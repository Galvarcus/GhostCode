vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# mutate.vim: changes to the Binder tree: insert, remove, move, reparent,
# and rename. Pure data operations on the change methods of Project and
# BinderItem, with no UI and no saving. After a true result, the caller
# saves and draws again.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/templates.vim' as TE
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the nearest ancestor of row whose structureRole is
# role, or null_object when there is none below the top level.
export def FindAncestorWithRole(rows: list<T.Row>, row: T.Row, role: string): BI.BinderItem
  var current: BI.BinderItem = row is null_object ? null_object : row.ownerItem
  while current isnot null_object
    if current.structureRole ==# role
      return current
    endif
    var parentRow: T.Row = T.FindRowById(rows, current.id)
    current = parentRow is null_object ? null_object : parentRow.ownerItem
  endwhile
  return null_object
enddef

# FUNCTION: Return the one top-level folder of the scrive with role, or
# null_object when it is missing, as in a project older than roles.
export def FindTopWithRole(project: PO.Project, role: string): BI.BinderItem
  for i in range(project.ChildCount())
    if project.ChildAt(i).structureRole ==# role
      return project.ChildAt(i)
    endif
  endfor
  return null_object
enddef

# FUNCTION: Return the one top-level Manuscript folder of the scrive, or
# null_object when it is missing.
export def FindManuscript(project: PO.Project): BI.BinderItem
  return FindTopWithRole(project, CO.ROLE_MANUSCRIPT)
enddef

# FUNCTION: Return the next unused number title, 1, 2, and so on, among
# the siblings with role. templates.vim numbers the same way, so an empty
# title gives the same result as in a new scrive, and an import numbers a
# Part or a Chapter whose title repeats a sibling's.
export def NextRoleNum(siblings: list<BI.BinderItem>, role: string): string
  var n: number = 0
  for item in siblings
    if item.structureRole ==# role && item.title =~# '^\d\+$'
      n = max([n, str2nr(item.title)])
    endif
  endfor
  return string(n + 1)
enddef

# FUNCTION: Put newItem into the children of container: after the row at
# the cursor when that row is in container or is container, else at the
# end. The same rule as AddNear, but for one given container.
def AddIntoContainer(container: BI.BinderItem, row: T.Row, newItem: BI.BinderItem): void
  if row isnot null_object && row.ownerItem is container
    container.InsertChildAt(container.IdxOfChild(row.item.id) + 1, newItem)
  else
    container.AddChild(newItem)
  endif
enddef

# FUNCTION: Create a Chapter folder in container, which is the Manuscript
# folder for a Novel or a Part for a Novel with Parts. It holds a first
# document, Scene 1, which the caller creates on disk, as templates.vim
# does for a new scrive. An empty title becomes the next number among the
# sibling chapters.
export def AddChapter(container: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var chapterTitle: string = title ==# '' ? NextRoleNum(container.children, CO.ROLE_CHAPTER) : title
  var chapter: BI.BinderItem = BI.BinderItem.NewFolder(chapterTitle, CO.ROLE_CHAPTER)
  # The caller gives the scene its path with layout.Place, once the chapter
  # has its place in the tree.
  chapter.AddChild(BI.BinderItem.NewDocument(TE.FirstSceneTitle(), ''))
  AddIntoContainer(container, row, chapter)
  return chapter
enddef

# FUNCTION: Create an empty Part folder in the Manuscript folder, as the
# Part 2 of templates.vim starts empty. An empty title becomes the next
# number among the sibling parts.
export def AddPart(manuscript: BI.BinderItem, row: T.Row, title: string): BI.BinderItem
  var partTitle: string = title ==# '' ? NextRoleNum(manuscript.children, CO.ROLE_PART) : title
  var part: BI.BinderItem = BI.BinderItem.NewFolder(partTitle, CO.ROLE_PART)
  AddIntoContainer(manuscript, row, part)
  return part
enddef

# FUNCTION: Return true for the folders that the user must never
# restructure or lose: Front Matter, Manuscript, Back Matter, Characters,
# and Research. dd on one of them clears its contents instead of removing
# it, see DeleteUnderCursor in binder.vim. Rename, indent, and outdent are
# refused.
export def IsImmutableFolder(item: BI.BinderItem): bool
  return item.structureRole ==# CO.ROLE_FRONT_MATTER
    || item.structureRole ==# CO.ROLE_MANUSCRIPT
    || item.structureRole ==# CO.ROLE_BACK_MATTER
    || item.structureRole ==# CO.ROLE_CHARS
    || item.structureRole ==# CO.ROLE_RESEARCH
    || item.structureRole ==# CO.ROLE_TRASH
enddef

# FUNCTION: Return true when an item with role may be a child of parent,
# where null_object means the top level. ROLE_PART and ROLE_CHAPTER may
# be only under a ROLE_MANUSCRIPT folder, directly or inside a Part.
# ROLE_CUSTOM may be only at the top level. Other roles and all documents
# may be anywhere. Exported for import.vim, which gives an imported
# folder its role.
export def RoleAllowedUnder(role: string, parent: BI.BinderItem): bool
  if role ==# CO.ROLE_PART || role ==# CO.ROLE_CHAPTER
    return parent isnot null_object
      && (parent.structureRole ==# CO.ROLE_MANUSCRIPT || parent.structureRole ==# CO.ROLE_PART)
  endif
  if role ==# CO.ROLE_CUSTOM
    return parent is null_object
  endif
  if role ==# CO.ROLE_FRONT_MATTER || role ==# CO.ROLE_MANUSCRIPT
      || role ==# CO.ROLE_BACK_MATTER || role ==# CO.ROLE_CHARS
      || role ==# CO.ROLE_RESEARCH || role ==# CO.ROLE_TRASH
    return parent is null_object
  endif
  return true
enddef

# FUNCTION: Return the list that holds the item of row: the Project for a
# top-level row, else the folder that owns the row. Both implement
# ItemContainer, see binderitem.vim, so the callers need one code path.
def Owner(project: PO.Project, row: T.Row): BI.ItemContainer
  return row.ownerItem is null_object ? project : row.ownerItem
enddef

# FUNCTION: Insert newItem right after row, in the same list.
def InsertAfter(project: PO.Project, row: T.Row, newItem: BI.BinderItem): void
  var owner: BI.ItemContainer = Owner(project, row)
  owner.InsertChildAt(owner.IdxOfChild(row.item.id) + 1, newItem)
enddef

# FUNCTION: Add newItem next to row: as a child when row is a folder, else
# as the next sibling. row is null_object for an empty binder, or when
# there is no cursor row. Then newItem goes at the end of the top level.
export def AddNear(project: PO.Project, row: T.Row, newItem: BI.BinderItem): void
  if row is null_object
    project.AddChild(newItem)
  elseif row.item.IsFolder()
    row.item.AddChild(newItem)
  else
    InsertAfter(project, row, newItem)
  endif
enddef

# FUNCTION: Remove the item of row from the tree. Its files stay on disk:
# removing from the binder does not delete work.
export def Remove(project: PO.Project, row: T.Row): void
  var owner: BI.ItemContainer = Owner(project, row)
  owner.RemoveChildAt(owner.IdxOfChild(row.item.id))
enddef

# FUNCTION: Remove all children of item but keep item, for the five
# structural folders, where dd clears the contents. As with Remove, only
# the tree changes and files stay on disk.
export def ClearChildren(item: BI.BinderItem): void
  item.SetChildren([])
enddef

# FUNCTION: Swap the item of row with its next or previous sibling. delta
# is 1 to move down or -1 to move up. Returns false at the end of the
# list.
export def MoveWithinSiblings(project: PO.Project, row: T.Row, delta: number): bool
  if row.item.IsFolder() && row.item.structureRole !=# CO.ROLE_CHAPTER
      && row.item.structureRole !=# CO.ROLE_PART
    return false
  endif
  var owner: BI.ItemContainer = Owner(project, row)
  var idx: number = owner.IdxOfChild(row.item.id)
  var target: number = idx + delta
  if target < 0 || target >= owner.ChildCount()
      || owner.ChildAt(target).structureRole ==# CO.ROLE_TRASH
    return false
  endif
  owner.SwapChildren(idx, target)
  return true
enddef

# FUNCTION: Return the folders inside item, item included, whose role is
# role, in reading order.
def FoldersWithRole(item: BI.BinderItem, role: string): list<BI.BinderItem>
  var found: list<BI.BinderItem> = []
  if !item.IsFolder()
    return found
  endif
  if item.structureRole ==# role
    found->add(item)
  endif
  for child in item.children
    found += FoldersWithRole(child, role)
  endfor
  return found
enddef

# FUNCTION: Move the document of row into the next folder with the role of
# its own folder, as the first item, when delta is 1, or into the previous
# one, as the last item, when delta is -1. J and K use it at the edge of a
# folder. Only folders in the same top level folder count, in reading
# order, so a scene moves from the last chapter of a Part into the first
# chapter of the next Part. Returns the folder that the document moved
# into, or null_object for a folder, an item at the top level, or when
# there is no such folder.
export def MoveAcrossFolders(project: PO.Project, row: T.Row, delta: number): BI.BinderItem
  if row.item.IsFolder() || row.ownerItem is null_object
    return null_object
  endif
  var owner: BI.BinderItem = row.ownerItem
  for top in project.items
    # Scenes in the Trash wait there, see trash.vim.
    if top.structureRole ==# CO.ROLE_TRASH
      continue
    endif
    var folders: list<BI.BinderItem> = FoldersWithRole(top, owner.structureRole)
    var idx: number = indexof(folders, (_, folder) => folder.id ==# owner.id)
    if idx < 0
      continue
    endif
    var targetIdx: number = idx + delta
    if targetIdx < 0 || targetIdx >= len(folders)
      return null_object
    endif
    var target: BI.BinderItem = folders[targetIdx]
    owner.RemoveChildAt(owner.IdxOfChild(row.item.id))
    if delta > 0
      target.InsertChildAt(0, row.item)
    else
      target.AddChild(row.item)
    endif
    return target
  endfor
  return null_object
enddef

# FUNCTION: Return the folders that the item of row may move into with
# MoveInto, each as the list of folders from the top level down to it.
# The folder that holds the item, the item, and the folders inside it are
# left out, and so is each folder whose role rules refuse the item. A
# structural folder cannot move, so it gets an empty list.
export def MoveTargets(project: PO.Project, row: T.Row): list<list<BI.BinderItem>>
  var item: BI.BinderItem = row.item
  var targets: list<list<BI.BinderItem>> = []
  if IsImmutableFolder(item)
    return targets
  endif
  var ownerId: string = row.ownerItem is null_object ? '' : row.ownerItem.id
  def Walk(folders: list<BI.BinderItem>, path: list<BI.BinderItem>): void
    for folder in folders
      # The Trash takes items only through dd.
      if !folder.IsFolder() || folder.id ==# item.id || folder.structureRole ==# CO.ROLE_TRASH
        continue
      endif
      var here: list<BI.BinderItem> = path + [folder]
      if folder.id !=# ownerId && RoleAllowedUnder(item.structureRole, folder)
        targets->add(here)
      endif
      Walk(folder.children, here)
    endfor
  enddef
  Walk(project.items, [])
  return targets
enddef

# FUNCTION: Move the item of row to the end of the folder target.
export def MoveInto(project: PO.Project, row: T.Row, target: BI.BinderItem): void
  Remove(project, row)
  target.AddChild(row.item)
  # An item moved out of the Trash is restored.
  row.item.ClearTrashOrigin()
enddef

# FUNCTION: Move the item of row out of its owner folder, to right after
# that folder. Returns false when row is already at the top level.
export def Outdent(project: PO.Project, rows: list<T.Row>, row: T.Row): bool
  if row.ownerItem is null_object
    return false
  endif
  var grandparentRow: T.Row = T.FindRowById(rows, row.ownerItem.id)
  var newParent: BI.BinderItem = grandparentRow.ownerItem
  if !RoleAllowedUnder(row.item.structureRole, newParent)
    return false
  endif
  Remove(project, row)
  InsertAfter(project, grandparentRow, row.item)
  return true
enddef

# FUNCTION: Move the item of row into its previous sibling when that
# sibling is a folder. Returns false when there is no previous sibling
# or it is a document.
export def Indent(project: PO.Project, row: T.Row): bool
  var owner: BI.ItemContainer = Owner(project, row)
  var siblingIdx: number = owner.IdxOfChild(row.item.id) - 1
  if siblingIdx < 0
    return false
  endif
  var sibling: BI.BinderItem = owner.ChildAt(siblingIdx)
  # The Trash takes items only through dd, see trash.vim.
  if !sibling.IsFolder() || sibling.structureRole ==# CO.ROLE_TRASH
      || !RoleAllowedUnder(row.item.structureRole, sibling)
    return false
  endif
  sibling.AddChild(row.item)
  owner.RemoveChildAt(siblingIdx + 1)
  return true
enddef

export def Rename(row: T.Row, newTitle: string): void
  row.item.Rename(newTitle)
enddef
