vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# binder.vim: the Binder sidebar. Draws the scrive tree and sets the keys
# that ask for input or confirmation before mutate.vim changes the tree.
# Every change follows the same steps: get the input, call mutate.vim,
# call project.Save, and call Render.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/templates.vim' as TE
import autoload 'bartleby/corkboard.vim' as CR
import autoload 'bartleby/outliner.vim' as O
import autoload 'bartleby/search.vim' as SE
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/locale/binder.vim' as MB
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/doctemplates.vim' as DT
import autoload 'bartleby/import.vim' as IM
import 'bartleby/variables/constants.vim' as CO

# The choice of no template, which is no path.
const TMPL_BLANK: string = 'blank'

const ACTION_VIEW: string = 'View'
const KIND_CHAPTER: string = 'Chapter'
const KIND_PART: string = 'Part'
const KIND_CUSTOM: string = 'Custom'
const COLLAPSED: string = 'bartleby_collapsed'

var log = L.New(expand('<sfile>:t'))
var show_role_labels: bool = g:bartleby_binder_show_role_labels

# Render draws the title line, the project name, above the tree. Every
# mapping from a cursor line to a tree row subtracts this.
const HEADER_LINES: number = 1
const INDENT: string = '  '

def RenderLines(rows: list<T.Row>, binderRoot: string, collapsed: dict<bool>): list<string>
  return rows->mapnew((_, row) => {
    var marker: string = '· '
    if row.item.IsFolder()
      marker = get(collapsed, row.item.id, false) ? '▸ ' : '▾ '
    endif
    var suffix: string = ''
    if row.item.IsDoc()
      var meta: D.DocMeta = row.item.LoadMeta(binderRoot)
      if meta.label !=# CO.LABELS[0]
        suffix = $' ({D.LabelName(meta.label)})'
      endif
    endif
    var label: string = show_role_labels ? row.item.DisplayLabel() : ''
    # A trailing slash marks a folder, for the Directory highlight in
    # syntax/bartleby-binder.vim. Display only: the stored title has no slash.
    var title: string = row.item.IsFolder() ? row.item.title .. '/' : row.item.title
    return repeat(INDENT, row.depth) .. marker .. label .. title .. suffix
  })
enddef

def FindOrCreateWin(): number
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr != -1
    return winNr
  endif
  execute 'vertical topleft :30split ' .. CO.BINDER_BUF
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  # Long titles wrap at word boundaries. shift:2 starts each wrapped line
  # under the title text, after the marker.
  setlocal wrap linebreak breakindent breakindentopt=shift:2
  setlocal nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-binder
  setlocal winfixwidth
  return bufwinnr(CO.BINDER_BUF)
enddef

# FUNCTION: Draw the tree of project in the current window, which must
# already be the Binder, see Show. The rows of a collapsed folder are not
# drawn at all, see tree.vim Flatten. This is not a Vim fold. The
# collapsed folders are kept across renders in b:bartleby_collapsed.
def Render(project: PO.Project): void
  var prevRows: list<T.Row> = get(b:, 'bartleby_rows', [])
  var prevLine: number = line('.')
  var prevId: string = prevLine > HEADER_LINES && prevLine <= len(prevRows) + HEADER_LINES
    ? prevRows[prevLine - 1 - HEADER_LINES].item.id : ''

  var collapsed: dict<bool> = get(b:, 'bartleby_collapsed', {})
  var rows: list<T.Row> = T.Flatten(project, collapsed)
  setlocal modifiable
  deletebufline('%', 1, '$')
  setline(1, [$'{project.name}'] + RenderLines(rows, project.BinderRoot(), collapsed))
  setlocal nomodifiable
  b:bartleby_rows = rows
  b:bartleby_project = project

  # After deletebufline and setline, the cursor is on line 1. Put it back
  # on the same item, at its new line, when the item still exists.
  var newIdx: number = prevId ==# '' ? -1 : T.IdxOfRowById(rows, prevId)
  if newIdx >= 0
    cursor(newIdx + 1 + HEADER_LINES, 1)
  endif
  # The open Scrivening follows the changes of its folder.
  SV.SyncWithTree(project)
enddef

# FUNCTION: Return what every cursor command needs: the buffer's project,
# its rows, and the row under the cursor, or null_object when there is
# none, also on the title line.
def CursorContext(): dict<any>
  var project: PO.Project = get(b:, 'bartleby_project', null_object)
  var rows: list<T.Row> = get(b:, 'bartleby_rows', [])
  var lineNr: number = line('.')
  var row: T.Row = lineNr > HEADER_LINES && lineNr <= len(rows) + HEADER_LINES
    ? rows[lineNr - 1 - HEADER_LINES] : null_object
  return {project: project, rows: rows, row: row, lineNr: lineNr}
enddef

def OpenUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !ctx.row.item.IsDoc()
    ToggleCollapse()
    return
  endif
  OpenDoc(ctx.project, ctx.row.item)
enddef

# FUNCTION: Open a document in the edit window. A document of the open
# Scrivening shows there, not in a second buffer. The jump is in the
# jumplist, so Ctrl-O returns.
export def OpenDoc(project: PO.Project, item: BI.BinderItem): void
  normal! m'
  if SV.ShowDoc(item.id)
    return
  endif
  var path: string = item.AbsPath(project.BinderRoot())
  if !filereadable(path)
    log.Error(MC.MissingFileDisk(path))
    return
  endif
  W.GoToEditorWin()
  execute 'edit ' .. fnameescape(path)
enddef

# FUNCTION: Add a document titled title next to the item of row, with its
# file, holding lines, and return it.
export def AddDocNear(project: PO.Project, row: T.Row, title: string, lines: list<string> = []): BI.BinderItem
  var item: BI.BinderItem = BI.BinderItem.NewDocument(title, '')
  MU.AddNear(project, row, item)
  # Its path follows its place in the tree, see layout.vim.
  LY.Place(project, item)
  TE.Materialize([item], project.BinderRoot())
  if !empty(lines)
    writefile(lines, item.AbsPath(project.BinderRoot()))
  endif
  project.Save()
  RenderIfOpen(project)
  return item
enddef

# FUNCTION: Open a Scrivening of the folder under the cursor, or of the
# folder that holds the document under it, at that document.
export def OpenScrivening(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if ctx.row.item.IsFolder()
    SV.Open(ctx.project, ctx.row.item)
  elseif ctx.row.ownerItem isnot null_object
    SV.Open(ctx.project, ctx.row.ownerItem, ctx.row.item.id)
  else
    log.Info(MC.ScriveningOpensOnly())
  endif
enddef

def OpenCorkboard(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  var project: PO.Project = ctx.project
  CR.Show(project, ctx.row.item, (doc: BI.BinderItem) => {
    var path: string = doc.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Error(MC.MissingFileDisk(path))
      return
    endif
    W.GoToEditorWin()
    execute 'edit ' .. fnameescape(path)
  })
enddef

def TakeSnapshot(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDoc()
    return
  endif
  var project: PO.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  IP.PromptText(MC.SnapLabelOptional(), '', (label: string) => {
    SN.Take(project, doc, label)
  })
enddef

def ShowSnapReadOnly(doc: BI.BinderItem, snap: SN.Snap): void
  W.GoToEditorWin()
  execute 'enew'
  setline(1, snap.lines)
  execute 'silent file ' .. fnameescape($'[Snapshot] {doc.title} - {snap.DisplayName()}')
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable readonly
enddef

def ViewSnapshots(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDoc()
    return
  endif
  var project: PO.Project = ctx.project
  var doc: BI.BinderItem = ctx.row.item
  var snaps: list<SN.Snap> = reverse(SN.List(project, doc))
  if empty(snaps)
    log.Info(MC.NoSnaps(doc.title))
    return
  endif
  var names: list<string> = snaps->mapnew((_, s) => s.DisplayName())
  PI.PickOne(MC.Snaps(), names, (choice: string) => {
    var snap: SN.Snap = snaps[index(names, choice)]
    PI.PickOne(MC.Msg(choice), [CO.ACTION_RESTORE, ACTION_VIEW, CO.CANCEL], (action: string) => {
      if action ==# CO.ACTION_RESTORE
        SN.Restore(project, doc, snap)
      elseif action ==# ACTION_VIEW
        ShowSnapReadOnly(doc, snap)
      endif
    }, '', {[CO.ACTION_RESTORE]: MC.Restore(), [ACTION_VIEW]: MC.View(), [CO.CANCEL]: MC.Cancel()})
  })
enddef

def OpenOutliner(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  O.Show(ctx.project, ctx.row.item)
enddef

def RunSearch(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object
    return
  endif
  SE.Run(ctx.project)
enddef

def AddDoc(): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx)
    return
  endif
  if ctx.project is null_object
    return
  endif
  IP.PromptText(MB.NewDocTitle(), '', (title: string) => {
    FinishAddDoc(ctx, title)
  })
enddef

def FinishAddDoc(ctx: dict<any>, title: string): void
  if title ==# ''
    return
  endif
  AddDocAsked(ctx.project, ctx.row, title)
enddef

# FUNCTION: Add a document titled title next to row, and open it in the
# edit window. Where templates apply, see doctemplates.vim, ask for one
# first, or for a blank document.
export def AddDocAsked(project: PO.Project, row: T.Row, title: string): void
  var found: list<dict<string>> = DT.ForRow(project, row)
  if empty(found)
    OpenDoc(project, AddDocNear(project, row, title))
    return
  endif
  var names: dict<string> = {[TMPL_BLANK]: MB.Blank()}
  for t in found
    names[t.path] = t.name
  endfor
  PI.PickOne(MB.DocTemplate(), found->mapnew((_, t) => t.path) + [TMPL_BLANK], (path: string) => {
    OpenDoc(project, AddDocNear(project, row, title, path ==# TMPL_BLANK ? [] : DT.Lines(path, project, title)))
  }, found[0].path, names)
enddef

# FUNCTION: Return the row under the cursor when the current window shows
# the Binder of project, else null_object, where an import goes at the end
# of the top level. :BartlebyImport uses it, so that an import run from the
# Binder goes next to the item at the cursor.
export def CursorRow(project: PO.Project): T.Row
  if bufname() !=# CO.BINDER_BUF
    return null_object
  endif
  var ctx: dict<any> = CursorContext()
  return ctx.project is project ? ctx.row : null_object
enddef

# FUNCTION: Import paths next to row, save the project, draw the Binder
# again, and report what came in and what was skipped. The i key and
# :BartlebyImport both end here. A folder brings a tree of documents, so
# an import that holds one asks first, as a tidy does. See import.vim.
export def ImportPaths(project: PO.Project, row: T.Row, paths: list<string>): void
  if row isnot null_object && TR.RowInTrash(row)
    log.Info(MB.TrashRestoresMoves())
    return
  endif
  var importer: IM.Importer = IM.Importer.new(project)
  importer.Plan(paths)
  if importer.folders == 0
    FinishImport(project, importer, row)
    return
  endif
  DP.Confirm(MB.ImportDocFolder(importer.docs, MB.FolderAdded(importer.folders)), () => {
    FinishImport(project, importer, row)
  })
enddef

# FUNCTION: Add what the import planned, save, draw the Binder again, and
# report. A skip makes the report a warning.
def FinishImport(project: PO.Project, importer: IM.Importer, row: T.Row): void
  importer.Apply(row)
  if !empty(importer.added)
    project.Save()
    RenderIfOpen(project)
  endif
  if empty(importer.skipped)
    log.Info(importer.Report())
  else
    log.Warn(importer.Report())
  endif
enddef

# FUNCTION: Ask for one file and import it next to row, with Tab to
# complete the path. Several files come in through :BartlebyImport.
export def ImportPrompt(project: PO.Project, row: T.Row): void
  IP.PromptText(MB.FileToImport(), '', (path: string) => {
    if path !=# ''
      ImportPaths(project, row, IM.ExpandPaths([path]))
    endif
  }, null_function, CO.COMPLETE_FILE)
enddef

def ImportUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx) || ctx.project is null_object
    return
  endif
  ImportPrompt(ctx.project, ctx.row)
enddef

def AddFolder(): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx)
    return
  endif
  if ctx.project is null_object
    return
  endif
  var options: list<string> = [KIND_CUSTOM]
  if ctx.project.projectType ==# CO.TYPE_NOVEL
    options->add(KIND_CHAPTER)
  elseif ctx.project.projectType ==# CO.TYPE_NOVEL_PARTS
    options->add(KIND_PART)
    var onOrInsidePart: bool = (ctx.row isnot null_object && ctx.row.item.structureRole ==# CO.ROLE_PART)
      || MU.FindAncestorWithRole(ctx.rows, ctx.row, CO.ROLE_PART) isnot null_object
    if onOrInsidePart
      options->add(KIND_CHAPTER)
    endif
  endif
  if len(options) ==# 1
    CreateFolder(ctx, KIND_CUSTOM)
  else
    PI.PickOne(MB.AddFolder(), options, (choice: string) => {
      CreateFolder(ctx, choice)
    }, '', {[KIND_CUSTOM]: MB.Folder(), [KIND_CHAPTER]: MC.Chapter(), [KIND_PART]: MC.Part()})
  endif
enddef

def CreateFolder(ctx: dict<any>, kind: string): void
  var promptTitle: string = kind ==# KIND_CUSTOM ? MB.NewFolderTitle()
    : kind ==# KIND_PART ? MB.NewPartTitle()
    : MB.NewChapterTitle()
  IP.PromptText(promptTitle, '', (title: string) => {
    FinishCreateFolder(ctx, kind, title)
  })
enddef

def FinishCreateFolder(ctx: dict<any>, kind: string, title: string): void
  if kind ==# KIND_CUSTOM
    if title ==# ''
      return
    endif
    ctx.project.AddChild(BI.BinderItem.NewFolder(title, CO.ROLE_CUSTOM))
    ctx.project.Save()
    Render(ctx.project)
    return
  endif

  if kind ==# KIND_CHAPTER
    var container: BI.BinderItem
    if ctx.project.projectType ==# CO.TYPE_NOVEL_PARTS
      container = (ctx.row isnot null_object && ctx.row.item.structureRole ==# CO.ROLE_PART)
        ? ctx.row.item : MU.FindAncestorWithRole(ctx.rows, ctx.row, CO.ROLE_PART)
    else
      container = MU.FindManuscript(ctx.project)
    endif
    if container is null_object
      log.Error(MB.NoManuscriptPart())
      return
    endif
    var chapter: BI.BinderItem = MU.AddChapter(container, ctx.row, title)
    LY.Place(ctx.project, chapter)
    TE.Materialize([chapter], ctx.project.BinderRoot())
  else
    var manuscript: BI.BinderItem = MU.FindManuscript(ctx.project)
    if manuscript is null_object
      log.Error(MB.NoManuscriptFolder())
      return
    endif
    MU.AddPart(manuscript, ctx.row, title)
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

# FUNCTION: dd. Outside the Trash, move the item into it, without asking,
# because u brings it back. An item with no file on disk is removed at
# once, since the Trash shows only what is on disk. On a structural
# folder, move all its contents there, after a confirmation. In the
# Trash, delete the item and its files for good, and on the Trash itself,
# empty it, both after a confirmation.
def DeleteUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  var project: PO.Project = ctx.project
  var row: T.Row = ctx.row
  var item: BI.BinderItem = row.item

  if item.structureRole ==# CO.ROLE_TRASH
    EmptyTrash(project)
    return
  endif

  if TR.RowInTrash(row)
    DP.Confirm(MB.DeleteFilesGood(item.title), () => {
      ReportFailed(TR.DeleteForever(project, row))
      log.Info(MB.DeletedGood(item.title))
      project.Save()
      Render(project)
    })
    return
  endif

  if MU.IsImmutableFolder(item)
    if item.ChildCount() == 0
      log.Info(MB.AlreadyEmpty(item.title))
      return
    endif
    var clearPrompt: string = MB.MoveAllContents(item.title)
    DP.Confirm(clearPrompt, () => {
      TR.MoveAllToTrash(project, item)
      log.Info(MB.MovedContentsTrash(item.title))
      project.Save()
      Render(project)
    })
    return
  endif

  if TR.HasFilesOnDisk(project, item)
    TR.MoveToTrash(project, row)
    log.Info(MB.MovedTrash(item.title))
  else
    MU.Remove(project, row)
    log.Info(MB.RemovedWhichHad(item.title))
  endif
  project.Save()
  Render(project)
enddef

# FUNCTION: u. Put the item, which must be directly in the Trash, back
# where it was. When its folder is gone, ask where, with the picker of m.
def RestoreUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  if !TR.RowInTrash(ctx.row) || item.structureRole ==# CO.ROLE_TRASH
    log.Info(MB.RestoresItemTrash())
    return
  endif
  if ctx.row.ownerItem.structureRole !=# CO.ROLE_TRASH
    log.Info(MB.RestoreFolderHolds())
    return
  endif
  if TR.Restore(project, ctx.row)
    ShowItem(project, item)
    project.Save()
    Render(project)
    log.Info(MB.Restored(item.title))
  else
    log.Info(MB.FolderGoneChoose(item.title))
    MoveToUnderCursor()
  endif
enddef

# FUNCTION: Ask, then delete everything in the Trash for good. The
# command BartlebyEmptyTrash and dd on the Trash use it.
export def EmptyTrash(project: PO.Project): void
  var trash: BI.BinderItem = project.TrashFolder()
  var count: number = trash is null_object ? 0 : trash.ChildCount()
  if count == 0
    log.Info(MB.TrashEmpty())
    return
  endif
  DP.Confirm(MB.DeleteItemTrash(count), () => {
    ReportFailed(TR.EmptyTrash(project))
    log.Info(MB.EmptiedTrash())
    project.Save()
    RenderIfOpen(project)
  })
enddef

# FUNCTION: Warn about the paths that could not be deleted, if any.
def ReportFailed(failed: list<string>): void
  if !empty(failed)
    log.Warn(MB.CouldNotDelete(join(failed, ', ')))
  endif
enddef

# FUNCTION: Show the Binder again, from any window, when it is open.
export def RenderIfOpen(project: PO.Project): void
  var winid: number = bufwinid(CO.BINDER_BUF)
  if winid == -1
    return
  endif
  var current: number = win_getid()
  win_gotoid(winid)
  Render(project)
  win_gotoid(current)
enddef

# FUNCTION: Expand the folders that hold item, so that it shows.
def ShowItem(project: PO.Project, item: BI.BinderItem): void
  var byId: dict<T.Row> = RowsById(project)
  if has_key(byId, item.id) && byId[item.id].ownerItem isnot null_object
    ExpandUp(byId, byId[item.id].ownerItem.id)
  endif
enddef

# FUNCTION: Return true, with a message, when the item under the cursor is
# the Trash or in it, where only u, m, and dd act.
def RefusedInTrash(ctx: dict<any>): bool
  if ctx.project is null_object || ctx.row is null_object || !TR.RowInTrash(ctx.row)
    return false
  endif
  log.Info(MB.TrashRestoresMoves())
  return true
enddef

def RenameUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if MU.IsImmutableFolder(ctx.row.item)
    log.Info(MB.CannotRenamed(ctx.row.item.title))
    return
  endif
  var oldTitle: string = ctx.row.item.title
  IP.PromptText(MB.Rename(), oldTitle, (newTitle: string) => {
    if newTitle ==# '' || newTitle ==# oldTitle
      return
    endif
    MU.Rename(ctx.row, newTitle)
    ctx.project.Save()
    Render(ctx.project)
    LK.RefreshWindows(ctx.project)
    if ctx.row.item.IsDoc()
      LK.OfferRetarget(ctx.project, oldTitle, newTitle)
    endif
  })
enddef

def Move(delta: number): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx)
    return
  endif
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  # At the edge of its folder, a scene moves on into the next or previous
  # chapter.
  if !MU.MoveWithinSiblings(ctx.project, ctx.row, delta)
    var target: BI.BinderItem = MU.MoveAcrossFolders(ctx.project, ctx.row, delta)
    if target is null_object
      log.Info(MB.ItemCannotReordered())
      return
    endif
    ShowFolder(ctx.project, target)
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

# FUNCTION: Ask for a folder and move the item under the cursor to its
# end. The picker shows each folder with the folders above it, as in
# Manuscript / Part: 1 / Chapter: 3, because many chapters have the same
# title.
def MoveToUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  var targets: list<list<BI.BinderItem>> = MU.MoveTargets(ctx.project, ctx.row)
  if empty(targets)
    log.Info(MB.ItemCannotMoved())
    return
  endif
  var ids: list<string> = []
  var names: dict<string> = {}
  var folders: dict<BI.BinderItem> = {}
  var seen: dict<number> = {}
  for path in targets
    var folder: BI.BinderItem = path[-1]
    var name: string = path->mapnew((_, f) => f.DisplayLabel() .. f.title)->join(' / ')
    # Two folders with the same path get a number, so each name is unique.
    seen[name] = get(seen, name, 0) + 1
    ids->add(folder.id)
    names[folder.id] = seen[name] == 1 ? name : $'{name} {seen[name]}'
    folders[folder.id] = folder
  endfor
  var project: PO.Project = ctx.project
  var row: T.Row = ctx.row
  # The list is as wide as its longest name, so that no path is cut, but
  # never wider than the screen.
  var width: number = min([max(values(names)->mapnew((_, name) => strdisplaywidth(name))) + 4,
    &columns - 4])
  IP.PromptFilter(MB.Move(), ids, (id: string) => {
    MU.MoveInto(project, row, folders[id])
    ShowFolder(project, folders[id])
    project.Save()
    Render(project)
  }, 12, width, names)
enddef

# FUNCTION: Expand folder and the folders that hold it, so that an item
# just moved into it shows, with the cursor still on it.
def ShowFolder(project: PO.Project, folder: BI.BinderItem): void
  ExpandUp(RowsById(project), folder.id)
enddef

# FUNCTION: Return the rows of the whole tree by the id of their item, so
# that a walk up to the top level takes one step per folder.
def RowsById(project: PO.Project): dict<T.Row>
  var byId: dict<T.Row> = {}
  for row in T.Flatten(project)
    byId[row.item.id] = row
  endfor
  return byId
enddef

# FUNCTION: Expand the folder with id and the folders that hold it, and
# save the collapsed folders in the session.
def ExpandUp(byId: dict<T.Row>, id: string): void
  var collapsed: dict<bool> = get(b:, 'bartleby_collapsed', {})
  var current: string = id
  while has_key(byId, current)
    if has_key(collapsed, current)
      remove(collapsed, current)
    endif
    var owner: BI.BinderItem = byId[current].ownerItem
    current = owner is null_object ? '' : owner.id
  endwhile
  b:bartleby_collapsed = collapsed
  SS.CaptureBinderState(IsOpen(), GetCollapsedIds())
enddef

def IndentUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx)
    return
  endif
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !MU.Indent(ctx.project, ctx.row)
    log.Info(MB.NoValidFolder())
    return
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def OutdentUnderCursor(): void
  var ctx: dict<any> = CursorContext()
  if RefusedInTrash(ctx)
    return
  endif
  if ctx.project is null_object || ctx.row is null_object
    return
  endif
  if !MU.Outdent(ctx.project, ctx.rows, ctx.row)
    log.Info(MB.AlreadyTopLevel())
    return
  endif
  ctx.project.Save()
  Render(ctx.project)
enddef

def PickLabel(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDoc()
    return
  endif
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var curMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  PI.PickOne(MC.Label(), CO.LABELS, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetLabel(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, curMeta.label, D.LabelNames())
enddef

def PickStatus(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsDoc()
    return
  endif
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.row.item
  var curMeta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  PI.PickOne(MC.Status(), CO.STATUSES, (choice: string) => {
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    meta.SetStatus(choice)
    meta.Save(item.MetaPath(project.BinderRoot()))
    Render(project)
  }, curMeta.status, D.StatusNames())
enddef

# FUNCTION: Show or hide the Chapter and Part prefixes and draw again.
# The setting applies to the whole session, not only to this buffer.
def ToggleRoleLabels(): void
  show_role_labels = !show_role_labels
  var project: PO.Project = get(b:, 'bartleby_project', null_object)
  if project isnot null_object
    Render(project)
  endif
enddef

def ShowHelp(): void
  H.Show(MC.Binder(), [
    ['<CR>', MB.OpenDocToggle()],
    ['<Tab>', MB.ToggleFolderCollapse()],
    ['a', MB.NewDoc()],
    ['A', MB.NewFolderChapter()],
    ['i', MB.ImportFile()],
    ['dd', MB.MoveItemTrash()],
    ['u', MB.RestoreItemTrash()],
    ['r', MB.RenameItemUnder()],
    ['J / K', MB.MoveItemDown()],
    ['m', MB.MoveItemAnother()],
    ['>> / <<', MB.IndentOutdentItem()],
    ['l', MC.SetLabel()],
    ['s', MC.SetStatus()],
    ['L', MB.ToggleChapterPart()],
    ['S', MB.TakeSnap()],
    ['gS', MB.ViewRestoreSnaps()],
    ['gc', MB.OpenCorkboard()],
    ['go', MB.OpenOutliner()],
    ['v', MC.OpenScrivening()],
    ['/', MB.SearchProj()],
    ['q', MB.CloseBinder()],
    ['?', MC.Help()],
  ])
enddef

def ToggleCollapse(): void
  var ctx: dict<any> = CursorContext()
  if ctx.project is null_object || ctx.row is null_object || !ctx.row.item.IsFolder()
    return
  endif
  var collapsed: dict<bool> = get(b:, 'bartleby_collapsed', {})
  var id: string = ctx.row.item.id
  if get(collapsed, id, false)
    remove(collapsed, id)
  else
    collapsed[id] = true
  endif
  b:bartleby_collapsed = collapsed
  Render(ctx.project)
  SS.CaptureBinderState(IsOpen(), GetCollapsedIds())
enddef

def SetupKeymaps(): void
  nnoremap <buffer> <silent> <CR> <ScriptCmd>OpenUnderCursor()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>close<CR>
  nnoremap <buffer> <silent> <Tab> <ScriptCmd>ToggleCollapse()<CR>
  nnoremap <buffer> <silent> a <ScriptCmd>AddDoc()<CR>
  nnoremap <buffer> <silent> A <ScriptCmd>AddFolder()<CR>
  nnoremap <buffer> <silent> i <ScriptCmd>ImportUnderCursor()<CR>
  nnoremap <buffer> <silent> dd <ScriptCmd>DeleteUnderCursor()<CR>
  nnoremap <buffer> <silent> u <ScriptCmd>RestoreUnderCursor()<CR>
  nnoremap <buffer> <silent> r <ScriptCmd>RenameUnderCursor()<CR>
  nnoremap <buffer> <silent> J <ScriptCmd>Move(1)<CR>
  nnoremap <buffer> <silent> K <ScriptCmd>Move(-1)<CR>
  nnoremap <buffer> <silent> m <ScriptCmd>MoveToUnderCursor()<CR>
  nnoremap <buffer> <silent> >> <ScriptCmd>IndentUnderCursor()<CR>
  nnoremap <buffer> <silent> << <ScriptCmd>OutdentUnderCursor()<CR>
  nnoremap <buffer> <silent> l <ScriptCmd>PickLabel()<CR>
  nnoremap <buffer> <silent> s <ScriptCmd>PickStatus()<CR>
  nnoremap <buffer> <silent> L <ScriptCmd>ToggleRoleLabels()<CR>
  nnoremap <buffer> <silent> S <ScriptCmd>TakeSnapshot()<CR>
  nnoremap <buffer> <silent> gS <ScriptCmd>ViewSnapshots()<CR>
  nnoremap <buffer> <silent> gc <ScriptCmd>OpenCorkboard()<CR>
  nnoremap <buffer> <silent> go <ScriptCmd>OpenOutliner()<CR>
  nnoremap <buffer> <silent> v <ScriptCmd>OpenScrivening()<CR>
  nnoremap <buffer> <silent> / <ScriptCmd>RunSearch()<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowHelp()<CR>
enddef

# FUNCTION: Draw the tree of project in the sidebar, and create the
# sidebar if needed.
export def Show(project: PO.Project): void
  var winNr: number = FindOrCreateWin()
  execute ':' .. winNr .. 'wincmd w'
  # Drop what was deleted from the Trash outside Bartleby.
  if TR.Prune(project)
    project.Save()
  endif
  Render(project)
  SetupKeymaps()
enddef

export def Toggle(project: PO.Project): void
  var winNr: number = bufwinnr(CO.BINDER_BUF)
  if winNr != -1
    execute ':' .. winNr .. 'close'
    SS.CaptureBinderState(IsOpen(), GetCollapsedIds())
    return
  endif
  Show(project)
  SS.CaptureBinderState(IsOpen(), GetCollapsedIds())
enddef

export def IsOpen(): bool
  return bufwinnr(CO.BINDER_BUF) != -1
enddef

# FUNCTION: Return the ids of the collapsed folders, for the session. The
# set lives in b:bartleby_collapsed on the Binder buffer, and other
# scripts use these two functions instead of that variable. They read the
# buffer, not the window: the buffer stays loaded while the Binder is
# closed, and Toggle saves the state after the window has closed.
export def GetCollapsedIds(): list<string>
  var buf: number = bufnr(CO.BINDER_BUF)
  return buf == -1 ? [] : keys(getbufvar(buf, COLLAPSED, {}))
enddef

export def ApplyCollapsedIds(ids: list<string>): void
  var buf: number = bufnr(CO.BINDER_BUF)
  if buf == -1
    return
  endif
  var collapsed: dict<bool> = {}
  for id in ids
    collapsed[id] = true
  endfor
  setbufvar(buf, COLLAPSED, collapsed)
enddef
