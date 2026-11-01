vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# inputpopup.vim: a modal popup form with one Tab order and Submit and
# Cancel buttons. Field types: text, choice, filter, and multiline.
# picker.vim's PickOne uses one choice field. buttonspopup.vim's
# PopupBtnMenu is separate, for the Corkboard card grid, which is not
# a form.
#
# fields is a list of rows, and each row is a list of field specs:
#
#   var fields = [
#     [{name: 'title', type: 'text'}],
#     [{name: 'kind', type: 'choice', options: ['Manuscript', 'Book']}],
#     [{name: 'city', type: 'text'}, {name: 'zip', type: 'text'}],
#   ]
#
# Shown as:
#
#   title:  __________________
#   kind:   [ Manuscript ]  [ Book ]
#   city: ______  zip: _____
#
#   [ Submit ]  [ Cancel ]
#
# A choice field always takes a whole row: the width of a row of options
# does not combine with text boxes. A filter field, a text line above a
# fuzzy-matched list, and a multiline field, a text area, are each the
# only field of their popup, see PromptFilter and PromptMultiline.
#
# The caller gives starting values in a dict keyed by field name. For a
# choice field, the value is the option to select. OnSubmit receives a
# dict of the values: typed text for a text field, and the selected
# option for a choice or filter field.
#
# opts keys are a data contract, not Vim identifiers, so they keep
# snake_case:
#   field_width   number        Width of a text field. Default 20.
#   widths        dict<number>  Width per text field, by field name.
#   maxlengths    dict<number>  Maximum characters per text field, by
#                               field name. Typing stops there. A longer
#                               starting value is kept. The field is at
#                               least one column wider, for the cursor.
#   complete      dict<string>  Completion type per text field, by field
#                               name, as getcompletion takes it, such as
#                               {path: 'file'}. Without one, a field
#                               completes nothing.
#   labels        dict<string>  Label per field, by field name. Default:
#                               the field name.
#   submit_label  string        Text of the Submit button.
#   cancel_label  string        Text of the Cancel button.
#   buttons       list          An empty list shows no buttons.
#   min_width     number        Minimum width of the popup.
#   title, line, col, zindex    Passed to popup_create unchanged.
#
# Keys: Tab and S-Tab, or C-n and C-p, move between the fields and the
# buttons. In a text field that completes and holds text, Tab takes the
# next match instead, and S-Tab the one before, so C-n and C-p move on
# from such a field. In a text field, Left, Right, Home, and End move
# the cursor, C-u clears it, and Enter moves to the next field. In a
# choice field, Left and Right change the option, without wrapping, and
# Enter moves on. C-s submits and Esc or C-c cancels from anywhere. The
# mouse can click buttons, text fields, and options.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

const TYPE_FILTER: string = 'filter'
const TYPE_MULTILINE: string = 'multiline'
const ACTION_SUBMIT: string = 'submit'
const ACTION_CANCEL: string = 'cancel'
const KEY_BS: string = "\<BS>"
const KEY_C_H: string = "\<C-h>"
const KEY_DEL: string = "\<Del>"
const KEY_HOME: string = "\<Home>"
const KEY_C_A: string = "\<C-a>"
const KEY_END: string = "\<End>"
const KEY_C_E: string = "\<C-e>"
const TYPE_BTN: string = 'button'
const KEY_C_S: string = "\<C-s>"
const KEY_C_N: string = "\<C-n>"
const KEY_C_P: string = "\<C-p>"
const KEY_C_J: string = "\<C-j>"
const KEY_C_K: string = "\<C-k>"
const KEY_PAGE_DOWN: string = "\<PageDown>"
const KEY_PAGE_UP: string = "\<PageUp>"
const KEY_C_U: string = "\<C-u>"
const TYPE_INPUT_POPUP_LABEL: string = 'InputPopupLabel'
const TYPE_INPUT_POPUP_CURSOR: string = 'InputPopupCursor'
const TYPE_INPUT_POPUP_OPTION: string = 'InputPopupOption'
const TYPE_INPUT_POPUP_OPTION_SEL: string = 'InputPopupOptionSelected'
const TYPE_INPUT_POPUP_SCROLLBAR: string = 'InputPopupScrollbar'
const TYPE_INPUT_POPUP_THUMB: string = 'InputPopupThumb'
const TYPE_INPUT_POPUP_BTN: string = 'InputPopupButton'
const TYPE_INPUT_POPUP_BTN_ACTIVE: string = 'InputPopupButtonActive'

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Convert rows of field names, a list of lists of strings, to
# field specs of type text. Saves writing each spec for a form of only
# text fields.
def Noop(): void
enddef

export def TextFields(rows: list<list<string>>): list<list<dict<any>>>
  return rows->mapnew((_, row) => row->mapnew((_, name) => ({name: name, type: CO.TYPE_TEXT})))
enddef

# FUNCTION: Show one text field, titled title and filled with default.
# Call OnSubmit with the text, or OnCancel, which does nothing by
# default, on cancel. One Enter submits, like input in a box. With
# complete, a completion type that getcompletion takes, Tab completes the
# text, as for a file path.
export def PromptText(title: string, default: string, OnSubmit: func(string),
    OnCancel: func() = Noop, complete: string = ''): void
  var fields: list<list<dict<any>>> = [[{name: 'value', type: 'text'}]]
  var form: InputPopup = InputPopup.new(fields, {value: default},
    {title: $' {title} ', complete: {value: complete}})
  form.OnSubmit((vals: dict<any>) => {
    OnSubmit(vals.value)
  })
  # A caller that wants no cancel handler but does want completion, which
  # comes after it, passes null_function. Calling that would fail.
  form.OnCancel(OnCancel == null_function ? Noop : OnCancel)
  form.Open()
enddef

# FUNCTION: Show options as a list, titled title, that narrows as you
# type, with matchfuzzy. Call OnSubmit with the selected option. Nothing
# is called on cancel, or on Enter with no match. Up, Down, C-k, C-j,
# PageUp, PageDown, and the mouse wheel move the selection, and the list
# scrolls with it. One Enter submits, as in PickOne. names, optional, maps
# an option to the text shown and matched for it, as in PickOne, and
# OnSubmit still receives the option.
export def PromptFilter(title: string, options: list<string>, OnSubmit: func(string),
    maxVisible: number = 10, minWidth: number = 0, names: dict<string> = {}): void
  var shown: list<string> = options->mapnew((_, o) => get(names, o, o))
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'filter',
    options: shown, maxVisible: maxVisible}]]
  var form: InputPopup = InputPopup.new(fields, {},
    {title: $' {title} ', buttons: [], min_width: minWidth})
  form.OnSubmit((vals: dict<any>) => {
    if vals.choice !=# ''
      OnSubmit(options[index(shown, vals.choice)])
    endif
  })
  form.Open()
enddef

# FUNCTION: Show a multiline text field, titled title and filled with
# default, a string with line breaks, with Save and Cancel buttons. Enter
# adds a line, unlike every other one-field prompt, so C-s or the Save
# button submits, and Tab moves to the buttons. Call OnSubmit with the
# text joined by line breaks. Nothing is called on cancel.
export def PromptMultiline(title: string, default: string, OnSubmit: func(string),
    rows: number = 5, width: number = 50): void
  var fields: list<list<dict<any>>> = [[{name: 'text', type: 'multiline',
    rows: rows}]]
  var form: InputPopup = InputPopup.new(fields, {text: default},
    {title: MI.Save(title), widths: {text: width},
      submit_label: MC.Save()})
  form.OnSubmit((vals: dict<any>) => {
    OnSubmit(vals.text)
  })
  form.Open()
enddef

# FUNCTION: Add text to row, the line that Render builds: its text, and
# its length in characters.
def AppendTo(row: dict<any>, text: string): void
  row.text ..= text
  row.chars += strchars(text)
enddef

# What a key handler of InputPopup did: the key was not one of its keys,
# it was handled, it changed the text of the field, or it closed the
# popup, which must then not be drawn again.
const KEY_UNHANDLED: string = ''
const KEY_HANDLED: string = 'handled'
const KEY_CHANGED: string = 'changed'
const KEY_CLOSED: string = 'closed'

export class InputPopup
  var fieldRows: list<list<dict<any>>>
  var defaults: dict<any>
  var opts: dict<any>

  var fields: list<dict<any>> = []
  var buttons: list<dict<any>> = []
  var bufnr: number = -1
  var winid: number = -1
  var currentIdx: number = 0

  var _onSubmit: any = v:null
  var _onCancel: any = v:null

  var _fieldHit: list<dict<any>> = []
  var _optionHit: list<dict<any>> = []
  var _buttonHit: list<dict<any>> = []

  def new(this.fieldRows, defaults: dict<any> = {}, opts: dict<any> = {})
    this.defaults = defaults
    this.opts = opts
    this.BuildFields()
    this.BuildBtns()
  enddef

  ############################################################################
  # SECTION: Setup.
  ############################################################################

  def BuildFields(): void
    this.fields = []
    var widths: dict<any> = get(this.opts, 'widths', {})
    var labels: dict<any> = get(this.opts, 'labels', {})
    var defaultWidth: number = get(this.opts, 'field_width', 20)
    for rowIdx in range(len(this.fieldRows))
      for spec in this.fieldRows[rowIdx]
        var name: string = spec.name
        var fieldType: string = get(spec, 'type', 'text')
        var field: dict<any> = {
          name: name,
          label: get(labels, name, name),
          type: fieldType,
          row: rowIdx,
        }
        if fieldType ==# CO.TYPE_CHOICE
          var options: list<string> = get(spec, 'options', [])
          var startVal: string = get(this.defaults, name, '')
          var selectedIdx: number = max([0, index(options, startVal)])
          field.options = options
          field.selectedIdx = selectedIdx
        elseif fieldType ==# TYPE_FILTER
          field.value = ''
          field.cursor = 0
          field.offset = 0
          field.options = get(spec, 'options', [])
          field.maxVisible = get(spec, 'maxVisible', 10)
          field.filtered = copy(field.options)
          field.selectedIdx = 0
          field.scrollTop = 0
        elseif fieldType ==# TYPE_MULTILINE
          var startText: string = get(this.defaults, name, '')
          field.lines = split(startText, "\n", true)
          if empty(field.lines)
            field.lines = ['']
          endif
          field.rows = get(spec, 'rows', 5)
          field.width = get(widths, name, defaultWidth)
          field.cursorLine = 0
          field.cursorCol = strchars(field.lines[0])
          field.scrollOffset = 0
        else
          var raw: any = get(this.defaults, name, '')
          var isComplex: bool = type(raw) != v:t_string
          var text: string = isComplex ? string(raw) : raw
          field.value = text
          field.cursor = strchars(text)
          field.offset = 0
          field.isComplex = isComplex
          field.maxLength = get(get(this.opts, 'maxlengths', {}), name, 0)
          # One column more than the maximum, for the cursor after the last
          # character. Without it the field scrolls and hides the text.
          field.width = max([get(widths, name, defaultWidth), field.maxLength + 1])
          field.complete = get(get(this.opts, 'complete', {}), name, '')
          field.matches = []
          field.matchIdx = -1
        endif
        add(this.fields, field)
      endfor
    endfor
  enddef

  def BuildBtns(): void
    if has_key(this.opts, 'buttons')
      this.buttons = get(this.opts, 'buttons', [])
      return
    endif
    this.buttons = [
      {label: get(this.opts, 'submit_label', MI.Submit()), action: ACTION_SUBMIT},
      {label: get(this.opts, 'cancel_label', MC.Cancel()), action: ACTION_CANCEL},
    ]
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('InputPopupLabel'))
      prop_type_add('InputPopupLabel', {highlight: 'Title'})
    endif
    if empty(prop_type_get('InputPopupCursor'))
      prop_type_add('InputPopupCursor', {highlight: 'IncSearch'})
    endif
    if empty(prop_type_get('InputPopupButton'))
      prop_type_add('InputPopupButton', {highlight: CO.HL_PMENU})
    endif
    if empty(prop_type_get('InputPopupButtonActive'))
      prop_type_add('InputPopupButtonActive', {highlight: CO.HL_PMENU_SEL})
    endif
    if empty(prop_type_get('InputPopupOption'))
      prop_type_add('InputPopupOption', {highlight: CO.HL_PMENU})
    endif
    if empty(prop_type_get('InputPopupScrollbar'))
      prop_type_add('InputPopupScrollbar', {highlight: 'PmenuSbar'})
    endif
    if empty(prop_type_get('InputPopupThumb'))
      prop_type_add('InputPopupThumb', {highlight: 'PmenuThumb'})
    endif
    if empty(prop_type_get('InputPopupOptionSelected'))
      prop_type_add('InputPopupOptionSelected', {highlight: CO.HL_PMENU_SEL})
    endif
  enddef

  def BtnLineText(): string
    var parts: list<string> = []
    for b in this.buttons
      add(parts, '[ ' .. b.label .. ' ]')
    endfor
    return join(parts, '  ')
  enddef

  def FieldLineText(f: dict<any>): string
    var label: string = f.label .. ': '
    if f.type ==# CO.TYPE_CHOICE
      var parts: list<string> = []
      for opt in f.options
        add(parts, '[ ' .. opt .. ' ]')
      endfor
      return label .. join(parts, '  ')
    endif
    return label .. repeat('_', f.width)
  enddef

  def ComputeSize(): list<number>
    if len(this.fields) == 1 && this.fields[0].type ==# TYPE_FILTER
      var f: dict<any> = this.fields[0]
      var w: number = 20
      for opt in f.options
        w = max([w, strchars(opt)])
      endfor
      var visibleRows: number = min([max([len(f.options), 1]), f.maxVisible])
      # One more column for the scrollbar when the list can scroll.
      var scrollbar: number = len(f.options) > f.maxVisible ? 2 : 0
      return [this.FitTitle(max([w + scrollbar, 10])), 1 + visibleRows]
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# TYPE_MULTILINE
      var f: dict<any> = this.fields[0]
      return [max([f.width, strchars(this.BtnLineText()), 10]), f.rows + (empty(this.buttons) ? 0 : 1)]
    endif

    var rowWidths: dict<number> = {}
    var rowCount: number = 0
    for f in this.fields
      var w: number = strchars(this.FieldLineText(f))
      if f.type !=# CO.TYPE_CHOICE
        w = get(rowWidths, string(f.row), 0) + strchars(f.label) + 2 + f.width + 2
      endif
      rowWidths[string(f.row)] = w
      rowCount = max([rowCount, f.row + 1])
    endfor
    var maxWidth: number = strchars(this.BtnLineText())
    for w in values(rowWidths)
      maxWidth = max([maxWidth, w])
    endfor
    return [this.FitTitle(max([maxWidth, 10])), max([rowCount, 1]) + (empty(this.buttons) ? 0 : 1)]
  enddef

  # METHOD: Return width, widened so that the title shows in full with 2
  # columns to spare, and to the min_width option.
  def FitTitle(width: number): number
    var title: string = trim(get(this.opts, 'title', ''))
    return max([width, strdisplaywidth(title) + 2, get(this.opts, 'min_width', 0)])
  enddef

  ############################################################################
  # SECTION: Public API.
  ############################################################################

  # METHOD: Set the function called with the field values on submit.
  def OnSubmit(Cb: any): void
    this._onSubmit = Cb
  enddef

  # METHOD: Set the function called on cancel.
  def OnCancel(Cb: any): void
    this._onCancel = Cb
  enddef

  def Open(): void
    if empty(this.fields)
      log.Error(MI.InputPopupFieldRowsProduced())
      return
    endif

    this.currentIdx = 0
    this.EnsurePropTypes()

    var [width, height] = this.ComputeSize()

    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    this.winid = popup_create(this.bufnr, {
      line: get(this.opts, 'line', 0),
      col: get(this.opts, 'col', 0),
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      title: get(this.opts, 'title', printf(CO.TITLE_FMT, MI.Input())),
      zindex: get(this.opts, 'zindex', 300),
      mapping: false,
      mousemoveevent: false,
      filter: (winid, key) => this.Filter(winid, key),
      callback: (winid, result) => this.OnClose(winid, result),
    })

    setwinvar(this.winid, '&wrap', 0)
    setwinvar(this.winid, '&number', 0)
    setwinvar(this.winid, '&relativenumber', 0)

    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid, 0)
    endif
  enddef

  ############################################################################
  # SECTION: Focus helpers.
  ############################################################################

  def TotalControls(): number
    return len(this.fields) + len(this.buttons)
  enddef

  def IsBtnIdx(idx: number): bool
    return idx >= len(this.fields)
  enddef

  def BtnAt(idx: number): dict<any>
    return this.buttons[idx - len(this.fields)]
  enddef

  # METHOD: Give the control at idx focus. A text or filter field gets its
  # cursor at the end of its text. A multiline field keeps its cursor, so
  # that focus comes back from the buttons to where the writing was.
  def Focus(idx: number): void
    this.currentIdx = idx
    if idx < len(this.fields) && index(['choice', TYPE_MULTILINE], this.fields[idx].type) < 0
      this.fields[idx].cursor = strchars(this.fields[idx].value)
    endif
  enddef

  def ActivateBtn(idx: number): void
    var btn: dict<any> = this.BtnAt(idx)
    popup_close(this.winid, btn.action == ACTION_SUBMIT ? 1 : 0)
  enddef

  ############################################################################
  # SECTION: Input handling.
  ############################################################################

  def HandleMultilineKey(key: string): bool
    var f: dict<any> = this.fields[this.currentIdx]
    if key ==# CO.KEY_CR
      var line: string = f.lines[f.cursorLine]
      var before: string = strcharpart(line, 0, f.cursorCol)
      var after: string = strcharpart(line, f.cursorCol)
      f.lines[f.cursorLine] = before
      insert(f.lines, after, f.cursorLine + 1)
      f.cursorLine += 1
      f.cursorCol = 0
    elseif key ==# CO.KEY_UP
      if f.cursorLine > 0
        f.cursorLine -= 1
        f.cursorCol = min([f.cursorCol, strchars(f.lines[f.cursorLine])])
      endif
    elseif key ==# CO.KEY_DOWN
      if f.cursorLine < len(f.lines) - 1
        f.cursorLine += 1
        f.cursorCol = min([f.cursorCol, strchars(f.lines[f.cursorLine])])
      endif
    elseif key ==# CO.KEY_LEFT
      if f.cursorCol > 0
        f.cursorCol -= 1
      elseif f.cursorLine > 0
        f.cursorLine -= 1
        f.cursorCol = strchars(f.lines[f.cursorLine])
      endif
    elseif key ==# CO.KEY_RIGHT
      if f.cursorCol < strchars(f.lines[f.cursorLine])
        f.cursorCol += 1
      elseif f.cursorLine < len(f.lines) - 1
        f.cursorLine += 1
        f.cursorCol = 0
      endif
    elseif key ==# KEY_BS || key ==# KEY_C_H
      if f.cursorCol > 0
        var chars: list<string> = split(f.lines[f.cursorLine], '\zs')
        remove(chars, f.cursorCol - 1)
        f.lines[f.cursorLine] = join(chars, '')
        f.cursorCol -= 1
      elseif f.cursorLine > 0
        var prevLen: number = strchars(f.lines[f.cursorLine - 1])
        f.lines[f.cursorLine - 1] ..= f.lines[f.cursorLine]
        remove(f.lines, f.cursorLine)
        f.cursorLine -= 1
        f.cursorCol = prevLen
      endif
    elseif key ==# KEY_DEL
      var line: string = f.lines[f.cursorLine]
      if f.cursorCol < strchars(line)
        var chars: list<string> = split(line, '\zs')
        remove(chars, f.cursorCol)
        f.lines[f.cursorLine] = join(chars, '')
      elseif f.cursorLine < len(f.lines) - 1
        f.lines[f.cursorLine] ..= f.lines[f.cursorLine + 1]
        remove(f.lines, f.cursorLine + 1)
      endif
    elseif key ==# KEY_HOME || key ==# KEY_C_A
      f.cursorCol = 0
    elseif key ==# KEY_END || key ==# KEY_C_E
      f.cursorCol = strchars(f.lines[f.cursorLine])
    elseif strchars(key) == 1 && char2nr(key) >= 32
      var chars: list<string> = split(f.lines[f.cursorLine], '\zs')
      insert(chars, key, f.cursorCol)
      f.lines[f.cursorLine] = join(chars, '')
      f.cursorCol += 1
    else
      return false
    endif
    return true
  enddef

  # METHOD: The popup filter. It sends key to the handler of the control
  # that has focus, after the keys that every control shares, and redraws
  # unless the key closed the popup.
  def Filter(winid: number, key: string): bool
    var isBtn: bool = this.IsBtnIdx(this.currentIdx)
    var type: string = isBtn ? 'button' : this.fields[this.currentIdx].type
    if type ==# TYPE_MULTILINE
      if this.MultilineKey(winid, key) !=# KEY_CLOSED
        this.Render()
      endif
      return true
    endif
    # A field that completes takes Tab for its matches, before CommonKey
    # moves the focus with it.
    var completing: dict<any> = this.CompletingField()
    var result: string = !empty(completing) && (key == CO.KEY_TAB || key == CO.KEY_S_TAB)
      ? this.CompleteKey(completing, key)
      : this.CommonKey(winid, key)
    if result ==# KEY_UNHANDLED
      if type ==# TYPE_BTN
        result = this.BtnKey(winid, key)
      elseif type ==# TYPE_FILTER
        result = this.FilterFieldKey(winid, key)
      elseif type ==# CO.TYPE_CHOICE
        result = this.ChoiceKey(winid, key)
      else
        result = this.TextKey(winid, key)
      endif
    endif
    # The matches belong to the text as it was, so a change drops them.
    if result ==# KEY_CHANGED && !empty(completing)
      completing.matches = []
      completing.matchIdx = -1
    endif
    if result !=# KEY_CLOSED
      this.Render()
    endif
    return true
  enddef

  # METHOD: Keys of a multiline field. Ctrl-S submits, Esc cancels, Tab and
  # Shift-Tab move to the buttons, and every other key edits the text. The
  # buttons are the way to save where the terminal takes Ctrl-S for flow
  # control, as the Linux console does.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/2
  def MultilineKey(winid: number, key: string): string
    if (key == CO.KEY_TAB || key == CO.KEY_S_TAB) && !empty(this.buttons)
      var step: number = key == "\<Tab>" ? 1 : this.TotalControls() - 1
      this.Focus((this.currentIdx + step) % this.TotalControls())
      return KEY_HANDLED
    elseif key == KEY_C_S
      popup_close(winid, 1)
      return KEY_CLOSED
    elseif key == CO.KEY_ESC || key == CO.KEY_C_C
      popup_close(winid, 0)
      return KEY_CLOSED
    endif
    this.HandleMultilineKey(key)
    return KEY_HANDLED
  enddef

  # METHOD: Keys that every control shares: move to the next or previous
  # control, submit, cancel, and click.
  def CommonKey(winid: number, key: string): string
    if key == CO.KEY_TAB || key == KEY_C_N
      this.Focus((this.currentIdx + 1) % this.TotalControls())
    elseif key == CO.KEY_S_TAB || key == KEY_C_P
      this.Focus((this.currentIdx - 1 + this.TotalControls()) % this.TotalControls())
    elseif key == KEY_C_S
      popup_close(winid, 1)
      return KEY_CLOSED
    elseif key == CO.KEY_ESC || key == CO.KEY_C_C
      popup_close(winid, 0)
      return KEY_CLOSED
    elseif key == CO.KEY_LEFT_MOUSE
      this.HandleMouseClick()
    else
      return KEY_UNHANDLED
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a button. A button holds no text, so other keys do
  # nothing.
  def BtnKey(winid: number, key: string): string
    if key == CO.KEY_CR || key == ' '
      this.ActivateBtn(this.currentIdx)
      return KEY_CLOSED
    elseif key == CO.KEY_LEFT
      this.Focus(max([len(this.fields), this.currentIdx - 1]))
    elseif key == CO.KEY_RIGHT
      this.Focus(min([this.TotalControls() - 1, this.currentIdx + 1]))
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a filter field: move in the list, or pick with Enter.
  # Other keys edit the text, and a changed text filters the list again.
  def FilterFieldKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == CO.KEY_DOWN || key == KEY_C_J || key == CO.KEY_SCROLL_WHEEL_DOWN
      this.MoveFilterSel(f, 1)
    elseif key == CO.KEY_UP || key == KEY_C_K || key == CO.KEY_SCROLL_WHEEL_UP
      this.MoveFilterSel(f, -1)
    elseif key == KEY_PAGE_DOWN
      this.MoveFilterSel(f, f.maxVisible)
    elseif key == KEY_PAGE_UP
      this.MoveFilterSel(f, -f.maxVisible)
    elseif key == CO.KEY_CR
      if !empty(f.filtered)
        popup_close(winid, 1)
      endif
      return KEY_CLOSED
    else
      var result: string = this.TextKey(winid, key)
      if result ==# KEY_CHANGED
        f.filtered = f.value ==# '' ? copy(f.options) : matchfuzzy(f.options, f.value)
        f.selectedIdx = 0
        f.scrollTop = 0
      endif
      return result
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a choice field. It holds no text, so other keys do
  # nothing.
  def ChoiceKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == CO.KEY_LEFT
      f.selectedIdx = max([0, f.selectedIdx - 1])
    elseif key == CO.KEY_RIGHT
      f.selectedIdx = min([len(f.options) - 1, f.selectedIdx + 1])
    elseif key == CO.KEY_CR
      if len(this.fields) == 1
        popup_close(winid, 1)
        return KEY_CLOSED
      endif
      this.Focus(this.currentIdx < len(this.fields) - 1 ? this.currentIdx + 1 : len(this.fields))
    endif
    return KEY_HANDLED
  enddef

  # METHOD: Return the focused field when it completes and holds text,
  # else an empty dict. An empty field keeps Tab for moving on, where
  # there is nothing to complete anyway.
  def CompletingField(): dict<any>
    if this.IsBtnIdx(this.currentIdx)
      return {}
    endif
    var f: dict<any> = this.fields[this.currentIdx]
    return get(f, 'complete', '') ==# '' || f.value ==# '' ? {} : f
  enddef

  # METHOD: Put the next match in f, or with Shift-Tab the one before.
  # The first Tab after a change looks the matches up. With one match,
  # which the text now is, they are looked up again, so that Tab after a
  # completed folder offers what is in it. No match leaves the text as it
  # is, as the command line of Vim does.
  def CompleteKey(f: dict<any>, key: string): string
    if empty(f.matches) || (len(f.matches) == 1 && f.matches[0] ==# f.value)
      f.matches = getcompletion(f.value, f.complete)
      f.matchIdx = -1
    endif
    if empty(f.matches)
      return KEY_HANDLED
    endif
    if f.matchIdx < 0
      f.matchIdx = key == CO.KEY_TAB ? 0 : len(f.matches) - 1
    else
      var step: number = key == CO.KEY_TAB ? 1 : len(f.matches) - 1
      f.matchIdx = (f.matchIdx + step) % len(f.matches)
    endif
    f.value = f.matches[f.matchIdx]
    # Render scrolls the field from the cursor, so the end of a long path
    # shows.
    f.cursor = strchars(f.value)
    return KEY_HANDLED
  enddef

  # METHOD: Keys of a text field. Enter submits a popup of one field, or
  # else moves on, to the Submit button after the last field. Returns
  # KEY_CHANGED when the text changed.
  def TextKey(winid: number, key: string): string
    var f: dict<any> = this.fields[this.currentIdx]
    if key == CO.KEY_CR
      if len(this.fields) == 1
        popup_close(winid, 1)
        return KEY_CLOSED
      endif
      this.Focus(this.currentIdx < len(this.fields) - 1 ? this.currentIdx + 1 : len(this.fields))
    elseif key == KEY_BS || key == KEY_C_H
      if f.cursor == 0
        return KEY_HANDLED
      endif
      var chars: list<string> = split(f.value, '\zs')
      remove(chars, f.cursor - 1)
      f.value = join(chars, '')
      f.cursor -= 1
      return KEY_CHANGED
    elseif key == KEY_DEL
      if f.cursor >= strchars(f.value)
        return KEY_HANDLED
      endif
      var chars: list<string> = split(f.value, '\zs')
      remove(chars, f.cursor)
      f.value = join(chars, '')
      return KEY_CHANGED
    elseif key == KEY_C_U
      f.value = ''
      f.cursor = 0
      return KEY_CHANGED
    elseif key == CO.KEY_LEFT
      f.cursor = max([0, f.cursor - 1])
    elseif key == CO.KEY_RIGHT
      f.cursor = min([strchars(f.value), f.cursor + 1])
    elseif key == KEY_HOME || key == KEY_C_A
      f.cursor = 0
    elseif key == KEY_END || key == KEY_C_E
      f.cursor = strchars(f.value)
    elseif strchars(key) == 1 && char2nr(key) >= 32 && !this.AtMaxLen(f)
      var chars: list<string> = split(f.value, '\zs')
      insert(chars, key, f.cursor)
      f.value = join(chars, '')
      f.cursor += 1
      return KEY_CHANGED
    endif
    return KEY_HANDLED
  enddef

  def HandleMouseClick(): void
    var pos: dict<any> = getmousepos()
    if pos.winid != this.winid
      return
    endif

    for hit in this._buttonHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(len(this.fields) + hit.idx)
        this.ActivateBtn(this.currentIdx)
        return
      endif
    endfor

    for hit in this._optionHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(hit.idx)
        this.fields[hit.idx].selectedIdx = hit.optionIdx
        return
      endif
    endfor

    for hit in this._fieldHit
      if pos.line == hit.lnum && pos.column >= hit.startCol && pos.column <= hit.endCol
        this.Focus(hit.idx)
        # Place the cursor at the click. Assumes one byte per character in the
        # field, which is true for ASCII text.
        var clickChar: number = pos.column - hit.startCol
        var f: dict<any> = this.fields[hit.idx]
        f.cursor = max([0, min([strchars(f.value), f.offset + clickChar])])
        return
      endif
    endfor
  enddef

  def OnClose(winid: number, result: number): void
    if result == 1
      if type(this._onSubmit) == v:t_func
        call(this._onSubmit, [this.Vals()])
      endif
    else
      if type(this._onCancel) == v:t_func
        call(this._onCancel, [])
      endif
    endif
    this.bufnr = -1
    this.winid = -1
  enddef

  ############################################################################
  # SECTION: Values.
  ############################################################################

  # METHOD: Return the field values in a dict keyed by field name, never by
  # label. A text field whose default was not a string, such as a list or
  # a number, is converted back with eval. Text that no longer parses stays
  # a string. A choice field returns its selected option.
  def Vals(): dict<any>
    var result: dict<any> = {}
    for f in this.fields
      if f.type ==# CO.TYPE_CHOICE
        result[f.name] = empty(f.options) ? '' : f.options[f.selectedIdx]
        continue
      endif
      if f.type ==# TYPE_FILTER
        result[f.name] = empty(f.filtered) ? '' : f.filtered[f.selectedIdx]
        continue
      endif
      if f.type ==# TYPE_MULTILINE
        result[f.name] = join(f.lines, "\n")
        continue
      endif
      var val: any = trim(f.value)
      if f.isComplex
        try
          val = eval(val)
        catch
          # Keep the text as a string if it no longer parses as Vim data.
        endtry
      endif
      result[f.name] = val
    endfor
    return result
  enddef

  ############################################################################
  # SECTION: Rendering.
  ############################################################################

  # METHOD: Return true when a text field with a maximum length is full.
  def AtMaxLen(f: dict<any>): bool
    return get(f, 'maxLength', 0) > 0 && strchars(f.value) >= f.maxLength
  enddef

  # METHOD: Move the selection of a filter list by step rows, and scroll so
  # that the selection stays visible.
  def MoveFilterSel(f: dict<any>, step: number): void
    f.selectedIdx = max([0, min([len(f.filtered) - 1, f.selectedIdx + step])])
    if f.selectedIdx < f.scrollTop
      f.scrollTop = f.selectedIdx
    elseif f.selectedIdx >= f.scrollTop + f.maxVisible
      f.scrollTop = f.selectedIdx - f.maxVisible + 1
    endif
  enddef

  def RenderFilter(): void
    var f: dict<any> = this.fields[0]
    # The trailing space is for the cursor at the end of the text, as in
    # RenderMultiline.
    var lines: list<string> = ['> ' .. f.value .. ' ']
    for i in range(f.maxVisible)
      var idx: number = f.scrollTop + i
      add(lines, idx < len(f.filtered) ? '  ' .. f.filtered[idx] : '')
    endfor
    # With a scrollbar, each list row is padded so that its last column
    # holds the scrollbar, see DrawFilterScrollbar.
    if this.FilterScrolls(f)
      var width: number = popup_getoptions(this.winid).minwidth
      for i in range(1, f.maxVisible)
        lines[i] ..= repeat(' ', max([0, width - 1 - strdisplaywidth(lines[i])])) .. ' '
      endfor
    endif
    if empty(f.filtered)
      lines[1] = '  ' .. MI.NoMatches()
    endif

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    this.ApplyFilterHls(lines, f)
  enddef

  def ApplyFilterHls(lines: list<string>, f: dict<any>): void
    prop_remove({type: TYPE_INPUT_POPUP_LABEL, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_OPTION, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_OPTION_SEL, bufnr: this.bufnr}, 1, len(lines))

    var inputText: string = lines[0]
    # Skip the prompt mark and space before the typed text: 2 characters.
    var cursorCharIdx: number = 2 + f.cursor
    var cursorByteCol: number = byteidx(inputText, cursorCharIdx) + 1
    var nextByteCol: number = byteidx(inputText, cursorCharIdx + 1)
    var cursorLen: number = (nextByteCol == -1 ? strlen(inputText) : nextByteCol) - (cursorByteCol - 1)
    prop_add(1, cursorByteCol, {
      type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr, length: max([cursorLen, 1]),
    })

    this._fieldHit = []
    this._optionHit = []
    for i in range(min([len(f.filtered) - f.scrollTop, f.maxVisible]))
      var idx: number = f.scrollTop + i
      var lnum: number = i + 2
      var text: string = lines[lnum - 1]
      var propType: string = idx == f.selectedIdx ? 'InputPopupOptionSelected' : 'InputPopupOption'
      # Stop before the scrollbar column, which has its own highlight.
      var length: number = this.FilterScrolls(f) ? strlen(text) - 1 : strlen(text)
      prop_add(lnum, 1, {
        type: propType, bufnr: this.bufnr, length: max([length, 1]),
      })
      add(this._optionHit, {idx: 0, optionIdx: idx, lnum: lnum, startCol: 1, endCol: strlen(text)})
    endfor
    this.DrawFilterScrollbar(f)
  enddef

  # METHOD: Return true while a filter list is longer than its rows.
  def FilterScrolls(f: dict<any>): bool
    return len(f.filtered) > f.maxVisible
  enddef

  # METHOD: Draw a scrollbar in the last column of the list rows, only
  # while the list is longer than its rows. PmenuSbar colors the track and
  # PmenuThumb the thumb, as in Vim's completion menu. The size and place
  # of the thumb show which part of the list is visible. RenderFilter has
  # already padded the rows, so the last column is free.
  def DrawFilterScrollbar(f: dict<any>): void
    prop_remove({type: TYPE_INPUT_POPUP_SCROLLBAR, bufnr: this.bufnr, all: true})
    prop_remove({type: TYPE_INPUT_POPUP_THUMB, bufnr: this.bufnr, all: true})
    if !this.FilterScrolls(f)
      return
    endif
    var total: number = len(f.filtered)
    var rows: number = f.maxVisible
    var thumbSize: number = max([1, rows * rows / total])
    var thumbTop: number = (f.scrollTop * (rows - thumbSize) + (total - rows) / 2) / (total - rows)
    for i in range(rows)
      var lnum: number = i + 2
      prop_add(lnum, strlen(getbufline(this.bufnr, lnum)[0]), {
        type: i >= thumbTop && i < thumbTop + thumbSize ? TYPE_INPUT_POPUP_THUMB : TYPE_INPUT_POPUP_SCROLLBAR,
        bufnr: this.bufnr, length: 1,
      })
    endfor
  enddef

  def RenderMultiline(): void
    var f: dict<any> = this.fields[0]
    if f.cursorLine < f.scrollOffset
      f.scrollOffset = f.cursorLine
    elseif f.cursorLine >= f.scrollOffset + f.rows
      f.scrollOffset = f.cursorLine - f.rows + 1
    endif

    var lines: list<string> = []
    for i in range(f.rows)
      var lineIdx: number = f.scrollOffset + i
      add(lines, lineIdx < len(f.lines) ? f.lines[lineIdx] : '')
    endfor
    # The cursor is a highlighted character, so at the end of its line it
    # needs a space to show on, as text fields have their padding. Only the
    # drawing gets the space, not the text.
    # REFERENCE: https://github.com/Galvarcus/bartleby/issues/3
    var cursorIdx: number = f.cursorLine - f.scrollOffset
    if cursorIdx >= 0 && cursorIdx < len(lines) && f.cursorCol >= strchars(lines[cursorIdx])
      lines[cursorIdx] ..= ' '
    endif
    var btnLnum: number = -1
    var btnMeta: list<dict<any>> = []
    if !empty(this.buttons)
      var buttons: dict<any> = this.LayoutBtns()
      lines->add(buttons.line)
      btnLnum = len(lines)
      btnMeta = buttons.meta
    endif

    this.WriteLines(lines)
    this.ApplyBtnHls(lines, btnLnum, btnMeta)
    this.ApplyMultilineHls(lines, f)
  enddef

  # METHOD: Draw the cursor of the multiline field f, while it has focus.
  def ApplyMultilineHls(lines: list<string>, f: dict<any>): void
    prop_remove({type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr}, 1, len(lines))
    if this.currentIdx != 0
      return
    endif

    var cursorScreenLine: number = f.cursorLine - f.scrollOffset + 1
    if cursorScreenLine >= 1 && cursorScreenLine <= len(lines)
      var text: string = lines[cursorScreenLine - 1]
      var cursorByteCol: number = byteidx(text, f.cursorCol) + 1
      var nextByteCol: number = byteidx(text, f.cursorCol + 1)
      var cursorLen: number = (nextByteCol == -1 ? strlen(text) : nextByteCol) - (cursorByteCol - 1)
      prop_add(cursorScreenLine, cursorByteCol, {
        type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr, length: max([cursorLen, 1]),
      })
    endif
  enddef

  # METHOD: Draw the popup: the fields, row by row, then the buttons, with
  # their highlights. A popup of one filter or multiline field has a
  # drawing of its own.
  def Render(): void
    if this.bufnr == -1
      return
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# TYPE_FILTER
      this.RenderFilter()
      return
    endif
    if len(this.fields) == 1 && this.fields[0].type ==# TYPE_MULTILINE
      this.RenderMultiline()
      return
    endif
    var layout: dict<any> = this.LayoutFields()
    var lines: list<string> = layout.lines
    var btnLnum: number = -1
    var btnMeta: list<dict<any>> = []
    if !empty(this.buttons)
      var buttons: dict<any> = this.LayoutBtns()
      lines->add(buttons.line)
      btnLnum = len(lines)
      btnMeta = buttons.meta
    endif
    this.WriteLines(lines)
    this.ApplyHls(lines, layout.meta, btnLnum, btnMeta)
  enddef

  # METHOD: Lay out the fields: the fields of a row on one line, and a
  # choice field on a line of its own. Returns the lines, and for each
  # field where its parts are, for ApplyHls.
  def LayoutFields(): dict<any>
    var lines: list<string> = []
    var meta: list<dict<any>> = []
    # The line being built: its row, its text, and its length in characters.
    var row: dict<any> = {num: -1, text: '', chars: 0}
    for idx in range(len(this.fields))
      var f: dict<any> = this.fields[idx]
      if f.row != row.num
        if row.num != -1
          add(lines, row.text)
        endif
        row = {num: f.row, text: '', chars: 0}
      endif
      var label: string = f.label .. ': '
      var labelStartChar: number = row.chars
      AppendTo(row, label)
      if f.type ==# CO.TYPE_CHOICE
        add(meta, this.LayoutChoice(idx, f, row, labelStartChar, strchars(label)))
        add(lines, row.text)
        row = {num: -1, text: '', chars: 0}
      else
        add(meta, this.LayoutText(idx, f, row, labelStartChar, strchars(label)))
      endif
    endfor
    if row.num != -1
      add(lines, row.text)
    endif
    return {lines: lines, meta: meta}
  enddef

  # METHOD: Add the options of the choice field f to row. Returns where its
  # label and options are.
  def LayoutChoice(idx: number, f: dict<any>, row: dict<any>, labelStartChar: number,
      labelChars: number): dict<any>
    var optChars: list<dict<any>> = []
    for i in range(len(f.options))
      var startChar: number = row.chars
      AppendTo(row, '[ ' .. f.options[i] .. ' ]')
      add(optChars, {optionIdx: i, startChar: startChar, endChar: row.chars})
      if i < len(f.options) - 1
        AppendTo(row, '  ')
      endif
    endfor
    return {
      idx: idx, field: f, lnum: row.num + 1, isChoice: true,
      labelStartChar: labelStartChar, labelChars: labelChars,
      optChars: optChars,
    }
  enddef

  # METHOD: Add the visible part of the text field f to row, scrolled so
  # that the cursor of the focused field shows. Returns where its label and
  # value are.
  def LayoutText(idx: number, f: dict<any>, row: dict<any>, labelStartChar: number,
      labelChars: number): dict<any>
    if idx == this.currentIdx
      if f.cursor < f.offset
        f.offset = f.cursor
      elseif f.cursor > f.offset + f.width - 1
        f.offset = f.cursor - f.width + 1
      endif
    else
      f.offset = 0
    endif
    var visible: string = strcharpart(f.value, f.offset, f.width)
    var valueStartChar: number = row.chars
    AppendTo(row, visible .. repeat(' ', max([f.width - strchars(visible), 0])) .. '  ')
    return {
      idx: idx, field: f, lnum: row.num + 1, isChoice: false,
      labelStartChar: labelStartChar, labelChars: labelChars,
      valueStartChar: valueStartChar, valueChars: f.width,
    }
  enddef

  # METHOD: Lay out the buttons on one line. Returns the line, and where
  # each button is.
  def LayoutBtns(): dict<any>
    var line: string = ''
    var meta: list<dict<any>> = []
    for i in range(len(this.buttons))
      var startChar: number = strchars(line)
      line ..= '[ ' .. this.buttons[i].label .. ' ]'
      add(meta, {idx: i, startChar: startChar, endChar: strchars(line)})
      if i < len(this.buttons) - 1
        line ..= '  '
      endif
    endfor
    return {line: line, meta: meta}
  enddef

  # METHOD: Put lines in the popup buffer, and remove the lines after them.
  def WriteLines(lines: list<string>): void
    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif
  enddef

  def ApplyHls(lines: list<string>, meta: list<dict<any>>,
      btnLnum: number, btnCharMeta: list<dict<any>>): void
    prop_remove({type: TYPE_INPUT_POPUP_LABEL, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_BTN, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_BTN_ACTIVE, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_OPTION, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_OPTION_SEL, bufnr: this.bufnr}, 1, len(lines))

    this._fieldHit = []
    this._optionHit = []
    for m in meta
      var text: string = lines[m.lnum - 1]
      var labelStartCol: number = byteidx(text, m.labelStartChar) + 1
      var labelEndByte: number = byteidx(text, m.labelStartChar + m.labelChars)
      var labelLen: number = (labelEndByte == -1 ? strlen(text) : labelEndByte) - (labelStartCol - 1)
      prop_add(m.lnum, labelStartCol, {
        type: TYPE_INPUT_POPUP_LABEL, bufnr: this.bufnr, length: max([labelLen, 1]),
      })

      if m.isChoice
        for oc in m.optChars
          var optStartCol: number = byteidx(text, oc.startChar) + 1
          var optEndByte: number = byteidx(text, oc.endChar)
          var optEndCol: number = (optEndByte == -1 ? strlen(text) : optEndByte)
          var propType: string = oc.optionIdx == m.field.selectedIdx
            ? TYPE_INPUT_POPUP_OPTION_SEL : TYPE_INPUT_POPUP_OPTION
          prop_add(m.lnum, optStartCol, {
            type: propType, bufnr: this.bufnr, length: max([optEndCol - (optStartCol - 1), 1]),
          })
          add(this._optionHit, {idx: m.idx, optionIdx: oc.optionIdx, lnum: m.lnum,
            startCol: optStartCol, endCol: optEndCol})
        endfor
        continue
      endif

      var valStartCol: number = byteidx(text, m.valueStartChar) + 1
      var valEndByte: number = byteidx(text, m.valueStartChar + m.valueChars)
      var valEndCol: number = (valEndByte == -1 ? strlen(text) : valEndByte)
      add(this._fieldHit, {idx: m.idx, lnum: m.lnum, startCol: valStartCol, endCol: valEndCol})
    endfor

    if this.currentIdx < len(this.fields) && this.fields[this.currentIdx].type !=# CO.TYPE_CHOICE
      var activeMeta: dict<any> = meta[this.currentIdx]
      var f: dict<any> = activeMeta.field
      var cursorCharIdx: number = activeMeta.valueStartChar + (f.cursor - f.offset)
      var text: string = lines[activeMeta.lnum - 1]
      var cursorByteCol: number = byteidx(text, cursorCharIdx) + 1
      var nextByteCol: number = byteidx(text, cursorCharIdx + 1)
      var cursorLen: number = (nextByteCol == -1 ? strlen(text) : nextByteCol) - (cursorByteCol - 1)
      prop_add(activeMeta.lnum, cursorByteCol, {
        type: TYPE_INPUT_POPUP_CURSOR, bufnr: this.bufnr, length: max([cursorLen, 1]),
      })
    endif

    this.ApplyBtnHls(lines, btnLnum, btnCharMeta)
  enddef

  # METHOD: Highlight the buttons on line btnLnum, the one with focus as
  # active, and record where each is for mouse clicks. No line is -1.
  def ApplyBtnHls(lines: list<string>, btnLnum: number, btnCharMeta: list<dict<any>>): void
    prop_remove({type: TYPE_INPUT_POPUP_BTN, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_INPUT_POPUP_BTN_ACTIVE, bufnr: this.bufnr}, 1, len(lines))
    this._buttonHit = []
    if btnLnum == -1
      return
    endif
    var btnText: string = lines[btnLnum - 1]
    var activeBtnIdx: number = this.currentIdx - len(this.fields)
    for bm in btnCharMeta
      var startCol: number = byteidx(btnText, bm.startChar) + 1
      var endByte: number = byteidx(btnText, bm.endChar)
      var endCol: number = (endByte == -1 ? strlen(btnText) : endByte)
      var propType: string = bm.idx == activeBtnIdx ? 'InputPopupButtonActive' : 'InputPopupButton'
      prop_add(btnLnum, startCol, {
        type: propType, bufnr: this.bufnr, length: max([endCol - (startCol - 1), 1]),
      })
      add(this._buttonHit, {idx: bm.idx, lnum: btnLnum, startCol: startCol, endCol: endCol})
    endfor
  enddef
endclass
