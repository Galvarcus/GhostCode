vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inspector.vim: a read-only split on the right that shows the Title,
# Label, Status, Target, Keywords, and Synopsis of the document in the
# editor.
#
# The e key edits the field under the cursor with the fitting popup:
#   Label, Status  PickOne from picker.vim, as in the Binder.
#   Target         PromptText for a word count. 0 or empty clears it.
#   Keywords       PromptText, as the Binder uses for renaming.
#   Synopsis       PromptMultiline, because a synopsis can have several
#                  paragraphs.
# The title cannot be changed here. Rename with r in the Binder.
#
# Linked from lists the documents with a link to this one, see links.vim.
# e or Enter on one opens it.
#
# While it is open, the Inspector follows the document in the editor
# window. Opening another document, from the Binder, the Corkboard, the
# Outliner, or with :e, updates it through a BufEnter autocommand that
# ignores Bartleby's own panes, see IsChromeBuf in windows.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/progress.vim' as PG
import autoload 'bartleby/progressview.vim' as PV
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/panes.vim' as MP
import 'bartleby/variables/constants.vim' as CO

const INSPECTOR_PROJ: string = 'bartleby_inspector_project'
const INSPECTOR_ITEM: string = 'bartleby_inspector_item'
# The id of the document on each line of Linked from, by line number.
const INSPECTOR_LINKS: string = 'bartleby_inspector_links'
# Shown for an empty field or list.
const NONE_MARK: string = '-'

var log = L.New(expand('<sfile>:t'))

# Line numbers in the output of RenderContent, so that EditUnderCursor
# knows which field is on which line. Line 2, the title, has no
# constant: the title cannot be changed here.
const LINE_LABEL: number = 3
const LINE_STATUS: number = 4
const LINE_TARGET: number = 5
const LINE_KEYWORDS: number = 7
const LINE_SYNOPSIS_HEADER: number = 9

# FUNCTION: Return the field labels in the message language, each with
# its colon, because the punctuation differs between languages.
# syntax/bartleby-inspector.vim matches these labels.
export def FieldLabels(): dict<string>
  return {
    title: MP.Title(),
    label: MP.Label(),
    status: MP.Status(),
    target: MP.Target(),
    keywords: MP.Keywords(),
    synopsis: MP.Synopsis(),
  }
enddef

# FUNCTION: Return the lines of the Inspector for item, and the id of the
# document on each line of Linked from, by line number.
def RenderContent(project: PO.Project, item: BI.BinderItem, meta: D.DocMeta): list<any>
  var labels: dict<string> = FieldLabels()
  var lines: list<string> = [
    $'::{MP.Inspector()}::',
    $'{labels.title} {item.title}',
    $'{labels.label} {D.LabelName(meta.label)}',
    $'{labels.status} {D.StatusName(meta.status)}',
    $'{labels.target} {meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : NONE_MARK}',
    '',
    $'{labels.keywords} {join(meta.keywords, ", ")}',
    '',
    labels.synopsis,
  ]
  if meta.synopsis !=# ''
    lines += split(meta.synopsis, "\n")
  endif
  var links: dict<string> = {}
  # In a screenplay, [[ ]] is a Fountain note, not a link.
  if project.DocExt() !=# CO.EXT_FOUNTAIN
    lines += ['', LinkedHeader()]
    var folders: dict<string> = LK.Folders(project)
    var docs: list<BI.BinderItem> = LK.LinkedFrom(project, item)
    for d in docs
      links[string(len(lines) + 1)] = d.id
      lines->add(folders[d.id] ==# '' ? d.title : $'{d.title}  {folders[d.id]}')
    endfor
    if empty(docs)
      lines->add(NONE_MARK)
    endif
  endif
  var goals: list<string> = GoalLines()
  if !empty(goals)
    lines += [''] + goals
  endif
  return [lines, links]
enddef

# FUNCTION: Return the header of Linked from.
export def LinkedHeader(): string
  return $'::{MP.LinkedFrom()}::'
enddef

# FUNCTION: Return the lines of the writing goals that are set, under the
# header of GoalsHeader, or nothing when none is. See progress.vim.
def GoalLines(): list<string>
  var goals: dict<number> = PG.Goals()
  var written: dict<number> = PG.Written()
  var T = PG.Thousands
  var lines: list<string> = []
  if goals.session > 0
    lines->add($'{MP.Session()} {T(max([written.session, 0]))} / {T(goals.session)}')
  endif
  if goals.daily > 0
    lines->add($'{MP.Today()} {T(max([written.today, 0]))} / {T(goals.daily)}')
  endif
  var tracker: dict<any> = PG.Tracker()
  var f: dict<any> = PG.TrackerFigures(PG.DayOf(localtime()))
  if !empty(f)
    var gap: string = f.difference >= 0
      ? MC.Over(T(f.difference)) : MC.Under(T(-f.difference))
    lines->add(f.dayNumber == 0 ? $'{MP.Tracker()} {MP.Starts(tracker.start)}'
      : $'{MP.Tracker()} {MP.Day(min([f.dayNumber, tracker.days]), tracker.days)}, {gap}')
  endif
  return empty(lines) ? [] : [GoalsHeader()] + lines
enddef

# FUNCTION: Return the header of the goal lines.
def GoalsHeader(): string
  return $'::{MP.Goals()}::'
enddef

# FUNCTION: Write the Inspector buffer for item without moving the focus
# from the editor. setbufline, deletebufline, and setbufvar take a target
# buffer, so the editor window is not touched.
def RefreshFor(project: PO.Project, item: BI.BinderItem): void
  var bufNr: number = bufnr(CO.INSPECTOR_BUF)
  if bufNr == -1
    return
  endif
  var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
  setbufvar(bufNr, '&modifiable', 1)
  deletebufline(bufNr, 1, '$')
  var [lines, links] = RenderContent(project, item, meta)
  setbufline(bufNr, 1, lines)
  setbufvar(bufNr, '&modifiable', 0)
  setbufvar(bufNr, '&modified', 0)
  setbufvar(bufNr, INSPECTOR_PROJ, project)
  setbufvar(bufNr, INSPECTOR_ITEM, item)
  setbufvar(bufNr, INSPECTOR_LINKS, links)
enddef

def CurContext(): dict<any>
  return {
    project: get(b:, INSPECTOR_PROJ, null_object),
    item: get(b:, INSPECTOR_ITEM, null_object),
  }
enddef

def EditUnderCursor(): void
  var ctx: dict<any> = CurContext()
  if ctx.project is null_object || ctx.item is null_object
    return
  endif
  var project: PO.Project = ctx.project
  var item: BI.BinderItem = ctx.item
  var lnum: number = line('.')
  var lines: list<string> = getline(1, '$')
  var goalsIdx: number = index(lines, GoalsHeader())
  var linkedIdx: number = index(lines, LinkedHeader())

  if OpenLinked()
    return
  elseif lnum == LINE_LABEL
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    PI.PickOne(MC.Label(), CO.LABELS, (choice: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetLabel(choice)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    }, meta.label, D.LabelNames())
  elseif lnum == LINE_STATUS
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    PI.PickOne(MC.Status(), CO.STATUSES, (choice: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetStatus(choice)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    }, meta.status, D.StatusNames())
  elseif lnum == LINE_TARGET
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    var current: string = meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : ''
    IP.PromptText(MP.TargetWordCount(), current, (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetWordCountTarget(max([0, str2nr(text)]))
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  elseif lnum == LINE_KEYWORDS
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    IP.PromptText(MC.Keywords(), join(meta.keywords, ', '), (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetKeywords(text ==# '' ? [] : split(text, ',\s*'))
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  elseif goalsIdx >= 0 && lnum > goalsIdx
    # The goal lines, after the synopsis.
    PV.EditGoals()
  elseif linkedIdx >= 0 && lnum > linkedIdx
    # Linked from, after the synopsis, where a line without a document
    # does nothing.
    return
  elseif lnum >= LINE_SYNOPSIS_HEADER
    var meta: D.DocMeta = item.LoadMeta(project.BinderRoot())
    IP.PromptMultiline(MC.Synopsis(), meta.synopsis, (text: string) => {
      var m: D.DocMeta = item.LoadMeta(project.BinderRoot())
      m.SetSynopsis(text)
      m.Save(item.MetaPath(project.BinderRoot()))
      RefreshFor(project, item)
    })
  endif
enddef

# FUNCTION: Update the Inspector for the document that just became active
# in an editor window. Runs on every BufEnter while the Inspector is
# open. Ignores Bartleby's own panes, such as the Binder and the
# Inspector, and anything that is not a document of the open scrive.
def FollowEditor(): void
  # Closed in another way than with Toggle, the Inspector stops following,
  # so that this hook does not run for every buffer after it.
  if bufwinnr(CO.INSPECTOR_BUF) == -1
    augroup bartleby_inspector_follow
      autocmd!
    augroup END
    return
  endif
  if W.IsChromeBuf(bufnr('%'))
    return
  endif
  var project: PO.Project = ST.Get()
  if project is null_object
    return
  endif
  var item: BI.BinderItem = SV.DocHere(project)
  if item is null_object
    return
  endif
  RefreshFor(project, item)
enddef

# FUNCTION: Open the document on the line of Linked from under the
# cursor, and return whether the line has one.
def OpenLinked(): bool
  var project: PO.Project = get(b:, INSPECTOR_PROJ, null_object)
  var id: string = get(get(b:, INSPECTOR_LINKS, {}), string(line('.')), '')
  var doc: BI.BinderItem = id ==# '' || project is null_object ? null_object : project.FindItem(id)
  if doc is null_object
    return false
  endif
  B.OpenDoc(project, doc)
  return true
enddef

def SetupKeymaps(): void
  nnoremap <buffer> <silent> e <ScriptCmd>EditUnderCursor()<CR>
  nnoremap <buffer> <silent> <CR> <ScriptCmd>OpenLinked()<CR>
enddef

# FUNCTION: Open the Inspector for the document in the current window, or
# close it when it is open.
export def Toggle(): void
  var winNr: number = bufwinnr(CO.INSPECTOR_BUF)
  if winNr != -1
    execute ':' .. winNr .. 'close'
    augroup bartleby_inspector_follow
      autocmd!
    augroup END
    return
  endif

  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MP.NoScriveOpen())
    return
  endif
  var item: BI.BinderItem = SV.DocHere(project)
  if item is null_object
    log.Info(MP.CurBufNot())
    return
  endif

  execute 'vertical botright :40split ' .. CO.INSPECTOR_BUF
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal nonumber norelativenumber nofoldenable
  setlocal filetype=bartleby-inspector
  setlocal winfixwidth
  # The buffer stays while the Inspector is closed, with modifiable off and
  # the lines of the last document, so it is written as when it follows
  # the editor.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/1
  RefreshFor(project, item)
  SetupKeymaps()

  # In a Scrivening, the document changes without a change of buffer.
  augroup bartleby_inspector_follow
    autocmd!
    autocmd BufEnter * FollowEditor()
    execute 'autocmd User ' .. SV.SECTION_EVENT .. ' FollowEditor()'
    execute 'autocmd User ' .. PG.CHANGED_EVENT .. ' FollowEditor()'
  augroup END
enddef
