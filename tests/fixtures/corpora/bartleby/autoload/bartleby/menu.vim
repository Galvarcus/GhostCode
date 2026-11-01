vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

import 'bartleby/variables/constants.vim' as CO

const POS_CENTER: string = 'center'
const COL_CURSOR: string = 'cursor'
const MENU_ZINDEX: number = 200
# Below the default of matchaddpos, so that the selection shows over the
# dimmed look of a disabled entry.
const DIM_PRIORITY: number = 5

##############################################################################
# Plugin_Name: Bartleby
# menu.vim: a reusable menu widget for the terminal and the GUI.
# License: GNU GPL 3.0
#
# Design: one item tree, shown in two ways that can be used together.
#
#   1. Popup mode, the default.
#      Drawn with popup_create.
#      In the GUI, the root is a bordered popup with a title, placed by
#      pos: at the cursor, centered, or at a line and column.
#      In the terminal, the root is a menu bar across the top of the
#      screen, without border or title, like Midnight Commander. An
#      item on the bar opens a bordered dropdown one row below it,
#      aligned under the item's label.
#      In both, each deeper level is a bordered popup without a title,
#      to the right of its parent.
#
#   2. Native mode, optional, through RegisterAsVimMenu. Builds :amenu
#      entries from the same tree, so the menu also appears in the gVim
#      menu bar and runs with :emenu. It does not change the popup.
#
# The selection highlight uses matchaddpos through win_execute, not text
# properties. Text properties show correct colors only for the first
# highlighted span on a line, which popupbuttons.vim showed earlier.
##############################################################################

# Item id to MenuItem, for the native :amenu dispatch.
var itemRegistry: dict<any> = {}
var idSeed: number = 0

# The autoload name of this script, such as bartleby#menu#. Vim runs a native
# menu entry in no script, so the entry can call a function of this script
# only by that name. A short name, or ScriptCmd, fails there with E117. The
# script must be in an autoload directory.
const AUTOLOAD_PREFIX: string = expand('<sfile>:p')
  ->substitute('^.*[/\\]autoload[/\\]', '', '')
  ->substitute('\.vim$', '', '')
  ->substitute('[/\\]', '#', 'g') .. '#'

# FUNCTION: Run the item with the given id. The target of the native menu
# entries that RegisterAsVimMenu creates, which call it by its autoload name.
export def MenuInvoke(id: string)
  if itemRegistry->has_key(id)
    var it = itemRegistry[id]
    if it.Action != null_function
      it.Action(it)
    endif
  endif
enddef

# CLASS: One menu entry: a label with an action, or a submenu.
export class MenuItem
  public var label: string
  # Called as Action(item) with this MenuItem.
  public var Action: func = null_function
  public var data: any = v:none
  public var enabled: bool = true
  # Called as When() at each Sync, to set enabled. Without it, enabled
  # keeps the value that the caller set.
  public var When: func(): bool = null_function
  public var separator: bool = false
  # The path of the native entry, set by RegisterAsVimMenu.
  public var vimPath: string = ''
  # Child MenuItems. A nonempty list makes this entry a submenu.
  public var items: list<any> = []

  def new(this.label, Action: func = null_function, data: any = v:none)
    this.Action = Action
    this.data = data
  enddef

  def IsSubmenu(): bool
    return len(this.items) > 0
  enddef

  def AddItem(label: string, Action: func = null_function, data: any = v:none): MenuItem
    var item = MenuItem.new(label, Action, data)
    this.items->add(item)
    return item
  enddef
endclass

# CLASS: A menu of MenuItems, shown as popups or as a native menu.
export class Menu
  # Identity.
  var name: string
  var title: string

  # Content.
  var items: list<any> = []

  # Appearance. Change any of these before the menu opens.
  public var normal_hl: string = 'Pmenu'
  public var select_hl: string = 'PmenuSel'
  public var disabled_hl: string = 'Comment'
  public var border: list<number> = [1, 1, 1, 1]
  public var padding: list<number> = [0, 1, 0, 1]
  public var minwidth: number = 14
  public var submenu_marker: string = ' >'
  # One of cursor, center, or a list of line and column.
  public var pos: any = 'cursor'

  # Behavior.
  public var close_on_select: bool = true
  public var wrap_navigation: bool = true

  # Internal state. Do not set these directly.
  # Popup ids, from the root to the deepest level.
  var _stack: list<number> = []
  # Window id to the items shown in that window.
  var _itemsOf: dict<any> = {}
  # Window id to its selected index.
  var _cur: dict<number> = {}
  # Window id to the match id of its selection highlight.
  var _selMatch: dict<number> = {}
  # Window id to true when the window is a menu bar.
  var _isBar: dict<bool> = {}
  # Window id to the start column of each item on the bar.
  var _barCols: dict<any> = {}

  def new(this.name, title: string = '')
    this.title = title == '' ? this.name : title
  enddef

  ############################################################################
  # SECTION: Building.
  ############################################################################

  def AddItem(label: string, Action: func = null_function, data: any = v:none): MenuItem
    var item = MenuItem.new(label, Action, data)
    this.items->add(item)
    return item
  enddef

  ############################################################################
  # SECTION: Open and close.
  ############################################################################

  def IsOpen(): bool
    return len(this._stack) > 0 && !empty(popup_getpos(this._stack[0]))
  enddef

  def Toggle()
    if this.IsOpen()
      this.Close()
    else
      this.Open()
    endif
  enddef

  def Open()
    if this.IsOpen()
      return
    endif
    this._stack = []
    if has('gui_running')
      this._ShowLevel(this.items, -1, 0)
    else
      this._ShowBar()
    endif
  enddef

  def Close()
    # Close the deepest level first.
    for id in reverse(copy(this._stack))
      if !empty(popup_getpos(id))
        # This runs the popup callback, and _OnClose clears the state.
        popup_close(id)
      endif
    endfor
    this._stack = []
  enddef

  ############################################################################
  # SECTION: Rendering.
  ############################################################################

  def _Lines(items: list<any>): list<string>
    var w = this.minwidth
    for it in items
      w = max([w, strdisplaywidth(it.label) + (it.IsSubmenu() ? strlen(this.submenu_marker) : 0)])
    endfor
    var lines: list<string> = []
    for it in items
      if it.separator
        lines->add(repeat('-', w))
      else
        var suffix = it.IsSubmenu() ? this.submenu_marker : ''
        var pad = w - strdisplaywidth(it.label) - strdisplaywidth(suffix)
        lines->add(it.label .. repeat(' ', max([pad, 1])) .. suffix)
      endif
    endfor
    return lines
  enddef

  # METHOD: Lay out the top-level items on one line, as a menu bar. Return
  # the padded line and the 1-based start column of each item, so that the
  # dropdown of an item aligns under it. The bar has no separators: a
  # separator gets column -1.
  def _BarLine(items: list<any>): dict<any>
    var cols: list<number> = []
    var line = ' '
    var pos = 2
    for it in items
      if it.separator
        cols->add(-1)
        continue
      endif
      cols->add(pos)
      line ..= it.label .. '   '
      pos += strdisplaywidth(it.label) + 3
    endfor
    var width = &columns
    if strdisplaywidth(line) < width
      line ..= repeat(' ', width - strdisplaywidth(line))
    endif
    return {line: line, cols: cols}
  enddef

  # METHOD: Show the terminal root: a menu bar across the top of the screen,
  # without border or title. The GUI root uses _ShowLevel. See Open.
  def _ShowBar()
    var items = this.items
    var built = this._BarLine(items)
    var winid = popup_create(built.line, {
      line: 1,
      col: 1,
      border: [0, 0, 0, 0],
      padding: [0, 0, 0, 0],
      highlight: this.normal_hl,
      wrap: false,
      mapping: false,
      zindex: MENU_ZINDEX,
      filter: (winid: number, key: string): bool => this._Filter(winid, key),
      callback: (winid: number, _result: any) => this._OnClose(winid),
    })
    this._stack->add(winid)
    this._itemsOf[winid] = items
    this._barCols[winid] = built.cols
    this._isBar[winid] = true
    this._cur[winid] = this._NextSelectable(items, -1, 1)
    this._Highlight(winid)
  enddef

  def _PosOpts(parentId: number, parentIdx: number): dict<any>
    if parentId != -1
      var pp = popup_getpos(parentId)
      var offset = (this.border[0] ? 1 : 0) + (this.title != '' ? 1 : 0)
      return {line: pp.line + offset + parentIdx, col: pp.col + pp.width}
    endif
    if type(this.pos) == v:t_list
      return {line: this.pos[0], col: this.pos[1]}
    elseif this.pos == POS_CENTER
      return {pos: POS_CENTER}
    else
      return {line: CO.BELOW_CURSOR, col: COL_CURSOR}
    endif
  enddef

  def _ShowLevel(items: list<any>, parentId: number, parentIdx: number, posOverride: dict<any> = {})
    var isRoot = parentId == -1 && empty(posOverride)
    var opts = empty(posOverride) ? this._PosOpts(parentId, parentIdx) : copy(posOverride)
    opts->extend({
      title: isRoot ? this.title : '',
      border: this.border,
      padding: this.padding,
      highlight: this.normal_hl,
      wrap: false,
      mapping: false,
      zindex: MENU_ZINDEX + len(this._stack),
      filter: (winid: number, key: string): bool => this._Filter(winid, key),
      callback: (winid: number, _result: any) => this._OnClose(winid),
    })
    var winid = popup_create(this._Lines(items), opts)
    # matchaddpos fails on a group that is not defined, as with syntax off.
    var dim: bool = hlexists(this.disabled_hl)
    for [i, it] in items(items)
      if dim && !it.enabled && !it.separator
        matchaddpos(this.disabled_hl, [i + 1], DIM_PRIORITY, -1, {window: winid})
      endif
    endfor
    this._stack->add(winid)
    this._itemsOf[winid] = items
    this._cur[winid] = this._NextSelectable(items, -1, 1)
    this._Highlight(winid)
  enddef

  ############################################################################
  # SECTION: Selection and highlighting.
  ############################################################################

  def _NextSelectable(items: list<any>, from: number, dir: number): number
    var n = len(items)
    if n == 0
      return -1
    endif
    var idx = from
    for _ in range(n)
      idx += dir
      if this.wrap_navigation
        idx = (idx + n) % n
      elseif idx < 0 || idx >= n
        return from
      endif
      if !items[idx].separator
        return idx
      endif
    endfor
    return from
  enddef

  def _Highlight(winid: number)
    if this._selMatch->has_key(winid)
      win_execute(winid, $'silent! call matchdelete({this._selMatch[winid]})')
    endif
    var idx = get(this._cur, winid, -1)
    if idx == -1
      return
    endif
    var items = this._itemsOf[winid]
    var hl = items[idx].enabled ? this.select_hl : this.disabled_hl
    if get(this._isBar, winid, false)
      var col = this._barCols[winid][idx]
      var len = strdisplaywidth(items[idx].label)
      win_execute(winid, $'g:__menu_mid = matchaddpos("{hl}", [[1, {col}, {len}]])')
    else
      win_execute(winid, $'g:__menu_mid = matchaddpos("{hl}", [{idx + 1}])')
    endif
    this._selMatch[winid] = g:__menu_mid
    unlet g:__menu_mid
  enddef

  ############################################################################
  # SECTION: Input handling.
  ############################################################################

  def _Filter(winid: number, key: string): bool
    var items = this._itemsOf[winid]
    var idx = get(this._cur, winid, -1)
    if get(this._isBar, winid, false)
      if key == 'h' || key == CO.KEY_LEFT
        this._cur[winid] = this._NextSelectable(items, idx, -1)
        this._Highlight(winid)
        return true
      elseif key == 'l' || key == CO.KEY_RIGHT
        this._cur[winid] = this._NextSelectable(items, idx, 1)
        this._Highlight(winid)
        return true
      elseif key == 'j' || key == CO.KEY_DOWN || key == CO.KEY_CR || key == ' '
        this._ActivateBar(winid, items, idx)
        return true
      elseif key == CO.KEY_ESC || key == 'q'
        this.Close()
        return true
      endif
      return false
    endif
    if key == 'j' || key == CO.KEY_DOWN
      this._cur[winid] = this._NextSelectable(items, idx, 1)
      this._Highlight(winid)
      return true
    elseif key == 'k' || key == CO.KEY_UP
      this._cur[winid] = this._NextSelectable(items, idx, -1)
      this._Highlight(winid)
      return true
    elseif key == CO.KEY_CR || key == 'l' || key == CO.KEY_RIGHT || key == ' '
      this._Activate(winid, items, idx)
      return true
    elseif key == 'h' || key == CO.KEY_LEFT
      this._Back(winid)
      return true
    elseif key == CO.KEY_ESC || key == 'q'
      this.Close()
      return true
    endif
    return false
  enddef

  def _Activate(winid: number, items: list<any>, idx: number)
    if idx < 0 || idx >= len(items)
      return
    endif
    var item = items[idx]
    if item.separator || !item.enabled
      return
    endif
    if item.IsSubmenu()
      this._ShowLevel(item.items, winid, idx)
    else
      if this.close_on_select
        this.Close()
      endif
      if item.Action != null_function
        item.Action(item)
      endif
    endif
  enddef

  def _ActivateBar(winid: number, items: list<any>, idx: number)
    if idx < 0 || idx >= len(items)
      return
    endif
    var item = items[idx]
    if item.separator || !item.enabled
      return
    endif
    if item.IsSubmenu()
      var col = this._barCols[winid][idx]
      var leftInset = (this.border[3] ? 1 : 0) + this.padding[3]
      this._ShowLevel(item.items, -1, 0, {line: 2, col: max([col - leftInset, 1])})
    else
      if this.close_on_select
        this.Close()
      endif
      if item.Action != null_function
        item.Action(item)
      endif
    endif
  enddef

  def _Back(winid: number)
    if len(this._stack) <= 1
      this.Close()
      return
    endif
    if this._stack[-1] == winid
      popup_close(winid)
    endif
  enddef

  def _OnClose(winid: number)
    var i = index(this._stack, winid)
    if i != -1
      this._stack = this._stack[0 : i - 1]
    endif
    this._itemsOf->remove(winid)
    this._cur->remove(winid)
    this._selMatch->remove(winid)
    if this._isBar->has_key(winid)
      this._isBar->remove(winid)
    endif
    if this._barCols->has_key(winid)
      this._barCols->remove(winid)
    endif
  enddef

  ############################################################################
  # SECTION: Native menu for the GUI and :emenu, optional.
  ############################################################################

  # METHOD: Build :amenu entries from this.items, so that the menu also
  # appears in the gVim menu bar and runs with :emenu. The popup menu,
  # Toggle, Open, and Close do not change.
  def RegisterAsVimMenu(root: string = '', priority: string = '')
    var r = root == '' ? this.title : root
    this._BuildVimMenu(r, this.items, priority)
  enddef

  # METHOD: Set each item that has When from it, in the popup menu and in
  # the native menu. Vim sends the native state to the GUI only before it
  # waits for input, so a call from a timer, which runs inside that wait,
  # shows in the GUI only after the next key.
  def Sync()
    this._SyncItems(this.items)
  enddef

  # METHOD: Show in the native entry of item whether item is enabled, after
  # it changed. An entry that was removed, or never registered, is left.
  def SyncVimItem(item: MenuItem)
    if item.vimPath == '' || empty(menu_info(item.vimPath))
      return
    endif
    execute $'amenu {item.enabled ? "enable" : "disable"} {item.vimPath}'
  enddef

  def UnregisterVimMenu(root: string = '')
    var r = root == '' ? this.title : root
    execute $'silent! aunmenu {r}'
  enddef

  def _SyncItems(items: list<any>)
    for item in items
      if item.IsSubmenu()
        this._SyncItems(item.items)
      elseif item.When != null_function
        item.enabled = item.When()
        this.SyncVimItem(item)
      endif
    endfor
  enddef

  def _BuildVimMenu(path: string, items: list<any>, priority: string)
    for item in items
      var mpath = $'{path}.{escape(item.label, ". \\")}'
      if item.separator
        execute $'amenu {priority} {mpath} <Nop>'
      elseif item.IsSubmenu()
        this._BuildVimMenu(mpath, item.items, priority)
      else
        idSeed += 1
        var id = $'{this.name}#{idSeed}'
        itemRegistry[id] = item
        item.vimPath = mpath
        execute $'amenu {priority} {mpath} <Cmd>call {AUTOLOAD_PREFIX}MenuInvoke("{id}")<CR>'
        if !item.enabled
          execute $'amenu disable {mpath}'
        endif
      endif
    endfor
  enddef
endclass
