vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexiconpopup.vim: the popups of :BartlebyDefine and :BartlebyThesaurus.
# The lookups are in lexicon.vim.
#
# The popup opens at once with a Looking up message and fills in when the
# request ends. It opens below the cursor in the current window, so it
# works the same in a scrive's editor window and in Focus.
#
# A lookup of the word under the cursor, or of a Visual selection on one
# line, records the exact position of that word as the target. CR on a
# thesaurus word writes it over the target, with the target's
# capitalization, as one undo step. If the target text changed meanwhile,
# the write is skipped with a warning. A lookup of a typed word, as in
# :BartlebyThesaurus word, has no target, so CR copies the word to the
# unnamed register.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/compile.vim' as MK
import autoload 'bartleby/lexicon_result.vim' as LR
import 'bartleby/variables/constants.vim' as CO

const HL_COMMENT: string = 'Comment'
const POS_TOPLEFT: string = 'topleft'
const HL_LEXICON_COMMENT: string = 'LexiconComment'
const HL_LEXICON_ERR: string = 'LexiconError'
const HL_LEXICON_TITLE: string = 'LexiconTitle'
const ACTION_LOOKUP: string = 'lookup'
const ACTION_REPLACE: string = 'replace'

var log = L.New(expand('<sfile>:t'))

const POPUP_ZINDEX: number = 260
const MIN_WIDTH: number = 30
const MAX_WIDTH: number = 70
const MAX_HEIGHT: number = 15
# Text property type, Bartleby highlight group, and default link. The
# groups are Bartleby's own, linked with :highlight default link, so they
# exist before :syntax on, when Comment does not, and a colorscheme can
# restyle them.
const PROP_TYPES: dict<list<string>> = {
  LexiconTitle: ['BartlebyLexiconTitle', 'Title'],
  LexiconComment: ['BartlebyLexiconNote', HL_COMMENT],
  LexiconError: ['BartlebyLexiconError', 'ErrorMsg'],
  LexiconSelected: ['BartlebyLexiconSelected', 'PmenuSel'],
}

# FUNCTION: Look up the word under the cursor.
export def LookupAtCursor(kind: string): void
  if !CanLookUp(kind)
    return
  endif
  if W.IsChromeBuf(bufnr('%'))
    log.Info(MK.LookupsNotAvailable())
    return
  endif
  var target: dict<any> = WordAtCursor()
  if empty(target)
    log.Info(MK.NoWordUnder())
    return
  endif
  OpenLookup(kind, LE.CleanWord(target.text), target)
enddef

# FUNCTION: Look up the last Visual selection, which must be on one line.
# Runs after Visual mode ends, when the marks of the selection are set.
export def LookupVisual(kind: string): void
  if !CanLookUp(kind)
    return
  endif
  var target: dict<any> = VisualSel()
  if empty(target)
    return
  endif
  OpenLookup(kind, LE.CleanWord(target.text), target)
enddef

# FUNCTION: Run :BartlebyDefine or :BartlebyThesaurus. A typed word is
# looked up without a target. No argument means the word under the
# cursor.
export def LookupCmd(kind: string, arg: string): void
  if arg ==# ''
    LookupAtCursor(kind)
    return
  endif
  if !CanLookUp(kind)
    return
  endif
  OpenLookup(kind, LE.CleanWord(arg), {})
enddef

def CanLookUp(kind: string): bool
  var reason: string = LE.DisabledReason(kind)
  if reason !=# ''
    log.Warn(reason)
    return false
  endif
  return true
enddef

def OpenLookup(kind: string, word: string, target: dict<any>): void
  if word ==# ''
    log.Info(MK.NothingLookUp())
    return
  endif
  LexiconPopup.new(kind, word, target).Open()
enddef

# FUNCTION: Return the keyword under or after the cursor, the word that
# cword picks, with its byte range: a dict of text, bufnr, lnum, start,
# and end, 0-based with end exclusive. Return an empty dict when there is
# none.
def WordAtCursor(): dict<any>
  var line: string = getline('.')
  var cursorCol: number = col('.') - 1
  var searchFrom: number = 0
  while true
    var [text: string, start: number, end: number] = matchstrpos(line, '\k\+', searchFrom)
    if start < 0
      return {}
    endif
    if end > cursorCol
      return {text: text, bufnr: bufnr('%'), lnum: line('.'), start: start, end: end}
    endif
    searchFrom = end
  endwhile
  return {}
enddef

def VisualSel(): dict<any>
  var first: list<number> = getpos("'<")
  var last: list<number> = getpos("'>")
  if first[1] != last[1]
    log.Info(MK.SelectTextOne())
    return {}
  endif
  var line: string = getline(first[1])
  var start: number = first[2] - 1
  var lastStart: number = min([last[2] - 1, strlen(line) - 1])
  var end: number = lastStart + strlen(matchstr(strpart(line, lastStart), '^.'))
  var text: string = strpart(line, start, end - start)
  if trim(text) ==# ''
    log.Info(MK.SelEmpty())
    return {}
  endif
  return {text: text, bufnr: bufnr('%'), lnum: first[1], start: start, end: end}
enddef

export class LexiconPopup
  var kind: string
  var word: string
  var target: dict<any>
  var result: LR.Result
  var rows: list<dict<any>> = []
  var selected: number = -1
  var firstline: number = 1
  var showAntonyms: bool = false
  var winid: number = -1
  var bufnr: number = -1

  def new(this.kind, this.word, this.target)
  enddef

  def Open(): void
    for [name, groups] in items(PROP_TYPES)
      execute $'highlight default link {groups[0]} {groups[1]}'
      if empty(prop_type_get(name))
        prop_type_add(name, {highlight: groups[0]})
      endif
    endfor
    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')
    this.winid = popup_create(this.bufnr, {
      line: CO.BELOW_CURSOR,
      col: 'cursor',
      pos: POS_TOPLEFT,
      title: $' {LE.Ref(this.kind).title}: {this.word} ',
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      minwidth: MIN_WIDTH,
      maxwidth: MAX_WIDTH,
      maxheight: MAX_HEIGHT,
      wrap: true,
      zindex: POPUP_ZINDEX,
      mapping: false,
      filter: (id, key) => this.Filter(id, key),
    })
    this.rows = [{text: MK.LookingUp(this.word), hl: HL_LEXICON_COMMENT}]
    this.Render()
    LE.Lookup(this.kind, this.word, (result) => this.OnResult(result))
  enddef

  def IsOpen(): bool
    return this.winid != -1 && !empty(popup_getpos(this.winid))
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid)
      this.winid = -1
    endif
  enddef

  def OnResult(result: LR.Result): void
    if !this.IsOpen()
      return
    endif
    this.result = result
    this.BuildRows()
    this.Render()
  enddef

  def BuildRows(): void
    var rows: list<dict<any>> = []
    var status: string = this.result.status
    if status ==# CO.STATUS_ERR
      rows->add({text: this.result.message, hl: HL_LEXICON_ERR})
    elseif status ==# CO.STATUS_NOTFOUND
      rows->add({text: MK.NoEntry(this.word)})
      if !empty(this.result.suggestions)
        rows->add({text: ''})
        rows->add({text: MK.DidMean(), hl: HL_LEXICON_TITLE})
        for suggestion in this.result.suggestions
          rows->add({text: '  ' .. suggestion, value: suggestion, action: ACTION_LOOKUP})
        endfor
      endif
    elseif this.kind ==# CO.KIND_THESAURUS
      rows = this.ThesaurusRows()
    else
      rows = this.DictRows()
    endif
    this.rows = rows
    this.selected = this.NextSelectable(-1, 1)
    this.firstline = 1
  enddef

  def DictRows(): list<dict<any>>
    var rows: list<dict<any>> = []
    for entry in this.result.entries
      if !empty(rows)
        rows->add({text: ''})
      endif
      var heading: string = entry.fl ==# '' ? entry.display : $'{entry.display}  ({entry.fl})'
      rows->add({text: heading, hl: HL_LEXICON_TITLE})
      for i in range(len(entry.defs))
        rows->add({text: $'  {i + 1}. {entry.defs[i]}'})
      endfor
    endfor
    return rows
  enddef

  def ThesaurusRows(): list<dict<any>>
    var rows: list<dict<any>> = []
    for entry in this.result.entries
      if !empty(rows)
        rows->add({text: ''})
      endif
      var heading: string = entry.fl ==# '' ? entry.headword : $'{entry.headword}  ({entry.fl})'
      rows->add({text: heading, hl: HL_LEXICON_TITLE})
      if this.showAntonyms
        if empty(entry.ants)
          rows->add({text: '  ' .. MK.NoAntonyms(), hl: HL_LEXICON_COMMENT})
        endif
        for ant in entry.ants
          rows->add({text: '    ' .. ant, value: ant, action: ACTION_REPLACE})
        endfor
        continue
      endif
      for sense in entry.senses
        if sense.label !=# ''
          rows->add({text: '  ' .. sense.label, hl: HL_LEXICON_COMMENT})
        endif
        for syn in sense.syns
          rows->add({text: '    ' .. syn, value: syn, action: ACTION_REPLACE})
        endfor
      endfor
    endfor
    rows->add({text: ''})
    var enter: string = empty(this.target) ? 'copy' : 'replace'
    var toggle: string = this.showAntonyms ? 'synonyms' : 'antonyms'
    rows->add({text: $'<CR> {enter}  a {toggle}  d define  ? help', hl: HL_LEXICON_COMMENT})
    return rows
  enddef

  # METHOD: Return the index of the next selectable row after from, in
  # direction step, or -1 when there is none.
  def NextSelectable(from: number, step: number): number
    var i: number = from + step
    while i >= 0 && i < len(this.rows)
      if has_key(this.rows[i], 'value')
        return i
      endif
      i += step
    endwhile
    return -1
  enddef

  def Render(): void
    var lines: list<string> = this.rows->mapnew((_, r) => r.text)
    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif
    for name in keys(PROP_TYPES)
      prop_remove({type: name, bufnr: this.bufnr, all: true}, 1, len(lines))
    endfor
    for i in range(len(this.rows))
      var name: string = i == this.selected ? 'LexiconSelected' : get(this.rows[i], 'hl', '')
      if name !=# '' && lines[i] !=# ''
        prop_add(i + 1, 1, {type: name, bufnr: this.bufnr, length: strlen(lines[i])})
      endif
    endfor
    if this.selected >= 0
      var lnum: number = this.selected + 1
      if lnum < this.firstline
        this.firstline = lnum
      elseif lnum >= this.firstline + MAX_HEIGHT
        this.firstline = lnum - MAX_HEIGHT + 1
      endif
    endif
    popup_setoptions(this.winid, {firstline: this.firstline})
  enddef

  def Move(step: number): void
    if this.selected >= 0
      var next: number = this.NextSelectable(this.selected, step)
      if next >= 0
        this.selected = next
      endif
    else
      var lastFirst: number = max([1, len(this.rows) - MAX_HEIGHT + 1])
      this.firstline = min([max([1, this.firstline + step]), lastFirst])
    endif
    this.Render()
  enddef

  def Accept(): void
    if this.selected < 0
      return
    endif
    var row: dict<any> = this.rows[this.selected]
    this.Close()
    if row.action ==# ACTION_LOOKUP
      OpenLookup(this.kind, LE.CleanWord(row.value), this.target)
    else
      this.Use(row.value)
    endif
  enddef

  # METHOD: Put value in the text where the lookup began, or in the unnamed
  # register when the lookup began with no text.
  def Use(value: string): void
    if empty(this.target)
      setreg('"', value)
      log.Info(MK.CopiedUnnamedRegister(value))
    else
      this.ReplaceTarget(value)
    endif
  enddef

  # METHOD: Return the action of the selected row, or an empty string when
  # no row is selected.
  def SelAction(): string
    return this.selected < 0 ? '' : get(this.rows[this.selected], 'action', '')
  enddef

  # METHOD: Use the selected suggestion of a misspelled word instead of
  # looking it up, as the thesaurus does with a synonym.
  def ReplaceWithSuggestion(): void
    if this.SelAction() !=# ACTION_LOOKUP
      return
    endif
    var suggestion: string = this.rows[this.selected].value
    this.Close()
    this.Use(suggestion)
  enddef

  def ReplaceTarget(replacement: string): void
    var t: dict<any> = this.target
    var line: string = get(getbufline(t.bufnr, t.lnum), 0, '')
    if strpart(line, t.start, t.end - t.start) !=# t.text
      log.Warn(MK.ChangedSinceLookup(t.text))
      return
    endif
    if !getbufvar(t.bufnr, '&modifiable')
      log.Warn(MK.BufCannotChanged())
      return
    endif
    var newText: string = LE.MatchCase(t.text, replacement)
    setbufline(t.bufnr, t.lnum, strpart(line, 0, t.start) .. newText .. strpart(line, t.end))
  enddef

  def DefineSel(): void
    if this.kind !=# CO.KIND_THESAURUS || this.selected < 0
      return
    endif
    var reason: string = LE.DisabledReason(CO.KIND_DICT)
    if reason !=# ''
      log.Warn(reason)
      return
    endif
    var word: string = this.rows[this.selected].value
    this.Close()
    OpenLookup(CO.KIND_DICT, LE.CleanWord(word), {})
  enddef

  def ToggleAntonyms(): void
    if this.kind !=# CO.KIND_THESAURUS || this.result is null_object || this.result.status !=# CO.STATUS_OK
      return
    endif
    this.showAntonyms = !this.showAntonyms
    this.BuildRows()
    this.Render()
  enddef

  def ShowHelp(): void
    var entries: list<list<string>> = [
      ['j / <Down>', this.selected >= 0 ? MK.NextWord() : MK.ScrollDown()],
      ['k / <Up>', this.selected >= 0 ? MK.PrevWord() : MK.ScrollUp()],
    ]
    var use: string = empty(this.target) ? MK.CopyWord() : MK.ReplaceWordText()
    if this.SelAction() ==# ACTION_LOOKUP
      entries->add(['<CR>', MK.LookUpSel()])
      entries->add(['r', use])
    elseif this.kind ==# CO.KIND_THESAURUS && this.selected >= 0
      entries->add(['<CR>', use])
    endif
    if this.kind ==# CO.KIND_THESAURUS
      if this.result isnot null_object && this.result.status ==# CO.STATUS_OK
        entries->add(['a', MK.ToggleAntonyms()])
      endif
      if this.selected >= 0
        entries->add(['d', MK.DefineSelWord()])
      endif
    endif
    entries += [['q / <Esc>', MC.Close()], ['?', MC.Help()]]
    H.Show(MK.Lookup(), entries)
  enddef

  def Filter(id: number, key: string): bool
    if key ==# 'j' || key ==# CO.KEY_DOWN
      this.Move(1)
    elseif key ==# 'k' || key ==# CO.KEY_UP
      this.Move(-1)
    elseif key ==# CO.KEY_CR
      this.Accept()
    elseif key ==# 'r'
      this.ReplaceWithSuggestion()
    elseif key ==# 'a'
      this.ToggleAntonyms()
    elseif key ==# 'd'
      this.DefineSel()
    elseif key ==# '?'
      this.ShowHelp()
    elseif key ==# 'q' || key ==# CO.KEY_ESC
      this.Close()
    endif
    return true
  enddef
endclass
