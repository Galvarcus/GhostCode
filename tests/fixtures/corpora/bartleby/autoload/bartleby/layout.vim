vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# layout.vim: where the files of documents go on disk. A document lives in
# the folders of its place in the Binder, from the top level down, as in
# manuscript/part-1/chapter-2/Arrival.md for the scene Arrival in Chapter 2
# of Part 1. A document, and a folder that the writer named, take the
# title as it was typed, with a hyphen for every run of what a file
# system forbids. A folder that every scrive has takes its role instead,
# because its title comes from the locale. A chapter and a part take the
# role before the title. A title that keeps nothing becomes untitled, and
# a path in use gets -2, -3, and so on.
#
# New scrives, new documents, and new chapters get their paths from this
# layout. Tidy moves the files of a scrive whose documents moved in the
# Binder, so that the disk follows the Binder again. It moves through
# temporary names, so that two documents can trade places, and saves the
# project after each step, so that project.json always names the files on
# disk. The Trash is left as it is.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/slug.vim' as SU
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

# The folders that every scrive has. Each takes its role as its name,
# because the titles come from the locale, so a German scrive had
# vorspann and a Japanese one had untitled for all of them, and no
# reader of a project or of the documentation could rely on a path.
const PINNED: list<string> = [CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT,
  CO.ROLE_CHARS, CO.ROLE_RESEARCH, CO.ROLE_BACK_MATTER, CO.ROLE_TRASH]

# FUNCTION: Return the name on disk of title, or UNTITLED when the title
# keeps nothing.
def SlugOf(title: string): string
  var name: string = SU.Safe(title)
  return name ==# '' ? CO.UNTITLED : name
enddef

# FUNCTION: Return the name on disk of folder: its role for a folder that
# every scrive has, the role before the title for a chapter or a part, so
# that chapter 1 is chapter-1, and the title alone for a folder that the
# writer named.
export def FolderSlug(folder: BI.BinderItem): string
  var role: string = folder.structureRole
  if role ==# CO.ROLE_CHAPTER || role ==# CO.ROLE_PART
    return role .. SU.SEP .. SlugOf(folder.title)
  endif
  return index(PINNED, role) < 0 ? SlugOf(folder.title) : role
enddef

# FUNCTION: Return the path, without -2 and so on, and without the
# extension, of a document titled title inside folders, the folders from
# the top level down.
def BasePath(folders: list<BI.BinderItem>, title: string): string
  return folders->mapnew((_, f) => FolderSlug(f))->add(SlugOf(title))->join('/')
enddef

# FUNCTION: Return the one key to hold a path under while the layout asks
# whether it is already claimed. The case is folded whatever this system
# does with it, because the project is what travels: two names that
# differ only in case are two files here and one file on Windows or on a
# default macOS volume, and the second would overwrite the first. The two
# questions beside this one are different. A comparison of paths asks
# what this file system does, and keeps PA.Canon. The test that tells a
# file of this project from one the writer placed asks the same, and
# keeps PA.Folded.
def Key(relPath: string): string
  return tolower(relPath)
enddef

# FUNCTION: Return the first of base, base-2, base-3, and so on, with ext,
# that Taken does not report in use.
def FreePath(base: string, ext: string, Taken: func(string): bool): string
  var relPath: string = base .. ext
  var n: number = 2
  while Taken(relPath)
    relPath = $'{base}-{n}{ext}'
    n += 1
  endwhile
  return relPath
enddef

# FUNCTION: Return true when relPath is base with ext, or base with -2, -3,
# and so on, and ext: a path that the layout could give.
def FollowsLayout(relPath: string, base: string, ext: string): bool
  var key: string = Key(relPath)
  return key ==# Key(base .. ext)
    || key =~# CO.PAT_NOMAGIC_BOL .. escape(Key(base), '\') .. '-\d\+'
      .. escape(Key(ext), '\') .. '\$'
enddef

# FUNCTION: Call Visit for each document in items, with the folders from
# the top level down to it, after the folders in holding. The Trash is
# left out.
def EachDoc(items: list<BI.BinderItem>, holding: list<BI.BinderItem>,
    Visit: func(BI.BinderItem, list<BI.BinderItem>)): void
  for item in items
    if item.IsDoc()
      Visit(item, holding)
    elseif item.structureRole !=# CO.ROLE_TRASH
      EachDoc(item.children, holding + [item], Visit)
    endif
  endfor
enddef

# FUNCTION: Return the folders that hold the item with id, from the top
# level down, or an empty list for an item at the top level.
def HoldingFolders(project: PO.Project, id: string): list<BI.BinderItem>
  var byId: dict<T.Row> = {}
  for row in T.Flatten(project)
    byId[row.item.id] = row
  endfor
  var folders: list<BI.BinderItem> = []
  var owner: BI.BinderItem = has_key(byId, id) ? byId[id].ownerItem : null_object
  while owner isnot null_object
    folders->insert(owner)
    owner = byId[owner.id].ownerItem
  endwhile
  return folders
enddef

# FUNCTION: Return the paths of the documents of project, the Trash
# included, without those whose ids are in skip.
def UsedPaths(project: PO.Project, skip: dict<bool>): dict<bool>
  var used: dict<bool> = {}
  for row in T.Flatten(project)
    if row.item.IsDoc() && !has_key(skip, row.item.id)
      used[Key(row.item.relPath)] = true
    endif
  endfor
  return used
enddef

# FUNCTION: Give the documents of items, the starter tree of a new scrive,
# their paths, with ext. Nothing is on disk yet.
export def AssignPaths(items: list<BI.BinderItem>, ext: string): void
  var used: dict<bool> = {}
  EachDoc(items, [], (doc, folders) => {
    var relPath: string = FreePath(BasePath(folders, doc.title), ext,
      (p) => has_key(used, Key(p)))
    doc.SetRelPath(relPath)
    used[Key(relPath)] = true
  })
enddef

# FUNCTION: Give item, a document just added to the tree of project, or
# each document inside it when it is a folder, its path from its place,
# free in the tree and on disk.
export def Place(project: PO.Project, item: BI.BinderItem): void
  var holding: list<BI.BinderItem> = HoldingFolders(project, item.id)
  var docs: list<list<any>> = []
  if item.IsDoc()
    docs->add([item, holding])
  else
    EachDoc(item.children, holding + [item], (doc, folders) => {
      docs->add([doc, folders])
    })
  endif
  var placing: dict<bool> = {}
  for [doc, _] in docs
    placing[doc.id] = true
  endfor
  var used: dict<bool> = UsedPaths(project, placing)
  var root: string = project.BinderRoot()
  for [doc, folders] in docs
    var relPath: string = FreePath(BasePath(folders, doc.title), project.DocExt(),
      (p) => has_key(used, Key(p)) || filereadable(root .. '/' .. p))
    doc.SetRelPath(relPath)
    used[Key(relPath)] = true
  endfor
enddef

# FUNCTION: Return the moves that make the files of project follow the
# Binder: for each document outside the Trash whose path differs, its
# item, from, and to. A document whose path already follows the layout
# keeps it, so that a second tidy moves nothing. A file on disk that no
# document names is never written over, nor a path of the Trash.
export def Plan(project: PO.Project): list<dict<any>>
  var root: string = project.BinderRoot()
  var ext: string = project.DocExt()
  var docs: list<list<any>> = []
  EachDoc(project.items, [], (doc, folders) => {
    docs->add([doc, BasePath(folders, doc.title)])
  })
  # The paths of these documents may be given anew. Those of the Trash
  # stay. current pairs with filereadable below to tell a file of this
  # project from one the writer placed, so it asks what this file system
  # does with case, not what any file system might do, see Key.
  var current: dict<bool> = {}
  var ids: dict<bool> = {}
  for [doc, _] in docs
    current[PA.Folded(doc.relPath)] = true
    ids[doc.id] = true
  endfor
  var trashPaths: dict<bool> = UsedPaths(project, ids)
  # Documents whose paths already follow the layout keep them, first come.
  var assigned: dict<bool> = {}
  var kept: dict<bool> = {}
  for [doc, base] in docs
    if FollowsLayout(doc.relPath, base, ext) && !has_key(assigned, Key(doc.relPath))
        && !has_key(trashPaths, Key(doc.relPath))
      assigned[Key(doc.relPath)] = true
      kept[doc.id] = true
    endif
  endfor
  var moves: list<dict<any>> = []
  for [doc, base] in docs
    if has_key(kept, doc.id)
      continue
    endif
    var relPath: string = FreePath(base, ext,
      (p) => has_key(assigned, Key(p)) || has_key(trashPaths, Key(p))
        || (filereadable(root .. '/' .. p) && !has_key(current, PA.Folded(p))))
    assigned[Key(relPath)] = true
    moves->add({item: doc, from: doc.relPath, to: relPath})
  endfor
  return moves
enddef

# FUNCTION: Return the loaded buffers of the documents that moves move, as
# full path to buffer number.
# The keys are the one spelling of a path, see path.vim: a scrive stores
# forward slashes while Vim names a buffer with the separator of its own
# system, so a buffer went unfound and a tidy moved a document that the
# writer had not saved.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
def BufsOf(root: string, moves: list<dict<any>>): dict<number>
  var paths: dict<bool> = {}
  for move in moves
    paths[PA.Canon($'{root}/{move.from}')] = true
  endfor
  var found: dict<number> = {}
  for info in getbufinfo({bufloaded: 1})
    var path: string = PA.Canon(info.name)
    if info.name !=# '' && has_key(paths, path)
      found[path] = info.bufnr
    endif
  endfor
  return found
enddef

# FUNCTION: Move the text file of doc, and its metadata file when it has
# one, to newRelPath, and give doc that path. Returns false, and changes
# nothing, when a file cannot move.
def MoveDoc(root: string, doc: BI.BinderItem, newRelPath: string): bool
  var oldRelPath: string = doc.relPath
  var oldText: string = doc.AbsPath(root)
  var oldMeta: string = doc.MetaPath(root)
  # The metadata file follows the path of its document, see binderitem.vim.
  doc.SetRelPath(newRelPath)
  var newText: string = doc.AbsPath(root)
  var newMeta: string = doc.MetaPath(root)
  doc.SetRelPath(oldRelPath)
  mkdir(fnamemodify(newText, ':h'), 'p')
  var hasMeta: bool = filereadable(oldMeta)
  if hasMeta && rename(oldMeta, newMeta) != 0
    return false
  endif
  if filereadable(oldText) && rename(oldText, newText) != 0
    if hasMeta
      rename(newMeta, oldMeta)
    endif
    return false
  endif
  doc.SetRelPath(newRelPath)
  return true
enddef

# FUNCTION: Make the files of project follow the Binder with moves, the
# result of Plan. A document with unsaved changes stops it before any
# move. An open document opens again at its new path, at the same place.
# Returns the paths that could not move, or why nothing moved.
export def Tidy(project: PO.Project, moves: list<dict<any>>): list<string>
  var root: string = project.BinderRoot()
  # The Scrivening names its files, so its text is saved before they move.
  if !SV.SaveIfModified()
    return [CO.SCRIVENINGS_BUF]
  endif
  var bufs: dict<number> = BufsOf(root, moves)
  var unsaved: list<string> = bufs->keys()->filter((_, p) => getbufvar(bufs[p], '&modified'))
  if !empty(unsaved)
    return unsaved
  endif
  # Where each open document shows, to open it again there after the move.
  var views: list<dict<any>> = []
  for move in moves
    var path: string = PA.Canon($'{root}/{move.from}')
    if has_key(bufs, path)
      for winid in win_findbuf(bufs[path])
        var pos: list<number> = getcurpos(winid)
        views->add({winid: winid, item: move.item, lnum: pos[1], col: pos[2]})
      endfor
    endif
  endfor
  var failed: list<string> = []
  var oldDirs: list<string> = moves->mapnew((_, m) => fnamemodify(root .. '/' .. m.from, ':h'))
  # First to temporary names, with the extension, so that Recover still
  # finds a file if Vim stops here, then to the new paths.
  var moving: list<dict<any>> = []
  for move in moves
    var temporary: string = fnamemodify(move.from, ':r') .. '.tidy-' .. move.item.id .. project.DocExt()
    if MoveDoc(root, move.item, temporary)
      moving->add(move)
    else
      failed->add(move.from)
    endif
  endfor
  project.Save()
  for move in moving
    if !MoveDoc(root, move.item, move.to)
      failed->add(move.item.relPath)
    endif
  endfor
  project.Save()
  for dir in oldDirs
    PE.RemoveEmptyDirectories(dir, root)
  endfor
  # Open each document again in its windows before the old buffers go:
  # bwipe closes the windows that still show a buffer.
  for view in views
    if win_id2win(view.winid) > 0
      win_execute(view.winid, 'silent edit ' .. fnameescape(view.item.AbsPath(root)))
      win_execute(view.winid, $'cursor({view.lnum}, {view.col})')
    endif
  endfor
  for path in keys(bufs)
    if bufexists(bufs[path])
      execute 'silent! bwipe ' .. bufs[path]
    endif
  endfor
  return failed
enddef
