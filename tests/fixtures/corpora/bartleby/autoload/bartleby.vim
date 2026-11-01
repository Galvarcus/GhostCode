vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby.vim: the functions that plugin/bartleby.vim calls from
# its commands and autocommands. They live here, not in the plugin file, so
# that Vim loads them, and the scripts and the logger that they import, the
# first time that one is used, not every time that Vim starts.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as S
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/search.vim' as SE
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/restore.vim' as R
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/scrivelist.vim' as SL
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/recover.vim' as RC
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/progress.vim' as PG
import autoload 'bartleby/import.vim' as IM
import autoload 'bartleby/import_map.vim' as IMM
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))
var link_complete: bool = g:bartleby_link_complete
var link_highlight: bool = g:bartleby_link_highlight

export def OpenScrive(name: string): void
  var scriveName: string = name ==# '' ? fnamemodify(SS.LastScrive(), ':t:r') : name
  if scriveName ==# ''
    log.Warn(MI.NoScriveName())
    SL.Show()
    return
  endif
  var project: PO.Project = S.Open(scriveName)
  if project is null_object
    # A last scrive that was moved or deleted gets the same fallback as no
    # last scrive. A typed name that is wrong does not: its error is enough.
    if name ==# ''
      SL.Show()
    endif
    return
  endif
  ST.Set(project)
  StartScriveHooks()
  SS.RememberLastScrive(project.scriveDir)
  R.Restore(project)
enddef
# FUNCTION: Ask for the scrive type with PickOne, as the other pickers
# do, then create the scrive. Esc creates nothing.
export def NewScrive(name: string): void
  PI.PickOne(MI.ScriveType(), CO.TYPES, (projectType: string) => {
    CreateScrive(name, projectType)
  }, CO.TYPE_NOVEL, PO.TypeNames())
enddef
# FUNCTION: Create a scrive from an existing file or folder: ask for the
# name, with the name of the source offered, then for the type, as
# NewScrive does, and import the source into the Manuscript of the new
# scrive. See CreateFrom in scrive.vim.
export def NewScriveFrom(path: string): void
  var src: string = IM.ExpandPaths([path])[0]
  if !isdirectory(src) && !filereadable(src)
    log.Error(MI.NoFileFolder(src))
    return
  endif
  IP.PromptText(MI.NewScrive(), SourceName(src), (name: string) => {
    if name ==# ''
      return
    endif
    # The export of a project says which type it needs, so the picker opens
    # on that one and the writer only confirms it.
    var detected: string = IMM.ProjectType(src)
    PI.PickOne(MI.ScriveType(), CO.TYPES, (projectType: string) => {
      OpenFromImport(name, projectType, src)
    }, detected ==# '' ? CO.TYPE_NOVEL : detected, PO.TypeNames())
  })
enddef
# FUNCTION: Return the name to offer for a scrive made from src: the name
# of the folder, or the name of the file without its extension.
def SourceName(src: string): string
  var bare: string = substitute(src, '[/\\]$', '', '')
  return isdirectory(src) ? fnamemodify(bare, ':t') : fnamemodify(bare, ':t:r')
enddef
# FUNCTION: Create the scrive from src, open it, and report what came in.
def OpenFromImport(name: string, projectType: string, src: string): void
  var importer: IM.Importer = S.CreateFrom(name, projectType, src)
  if importer is null_object
    # Create reports a name that is already a scrive, and leaves that
    # scrive as it is, so a folder that is still there means that. The
    # other reason is a source with nothing in it to import.
    if !isdirectory(S.ScrivePath(name))
      log.Error(MI.NothingImported(src))
    endif
    return
  endif
  var project: PO.Project = importer.project
  ST.Set(project)
  StartScriveHooks()
  SS.RememberLastScrive(project.scriveDir)
  B.Show(project)
  if empty(importer.skipped)
    log.Info(importer.Report())
  else
    log.Warn(importer.Report())
  endif
enddef
export def CreateScrive(name: string, projectType: string): void
  var project: PO.Project = S.Create(name, projectType)
  if project is null_object
    return
  endif
  ST.Set(project)
  StartScriveHooks()
  SS.RememberLastScrive(project.scriveDir)
  B.Show(project)
enddef
export def ToggleBinder(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  B.Toggle(ST.Get())
enddef
export def RunSearch(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  SE.Run(ST.Get())
enddef
export def EditProjectInfo(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  PR.EditForScrive(ST.Get())
enddef
# FUNCTION: Return the BinderItem of the current buffer in the open
# scrive, or null_object with a warning when no scrive is open or the
# buffer is not one of its documents.
export def CurDoc(): BI.BinderItem
  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MC.NoScriveOpen())
    return null_object
  endif
  var doc: BI.BinderItem = SV.DocHere(project)
  if doc is null_object
    log.Warn(MI.CurBufNot())
  endif
  return doc
enddef
export def SnapCurDoc(): void
  var project: PO.Project = ST.Get()
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  IP.PromptText(MC.SnapLabelOptional(), '', (label: string) => {
    SN.Take(project, doc, label)
  })
enddef
export def ViewSnapsForCurDoc(): void
  var project: PO.Project = ST.Get()
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  var snaps: list<SN.Snap> = reverse(SN.List(project, doc))
  if empty(snaps)
    log.Info(MC.NoSnaps(doc.title))
    return
  endif
  var names: list<string> = snaps->mapnew((_, s) => s.DisplayName())
  PI.PickOne(MC.Snaps(), names, (choice: string) => {
    var snap: SN.Snap = snaps[index(names, choice)]
    PI.PickOne(MC.Msg(choice), [CO.ACTION_RESTORE, CO.CANCEL], (action: string) => {
      if action ==# CO.ACTION_RESTORE
        SN.Restore(project, doc, snap)
      endif
    }, '', {[CO.ACTION_RESTORE]: MC.Restore(), [CO.CANCEL]: MC.Cancel()})
  })
enddef
export def RunCompile(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  C.Run(ST.Get())
enddef
export def EmptyTrash(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  B.EmptyTrash(ST.Get())
enddef
# FUNCTION: Recover the documents that are on disk but not in the Binder.
# With no name, into the open scrive. With the name of a scrive whose
# project.json does not load, rebuild its Binder after a confirmation, see
# recover.vim, and open it.
export def Recover(name: string): void
  if name ==# ''
    var project: PO.Project = ST.Get()
    if project is null_object
      log.Warn(MI.NoScriveOpen())
      return
    endif
    var count: number = RC.Recover(project)
    if count == 0
      log.Info(MI.EveryDocDisk())
      return
    endif
    project.Save()
    B.RenderIfOpen(project)
    log.Info(MI.RecoveredDocFolder(count))
    return
  endif
  var dir: string = S.ScrivePath(S.ResolveName(name))
  if !isdirectory(dir)
    log.Error(MC.NoScriveNamed(name, S.BinderRoot()))
    return
  endif
  if PO.Project.new(dir).Load()
    log.Info(MI.OpensOpenThen(name))
    return
  endif
  DP.Confirm(MI.RebuildBinderDamaged(name), () => {
    if RC.Rebuild(dir) isnot null_object
      OpenScrive(fnamemodify(dir, ':t:r'))
    endif
  })
enddef
# FUNCTION: Move the files of the open scrive, so that the folders on disk
# follow the Binder, after a confirmation that says how many move. See
# layout.vim.
export def TidyFiles(): void
  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  var moves: list<dict<any>> = LY.Plan(project)
  if empty(moves)
    log.Info(MI.FilesAlreadyFollow())
    return
  endif
  DP.Confirm(MI.MoveFileSo(len(moves)), () => {
    var failed: list<string> = LY.Tidy(project, moves)
    B.RenderIfOpen(project)
    if empty(failed)
      log.Info(MI.MovedFile(len(moves)))
    else
      log.Warn(MI.FilesDidNot(
        join(failed, ', ')))
    endif
  })
enddef
# FUNCTION: Import files into the open scrive, next to the item under the
# Binder cursor when the Binder is the current window, else at the end of
# the top level. With no path, ask for one. A path may hold ~ and
# wildcards. See import.vim.
export def Import(paths: list<string>): void
  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  var row: T.Row = B.CursorRow(project)
  if empty(paths)
    B.ImportPrompt(project, row)
    return
  endif
  B.ImportPaths(project, row, IM.ExpandPaths(paths))
enddef
# FUNCTION: Open a Scrivening: from the Binder, of the folder under its
# cursor, and from a document, of the folder that holds it, at the line of
# the cursor. With close, save and close the open one instead. See
# scrivenings.vim.
export def OpenScrivening(close: bool): void
  if close
    if !SV.IsOpen()
      log.Info(MI.NoScriveningOpen())
    elseif !SV.Close()
      log.Warn(MI.ScriveningStaysOpen())
    endif
    return
  endif
  if bufname() ==# CO.BINDER_BUF
    B.OpenScrivening()
    return
  endif
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  var project: PO.Project = ST.Get()
  var row: T.Row = T.FindRowById(T.Flatten(project), doc.id)
  if row is null_object || row.ownerItem is null_object
    log.Info(MC.ScriveningOpensOnly())
    return
  endif
  var offset: number = SV.IsScrivening(bufnr()) ? SV.LineInDoc() - 1 : line('.') - 1
  SV.Open(project, row.ownerItem, doc.id, offset)
enddef
# FUNCTION: Start the hooks that serve an open scrive. Until a scrive
# opens, Vim runs none of them for the buffers it enters.
export def StartScriveHooks(): void
  augroup bartleby_quill_auto
    autocmd!
    autocmd BufEnter * Q.AutoApply()
  augroup END
  augroup bartleby_links_auto
    autocmd!
    autocmd BufEnter,WinEnter * EnterLinkDoc()
    autocmd TextChanged,InsertLeave * RefreshLinks()
  augroup END
  # An empty edit window stays when the last one closes beside a pane.
  W.WatchEditWin()
  # Count the words for the goals on pauses and saves, never on each key.
  augroup bartleby_progress
    autocmd!
    autocmd CursorHold,CursorHoldI,InsertLeave,BufWritePost,BufEnter * PG.Refresh()
  augroup END
  PG.Refresh()
  SetupStatusline()
enddef
# FUNCTION: On entering a buffer that holds documents of the open scrive
# in prose, where [[ ]] is a link, map [ to offer the titles and
# highlight the links. In a screenplay, [[ ]] is a Fountain note. The
# result is kept in b:bartleby_link_doc, so that an edit does not look up
# the document again. Exported for the tests.
export def EnterLinkDoc(): void
  var project: PO.Project = ST.Get()
  b:bartleby_link_doc = !W.IsChromeBuf(bufnr()) && project isnot null_object
    && project.DocExt() !=# CO.EXT_FOUNTAIN && SV.DocHere(project) isnot null_object
  if !b:bartleby_link_doc
    return
  endif
  if link_complete && !exists('b:bartleby_links_mapped')
    b:bartleby_links_mapped = true
    inoremap <buffer> [ [<ScriptCmd>LK.CompleteTitles()<CR>
    inoremap <buffer> # #<ScriptCmd>LK.CompleteHeadings()<CR>
  endif
  RefreshLinks()
enddef

def RefreshLinks(): void
  var project: PO.Project = ST.Get()
  if link_highlight && get(b:, 'bartleby_link_doc', false) && project isnot null_object
    LK.Highlight(project, bufnr())
  endif
enddef
# FUNCTION: Add the writing progress to the status line, when the status
# line has no setting of its own and vim-airline does not draw it, as the
# default status line of Vim, with the ruler. See progress.vim. It waits
# for a scrive, so that Vim loads this script only for Bartleby.
def SetupStatusline(): void
  if !g:bartleby_statusline || exists('g:loaded_airline') || &g:statusline !=# ''
    return
  endif
  &g:statusline = '%<%f %h%m%r%=%( %{bartleby#progress#Status()}  %)%-14.(%l,%c%V%) %P'
enddef
export def AutoRestoreSession(): void
  if SS.LastScrive() !=# ''
    OpenScrive('')
  endif
enddef
