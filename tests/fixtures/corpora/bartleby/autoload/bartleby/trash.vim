vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# trash.vim: the Trash of the Binder. dd moves an item into the Trash, and
# its files stay on disk until the Trash deletes them for good. The Trash
# is a folder with ROLE_TRASH, always the last at the top level, see
# project.vim. Each item directly in it remembers its folder and its index
# there, so that Restore can put it back.
#
# The Trash shows only what is still on disk. An item with no file on disk
# is removed at once instead, and Prune drops items whose files were
# deleted outside Bartleby. Deleting for good removes the text file of
# each document, its metadata file, its snapshots, and each directory that
# is left empty, and never a path outside the scrive.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/tree.vim' as T
import 'bartleby/variables/constants.vim' as CO

const DEL_RECURSIVE: string = 'rf'

# FUNCTION: Return the ids of the items in the Trash, the Trash included,
# as a set.
export def IdsInTrash(project: PO.Project): dict<bool>
  var ids: dict<bool> = {}
  var trash: BI.BinderItem = project.TrashFolder()
  if trash isnot null_object
    ids[trash.id] = true
    for item in Descendants(trash)
      ids[item.id] = true
    endfor
  endif
  return ids
enddef

# FUNCTION: Return true when the item of row is the Trash or is inside it,
# from the top item of the row, without a walk of the tree.
export def RowInTrash(row: T.Row): bool
  return row.topItem isnot null_object && row.topItem.structureRole ==# CO.ROLE_TRASH
enddef

# FUNCTION: Return true when item is the Trash or is inside it.
export def IsInTrash(project: PO.Project, item: BI.BinderItem): bool
  return has_key(IdsInTrash(project), item.id)
enddef

# FUNCTION: Return true when a document of item, or item itself, has its
# text file on disk.
export def HasFilesOnDisk(project: PO.Project, item: BI.BinderItem): bool
  var root: string = project.BinderRoot()
  return Docs(item)->indexof((_, doc) => filereadable(doc.AbsPath(root))) >= 0
enddef

# FUNCTION: Move the item of row to the top of the Trash, where the item
# removed last is first, and remember its folder and index for Restore.
export def MoveToTrash(project: PO.Project, row: T.Row): void
  var owner: BI.ItemContainer = row.ownerItem is null_object ? project : row.ownerItem
  var idx: number = owner.IdxOfChild(row.item.id)
  owner.RemoveChildAt(idx)
  row.item.MarkTrashed(row.ownerItem is null_object ? '' : row.ownerItem.id, idx)
  project.TrashFolder().InsertChildAt(0, row.item)
enddef

# FUNCTION: Move every item of folder that has a file on disk to the Trash,
# and remove the rest, for dd on a structural folder, which stays. The
# first item ends at the top of the Trash.
export def MoveAllToTrash(project: PO.Project, folder: BI.BinderItem): void
  var trash: BI.BinderItem = project.TrashFolder()
  for idx in range(folder.ChildCount() - 1, 0, -1)
    var item: BI.BinderItem = folder.ChildAt(idx)
    folder.RemoveChildAt(idx)
    if HasFilesOnDisk(project, item)
      item.MarkTrashed(folder.id, idx)
      trash.InsertChildAt(0, item)
    endif
  endfor
enddef

# FUNCTION: Move the item of row, which must be directly in the Trash,
# back to its folder at its index, or as near as the folder now allows.
# Returns false, and leaves the item in the Trash, when that folder no
# longer exists outside the Trash.
export def Restore(project: PO.Project, row: T.Row): bool
  var item: BI.BinderItem = row.item
  var trash: BI.BinderItem = project.TrashFolder()
  if trash is null_object || row.ownerItem is null_object || row.ownerItem.id !=# trash.id
    return false
  endif
  var target: BI.ItemContainer = project
  # At the top level, the Trash stays last.
  var last: number = project.ChildCount() - 1
  if item.trashOrigin !=# ''
    var folder: BI.BinderItem = project.FindItem(item.trashOrigin)
    if folder is null_object || IsInTrash(project, folder)
      return false
    endif
    target = folder
    last = folder.ChildCount()
  endif
  trash.RemoveChildAt(trash.IdxOfChild(item.id))
  target.InsertChildAt(min([max([item.trashIndex, 0]), last]), item)
  item.ClearTrashOrigin()
  return true
enddef

# FUNCTION: Delete the files of the item of row for good, and remove it
# from the Trash. A buffer of a deleted file is wiped, so that it cannot
# write the file again. Returns the paths that were not deleted, such as
# a path that would leave the scrive.
export def DeleteForever(project: PO.Project, row: T.Row): list<string>
  var failed: list<string> = []
  var root: string = project.BinderRoot()
  for doc in Docs(row.item)
    if doc.relPath =~# '\.\.' || doc.relPath =~# '^/'
      failed->add(doc.relPath)
      continue
    endif
    for path in [doc.AbsPath(root), doc.MetaPath(root)]
      if !filereadable(path)
        continue
      endif
      if bufexists(path)
        execute 'silent! bwipe! ' .. bufnr(path)
      endif
      if delete(path) != 0
        failed->add(path)
      else
        PE.RemoveEmptyDirectories(fnamemodify(path, ':h'), root)
      endif
    endfor
    var snaps: string = SN.SnapDir(project, doc)
    if isdirectory(snaps) && delete(snaps, DEL_RECURSIVE) != 0
      failed->add(snaps)
    endif
  endfor
  var owner: BI.ItemContainer = row.ownerItem is null_object ? project : row.ownerItem
  owner.RemoveChildAt(owner.IdxOfChild(row.item.id))
  return failed
enddef

# FUNCTION: Delete everything in the Trash for good. Returns the paths that
# were not deleted.
export def EmptyTrash(project: PO.Project): list<string>
  var failed: list<string> = []
  var trash: BI.BinderItem = project.TrashFolder()
  if trash is null_object
    return failed
  endif
  var rows: list<T.Row> = T.Flatten(project)
  for item in copy(trash.children)
    failed += DeleteForever(project, T.FindRowById(rows, item.id))
  endfor
  return failed
enddef

# FUNCTION: Remove from the Trash each item, at any depth, that has no file
# left on disk, because its files were deleted outside Bartleby. Returns
# true when it removed something.
export def Prune(project: PO.Project): bool
  var trash: BI.BinderItem = project.TrashFolder()
  return trash isnot null_object && PruneFolder(project, trash)
enddef

def PruneFolder(project: PO.Project, folder: BI.BinderItem): bool
  var changed: bool = false
  for child in copy(folder.children)
    if !HasFilesOnDisk(project, child)
      folder.RemoveChildAt(folder.IdxOfChild(child.id))
      changed = true
    elseif child.IsFolder()
      changed = PruneFolder(project, child) || changed
    endif
  endfor
  return changed
enddef

# FUNCTION: Return the documents of item, or item itself when it is one.
def Docs(item: BI.BinderItem): list<BI.BinderItem>
  return item.IsDoc() ? [item] : Descendants(item)->filter((_, d) => d.IsDoc())
enddef

def Descendants(folder: BI.BinderItem): list<BI.BinderItem>
  var found: list<BI.BinderItem> = []
  for child in folder.children
    found->add(child)
    if child.IsFolder()
      found += Descendants(child)
    endif
  endfor
  return found
enddef
