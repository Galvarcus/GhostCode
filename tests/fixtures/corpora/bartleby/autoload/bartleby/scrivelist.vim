vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrivelist.vim: :BartlebyList. Finds the .bartleby folders in the
# binder root, keeps those with a valid project.json, and shows them in a
# popup list with title and type. CR opens the selection with
# :BartlebyOpen, so it works exactly like opening a scrive by name.
#
# With no valid scrive, as after a fresh install, it asks for a name and
# runs :BartlebyNewScrive instead of reporting an error.
#
# It reads project.json directly, not with Project.Load, because Load
# warns about a missing file, and a list should skip a stray folder
# quietly and report the count once.
#
# ScriveEntry is defined before the functions that use it because
# FindScrives and ReadEntry name it in their return types, and Vim9
# resolves a signature when the function is defined.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/scrive.vim' as S
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/views.vim' as MV
import 'bartleby/variables/constants.vim' as CO

const TYPE_SCRIVE_LIST_HEADER: string = 'ScriveListHeader'
const TYPE_SCRIVE_LIST_SEL: string = 'ScriveListSelected'

var log = L.New(expand('<sfile>:t'))

const COL_GAP: string = '    '
const MAX_VISIBLE_ROWS: number = 15
const SCRIVELIST_ZINDEX: number = 250

# CLASS: One valid scrive. name is the bare folder name, which
# :BartlebyOpen takes. title is the name in project.json, shown to the
# user.
export class ScriveEntry
  var name: string
  var title: string
  var projectType: string
endclass

# FUNCTION: Return every .bartleby folder directly under root, valid or
# not.
export def CandidateDirs(root: string): list<string>
  if !isdirectory(root)
    return []
  endif
  # nosuf true, so that a wildignore of the writer cannot hide a scrive.
  return globpath(root, '*' .. CO.SCRIVE_EXT, true, true)
    ->filter((_, p) => isdirectory(p))
enddef

# FUNCTION: Return a ScriveEntry for dir, or null_object when its
# project.json is missing, cannot be read, is not a JSON object, has no
# items list, or names an unknown project type. A missing or empty name
# falls back to the folder name, as in Project.Load.
export def ReadEntry(dir: string): ScriveEntry
  var path: string = dir .. '/' .. CO.PROJ_FILE
  if !filereadable(path)
    return null_object
  endif
  var data: any
  try
    data = json_decode(join(readfile(path), "\n"))
  catch
    return null_object
  endtry
  if type(data) != v:t_dict
    return null_object
  endif
  if type(get(data, 'items', 0)) != v:t_list
    return null_object
  endif
  var projectType: any = get(data, 'projectType', '')
  if type(projectType) != v:t_string || index(CO.TYPES, projectType) < 0
    return null_object
  endif
  var folderName: string = fnamemodify(dir, ':t:r')
  var title: any = get(data, 'name', '')
  if type(title) != v:t_string || title ==# ''
    title = folderName
  endif
  return ScriveEntry.new(folderName, title, projectType)
enddef

# FUNCTION: Return every valid scrive under root, or under the binder root
# when root is empty, sorted by title without regard to case.
export def FindScrives(root: string = ''): list<ScriveEntry>
  var scanRoot: string = root ==# '' ? S.BinderRoot() : root
  var entries: list<ScriveEntry> = []
  for dir in CandidateDirs(scanRoot)
    var entry: ScriveEntry = ReadEntry(dir)
    if entry isnot null_object
      entries->add(entry)
    endif
  endfor
  return entries->sort((a, b) => a.title ==? b.title ? 0 : (a.title >? b.title ? 1 : -1))
enddef

export def TypeLabel(projectType: string): string
  return get(PO.TypeNames(), projectType, projectType)
enddef

# FUNCTION: Run :BartlebyList.
export def Show(): void
  var dirs: list<string> = CandidateDirs(S.BinderRoot())
  var entries: list<ScriveEntry> = FindScrives()
  var skipped: number = len(dirs) - len(entries)
  if skipped > 0
    log.Warn(MV.SkippedFolderUnder(skipped, S.BinderRoot()))
  endif
  if empty(entries)
    PromptNewScrive()
    return
  endif
  ScriveListPopup.new(entries).Open()
enddef

def Pad(text: string, width: number): string
  return text .. repeat(' ', max([0, width - strdisplaywidth(text)]))
enddef

def PromptNewScrive(): void
  log.Info(MV.NoScrivesFound(S.BinderRoot()))
  IP.PromptText(MV.NoScrivesCreate(), '', (name: string) => {
    if name !=# ''
      execute $'BartlebyNewScrive {name}'
    endif
  })
enddef

class ScriveListPopup
  var entries: list<ScriveEntry>
  var titleWidth: number = 0
  var selectedIdx: number = 0
  var scrollOffset: number = 0
  var winid: number = -1
  var bufnr: number = -1

  def new(this.entries)
    this.titleWidth = strdisplaywidth(Headers()[0])
    for entry in this.entries
      this.titleWidth = max([this.titleWidth, strdisplaywidth(entry.title)])
    endfor
  enddef

  def FmtRow(title: string, typeLabel: string): string
    return Pad(title, this.titleWidth) .. COL_GAP .. typeLabel
  enddef

  def Width(): number
    var typeWidth: number = strdisplaywidth(Headers()[1])
    for entry in this.entries
      typeWidth = max([typeWidth, strdisplaywidth(TypeLabel(entry.projectType))])
    endfor
    return max([this.titleWidth + strdisplaywidth(COL_GAP) + typeWidth, 30])
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('ScriveListHeader'))
      prop_type_add('ScriveListHeader', {highlight: 'Title'})
    endif
    if empty(prop_type_get('ScriveListSelected'))
      prop_type_add('ScriveListSelected', {highlight: 'PmenuSel'})
    endif
  enddef

  def Open(): void
    this.EnsurePropTypes()
    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    var width: number = this.Width()
    var height: number = min([len(this.entries), MAX_VISIBLE_ROWS]) + 2
    this.winid = popup_create(this.bufnr, {
      title: printf(CO.TITLE_FMT, MV.Scrives()),
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      zindex: SCRIVELIST_ZINDEX,
      mapping: false,
      filter: (id, key) => this.Filter(id, key),
    })
    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid)
      this.winid = -1
    endif
  enddef

  def VisibleSlice(): list<number>
    if this.selectedIdx < this.scrollOffset
      this.scrollOffset = this.selectedIdx
    elseif this.selectedIdx >= this.scrollOffset + MAX_VISIBLE_ROWS
      this.scrollOffset = this.selectedIdx - MAX_VISIBLE_ROWS + 1
    endif
    return [this.scrollOffset, min([len(this.entries), this.scrollOffset + MAX_VISIBLE_ROWS])]
  enddef

  def Render(): void
    var header: string = this.FmtRow(Headers()[0], Headers()[1])
    var lines: list<string> = [header, repeat('-', this.Width())]
    var [first: number, last: number] = this.VisibleSlice()
    for i in range(first, last - 1)
      var entry: ScriveEntry = this.entries[i]
      lines->add(this.FmtRow(entry.title, TypeLabel(entry.projectType)))
    endfor

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    prop_remove({type: TYPE_SCRIVE_LIST_HEADER, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_SCRIVE_LIST_SEL, bufnr: this.bufnr}, 1, len(lines))
    prop_add(1, 1, {type: TYPE_SCRIVE_LIST_HEADER, bufnr: this.bufnr, length: strlen(header)})
    var selLnum: number = 3 + (this.selectedIdx - first)
    prop_add(selLnum, 1, {
      type: TYPE_SCRIVE_LIST_SEL, bufnr: this.bufnr,
      length: max([strlen(lines[selLnum - 1]), 1]),
    })
  enddef

  # METHOD: Open the selection with a timer after this popup filter call
  # returns, so the scrive's windows are never built inside a popup filter.
  def OpenSel(): void
    var name: string = this.entries[this.selectedIdx].name
    this.Close()
    timer_start(0, (_) => {
      execute $'BartlebyOpen {name}'
    })
  enddef

  def ShowHelp(): void
    H.Show(MV.Scrives(), [
      ['<CR>', MV.OpenSelScrive()],
      ['j / <Down>', MV.NextScrive()],
      ['k / <Up>', MV.PrevScrive()],
      ['q / <Esc>', MC.Close()],
      ['?', MC.Help()],
    ])
  enddef

  def Filter(winid: number, key: string): bool
    if key ==# 'j' || key ==# CO.KEY_DOWN
      this.selectedIdx = min([len(this.entries) - 1, this.selectedIdx + 1])
      this.Render()
    elseif key ==# 'k' || key ==# CO.KEY_UP
      this.selectedIdx = max([0, this.selectedIdx - 1])
      this.Render()
    elseif key ==# CO.KEY_CR
      this.OpenSel()
    elseif key ==# '?'
      this.ShowHelp()
    elseif key ==# 'q' || key ==# CO.KEY_ESC
      this.Close()
    endif
    return true
  enddef
endclass

# FUNCTION: Return the column headers in the message language.
def Headers(): list<string>
  return [MV.Title(), MV.Type()]
enddef
