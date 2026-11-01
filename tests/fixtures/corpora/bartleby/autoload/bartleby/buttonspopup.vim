vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# buttonspopup.vim: a reusable popup of clickable buttons.
# License: GNU GPL 3.0
#
# Usage:
#   import autoload 'bartleby/buttonspopup.vim' as BP
#
#   var buttons = [
#     BP.Button.new('Yes',    MyYesFunc),
#     BP.Button.new('No',     MyNoFunc),
#     BP.Button.new('Cancel', MyCancelFunc),
#   ]
#
#   var menu = BP.PopupBtnMenu.new(buttons, {
#     button: {columns: 3},
#     popup:  {title: ' Confirm ', border: []},
#     callback: (selected: any) => {
#       if selected != null
#         call(selected.Action, [])
#       endif
#     },
#   })
#   menu.Show()
#
# The popup never calls a button's Action. The callback decides.
#
# Button.new(label, Action, data = v:none)
#   label   string    Text of the button. A label without a line break
#                     shows as one line in brackets. A label with a line
#                     break shows as a bordered card, and its first line
#                     reads as a title. The caller splits the lines, for
#                     example with bartleby/wrap.vim.
#   Action  funcref   Returned to the callback unchanged, never called.
#   data    any       Optional payload for the caller, such as an id.
#                     Default v:none.
#
# PopupBtnMenu.new(buttons: list<Button>, opts: dict<any> = {})
#   opts has three sections. Only callback is required. The keys of opts
#   are a data contract, not Vim identifiers, so they keep snake_case.
#
#   opts.popup      Any popup_create option, such as title, border, pos,
#                   line, col, minwidth, zindex, or highlight. Passed
#                   through unchanged, except filter and callback, which
#                   this class sets.
#
#   opts.button     columns      number  Grid columns. Default: one row.
#                   spacing      number  Blank columns between buttons in
#                                        a row. Default 2.
#                   row_spacing  number  Blank lines between rows.
#                                        Default 1.
#                   width        number  Minimum width of every button.
#                                        Default 0: each button fits its
#                                        own text or longest card line.
#                   normal_hl    string  Highlight of an unselected
#                                        button. Default Pmenu.
#                   select_hl    string  Highlight of the selected
#                                        button. Default PmenuSel.
#                   selected     number  Index of the first selected
#                                        button. Default 0.
#
#   opts.on_key     Optional func(id: number, selected: number,
#                   key: string): bool, called before the popup's own key
#                   handling on every key. True means the key is handled.
#                   False passes it on to the built-in keys. Corkboard
#                   uses this for e to edit and J and K to reorder.
#
#   opts.callback   Required func(any). Called once when the popup closes,
#                   with the activated Button, or null when the popup was
#                   cancelled by Esc or a click outside it.
#
# menu.Show(): number   Opens the popup and returns its window id.
#
# Keys:
#   Left, Right, Tab, S-Tab, h, l   Move the selection. Wraps around.
#   Up, Down, k, j                  Move one grid row. Wraps per column.
#   CR, Space                       Activate the selected button.
#   LeftMouse                       Activate the clicked button. A click
#                                   outside the popup cancels it.
#   ScrollWheelUp, ScrollWheelDown  Scroll when the content is taller
#                                   than opts.popup.maxheight. Default:
#                                   the screen height less a margin. The
#                                   selection also scrolls into view.
#   Esc, C-c                        Cancel. The callback receives null.
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

const DIRECTION_RIGHT: string = 'right'
const DIRECTION_LEFT: string = 'left'
const DIRECTION_DOWN: string = 'down'
const DIRECTION_UP: string = 'up'
const KEY_LEFT_RELEASE: string = "\<LeftRelease>"

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Return the box corners and edges in this order: top left,
# top right, bottom left, bottom right, horizontal, vertical.
# Plain ASCII on purpose. Unicode box-drawing characters have ambiguous
# width, and when the terminal draws them at a different width than
# strdisplaywidth assumes, every highlight span computed from them is
# off. The ambiwidth option did not prevent this, because it describes
# what Vim assumes, not what the terminal draws.
def BoxChars(): list<string>
  return ['+', '+', '+', '+', '-', '|']
enddef

export class Btn
  public var label: string
  public var Action: func
  public var data: any = v:none

  def new(this.label, this.Action, this.data = v:none)
  enddef
endclass

export class PopupBtnMenu
  # Configuration, set from opts in the constructor.
  var buttons: list<Btn>
  var callback: func(any)
  var columns: number = 1
  var spacing: number = 2
  var rowSpacing: number = 1
  var buttonWidth: number = 0
  var normalHl: string = 'Pmenu'
  var selectHl: string = 'PmenuSel'
  var popupOpts: dict<any> = {}
  # Optional key hook from opts.on_key. See the Usage section in the file
  # header. Null means no hook.
  var OnKey: any = null

  # Runtime state.
  var id: number = -1
  var lines: list<string> = []
  var positions: list<dict<any>> = []
  var matchIds: list<number> = []
  var selected: number = 0

  def new(this.buttons, opts: dict<any> = {})
    if empty(this.buttons)
      log.Error(MI.PopupButtonMenuBtnsList())
      throw 'PopupButtonMenu: buttons list must not be empty'
    endif

    var btnOpts: dict<any> = get(opts, 'button', {})
    this.popupOpts = copy(get(opts, 'popup', {}))
    this.callback = get(opts, 'callback', null)
    if this.callback == null
      log.Error(MI.PopupButtonMenuOptsCb())
      throw 'PopupButtonMenu: opts.callback is required'
    endif

    this.columns = max([1, get(btnOpts, 'columns', len(this.buttons))])
    this.spacing = get(btnOpts, 'spacing', 2)
    this.rowSpacing = max([0, get(btnOpts, 'row_spacing', 1)])
    this.buttonWidth = get(btnOpts, 'width', 0)
    this.normalHl = get(btnOpts, 'normal_hl', CO.HL_PMENU)
    this.selectHl = get(btnOpts, 'select_hl', CO.HL_PMENU_SEL)
    this.OnKey = get(opts, 'on_key', null)
    this.selected = max([0, min([len(this.buttons) - 1, get(btnOpts, 'selected', 0)])])
  enddef

  ############################################################################
  # SECTION: Public API.
  ############################################################################

  def Show(): number
    this.BuildLayout()

    if !has_key(this.popupOpts, 'line') && !has_key(this.popupOpts, 'pos')
      this.popupOpts.line = (&lines - len(this.lines)) / 2
    endif
    if !has_key(this.popupOpts, 'col') && !has_key(this.popupOpts, 'pos')
      var maxWidth: number = 0
      for l in this.lines
        maxWidth = max([maxWidth, strdisplaywidth(l)])
      endfor
      this.popupOpts.col = (&columns - maxWidth) / 2
    endif
    if !has_key(this.popupOpts, 'border')
      this.popupOpts.border = []
    endif
    if !has_key(this.popupOpts, 'padding')
      this.popupOpts.padding = [0, 1, 0, 1]
    endif
    if !has_key(this.popupOpts, 'maxheight')
      # Leave room for the tabline, statusline, and command line. Vim shows a
      # scrollbar when the content is taller, in the right padding column,
      # so it does not cover card text. Keeping the selected button visible
      # still needs EnsureVisible.
      this.popupOpts.maxheight = max([3, &lines - 6])
    endif
    if !has_key(this.popupOpts, 'mapping')
      # The default mapping value is true: typed keys first go through the
      # user's own mappings. A mapping on Left or Right then takes the key
      # before this filter sees it, and Vim waits up to timeoutlen for
      # longer mapped sequences, which makes the popup feel slow. This popup
      # handles every key itself, so it takes the keys unmapped.
      this.popupOpts.mapping = false
    endif

    # Bound method funcrefs: Vim resolves this when the popup calls them,
    # so Filter and HandleClose keep full access to the object.
    this.popupOpts.filter = this.Filter
    this.popupOpts.callback = this.HandleClose

    this.id = popup_create(this.lines, this.popupOpts)

    # Each button has its own highlight match: normalHl, or selectHl for the
    # selected one. AddMatch explains why matchaddpos is used.
    this.matchIds = []
    for pos in this.positions
      var hl: string = pos.idx == this.selected ? this.selectHl : this.normalHl
      this.matchIds->add(this.AddMatch(pos, hl))
    endfor

    return this.id
  enddef

  ############################################################################
  # SECTION: Internals.
  ############################################################################

  # METHOD: Render one button. A label without a line break is one line,
  # as wide as its bracketed text or opts.button.width, whichever is
  # wider. A label with a line break is a bordered box, each line padded
  # to the widest line or opts.button.width. Returns a dict with lines
  # and width. All lines have the same display width.
  def RenderBtn(button: Btn): dict<any>
    var cellLines: list<string> = split(button.label, "\n", true)

    if len(cellLines) == 1
      var text: string = '[ ' .. cellLines[0] .. ' ]'
      var natural: number = strdisplaywidth(text)
      var width: number = this.buttonWidth > 0 ? max([this.buttonWidth, natural]) : natural
      var padTotal: number = width - natural
      var padLeft: number = padTotal / 2
      var padRight: number = padTotal - padLeft
      return {lines: [repeat(' ', padLeft) .. text .. repeat(' ', padRight)], width: width}
    endif

    var contentWidth: number = this.buttonWidth
    for l in cellLines
      contentWidth = max([contentWidth, strdisplaywidth(l)])
    endfor

    var chars: list<string> = BoxChars()
    var boxLines: list<string> = [chars[0] .. repeat(chars[4], contentWidth + 2) .. chars[1]]
    for l in cellLines
      boxLines->add(chars[5] .. ' ' .. l .. repeat(' ', contentWidth - strdisplaywidth(l))
        .. ' ' .. chars[5])
    endfor
    boxLines->add(chars[2] .. repeat(chars[4], contentWidth + 2) .. chars[3])

    return {lines: boxLines, width: contentWidth + 4}
  enddef

  def BuildLayout(): void
    var newLines: list<string> = []
    var newPositions: list<dict<any>> = []
    var idx: number = 0
    var btnCount: number = len(this.buttons)
    var rowCount: number = (btnCount + this.columns - 1) / this.columns
    var curLine: number = 1

    for r in range(rowCount)
      # Render every button of the row first, so that the row height, the
      # tallest button, is known. Shorter buttons get blank lines to match.
      var rendered: list<dict<any>> = []
      for c in range(this.columns)
        if idx + c >= btnCount
          break
        endif
        rendered->add(this.RenderBtn(this.buttons[idx + c]))
      endfor
      var rowHeight: number = 1
      for rb in rendered
        rowHeight = max([rowHeight, len(rb.lines)])
      endfor

      var colCursor: number = 1
      for i in range(len(rendered))
        var rb: dict<any> = rendered[i]
        var spans: list<list<number>> = []
        for subLine in range(len(rb.lines))
          spans->add([curLine + subLine, colCursor, rb.width])
        endfor
        newPositions->add({idx: idx + i, spans: spans})
        colCursor += rb.width + this.spacing
      endfor

      for subLine in range(rowHeight)
        var parts: list<string> = []
        for rb in rendered
          parts->add(subLine < len(rb.lines) ? rb.lines[subLine] : repeat(' ', rb.width))
        endfor
        newLines->add(join(parts, repeat(' ', this.spacing)))
      endfor
      curLine += rowHeight
      idx += len(rendered)

      if r < rowCount - 1
        for i in range(this.rowSpacing)
          newLines->add('')
          curLine += 1
        endfor
      endif
    endfor

    this.lines = newLines
    this.positions = newPositions
  enddef

  # METHOD: Add a highlight match for one button in the popup window and
  # return its match id, so that it can be removed on its own.
  #
  # Uses matchaddpos through win_execute, because matchaddpos works on the
  # current window and a popup cannot become current. Text properties do
  # not work here: with several highlighted spans on one popup line, only
  # the first span keeps its colors. The others show as bold. matchaddpos
  # draws each match independently, shows it on the next redraw, and takes
  # several positions in one call, so a whole card, border included, is
  # one match with one id.
  def AddMatch(pos: dict<any>, hlGroup: string): number
    var output: string = win_execute(this.id,
      $'echo matchaddpos("{hlGroup}", {string(pos.spans)})')
    return str2nr(trim(output))
  enddef

  # METHOD: Scroll the popup so that targetLine, the top line of a button,
  # is visible. The popup handles its own keys, so Vim's own scrolling on
  # cursor movement never runs for keyboard navigation.
  def EnsureVisible(targetLine: number): void
    var topLine: number = str2nr(trim(win_execute(this.id, 'echo line("w0")')))
    var botLine: number = str2nr(trim(win_execute(this.id, 'echo line("w$")')))
    if targetLine < topLine
      win_execute(this.id, $'normal! {targetLine}Gzt')
    elseif targetLine > botLine
      win_execute(this.id, $'normal! {targetLine}Gzb')
    endif
  enddef

  def SetSel(newIdx: number): void
    if newIdx == this.selected
      return
    endif

    matchdelete(this.matchIds[this.selected], this.id)
    this.matchIds[this.selected] =
      this.AddMatch(this.positions[this.selected], this.normalHl)

    matchdelete(this.matchIds[newIdx], this.id)
    this.matchIds[newIdx] = this.AddMatch(this.positions[newIdx], this.selectHl)

    this.selected = newIdx
    this.EnsureVisible(this.positions[newIdx].spans[0][0])
    redraw
  enddef

  def Filter(id: number, key: string): bool
    if this.OnKey != null && call(this.OnKey, [id, this.selected, key])
      return true
    endif

    var total: number = len(this.buttons)

    if key == CO.KEY_CR || key == ' '
      popup_close(id, this.selected)
      return true
    elseif key == CO.KEY_ESC || key == CO.KEY_C_C
      popup_close(id, -1)
      return true
    elseif key == CO.KEY_RIGHT || key == CO.KEY_TAB || key == 'l'
      this.SetSel(
        PopupBtnMenu.NextIdx(this.selected, total, this.columns, DIRECTION_RIGHT))
      return true
    elseif key == CO.KEY_LEFT || key == CO.KEY_S_TAB || key == 'h'
      this.SetSel(
        PopupBtnMenu.NextIdx(this.selected, total, this.columns, DIRECTION_LEFT))
      return true
    elseif key == CO.KEY_DOWN || key == 'j'
      this.SetSel(
        PopupBtnMenu.NextIdx(this.selected, total, this.columns, DIRECTION_DOWN))
      return true
    elseif key == CO.KEY_UP || key == 'k'
      this.SetSel(
        PopupBtnMenu.NextIdx(this.selected, total, this.columns, DIRECTION_UP))
      return true
    elseif key == CO.KEY_SCROLL_WHEEL_UP
      win_execute(id, 'normal! 3k')
      return true
    elseif key == CO.KEY_SCROLL_WHEEL_DOWN
      win_execute(id, 'normal! 3j')
      return true
    elseif key == CO.KEY_LEFT_MOUSE || key == KEY_LEFT_RELEASE
      var mousePos: dict<any> = getmousepos()
      if mousePos.winid == id
        for pos in this.positions
          for span in pos.spans
            if span[0] == mousePos.line && mousePos.column >= span[1]
                && mousePos.column <= span[1] + span[2] - 1
              popup_close(id, pos.idx)
              return true
            endif
          endfor
        endfor
        return true
      else
        popup_close(id, -1)
        return true
      endif
    endif

    return true
  enddef

  def HandleClose(id: number, result: number): void
    if result >= 0 && result < len(this.buttons)
      call(this.callback, [this.buttons[result]])
    else
      call(this.callback, [null])
    endif
  enddef

  ############################################################################
  # SECTION: Static helpers.
  ############################################################################

  static def NextIdx(selected: number, total: number, columns: number,
      direction: string): number
    var col: number = selected % columns

    if direction == DIRECTION_RIGHT
      return (selected + 1) % total
    elseif direction == DIRECTION_LEFT
      return (selected - 1 + total) % total
    elseif direction == DIRECTION_DOWN
      var candidate: number = selected + columns
      return candidate < total ? candidate : col
    elseif direction == DIRECTION_UP
      var candidate: number = selected - columns
      if candidate >= 0
        return candidate
      endif
      var last: number = col
      var i: number = col
      while i < total
        last = i
        i += columns
      endwhile
      return last
    endif
    return selected
  enddef
endclass
