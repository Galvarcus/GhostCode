vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# focus.vim: Focus, a distraction-free writing mode, converted from Goyo,
# github.com/junegunn/goyo.vim, to a Vim9 class.
# Opens the current buffer alone in a new tab. Four empty pad windows
# center a writing column of fixed width, and optionally fixed height.
# The statusline, tabline, and ruler are hidden, and the window chrome
# takes the background color. Each tab can hold its own session, in the
# tab-local variable t:bartleby_focus_session, as in Goyo.
#
# Not converted: Goyo's decorative background patterns. Kept: handling
# for statusline plugins, see DisableThirdPartyStatuslines, because a
# plugin such as airline redraws its statusline whatever laststatus is.
# Also kept: guioptions handling, to hide GVim scrollbars.
#
# In the GUI, Focus can also set a font and enter fullscreen, see
# ApplyGuiSettings. The User BartlebyFocusEnter and BartlebyFocusLeave
# events, from Goyo's GoyoEnter and GoyoLeave, let other settings join.
#
# Paragraph dimming, as in Limelight, is Spotlight's job. Use it together
# with Focus.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/locale/writing.vim' as MW

const SIGNIFY_VAR: string = 'sy'
const BG_1: string = '-1'

var log = L.New(expand('<sfile>:t'))
var focus_width: any = g:bartleby_focus_width
var focus_height: any = g:bartleby_focus_height
var margin_top: number = g:bartleby_focus_margin_top
var margin_bottom: number = g:bartleby_focus_margin_bottom
var linenr: number = g:bartleby_focus_linenr
var focus_bg: string = g:bartleby_focus_bg
var focusfullscreen: bool = !!g:bartleby_focus_fullscreen
var focus_guifont: string = g:bartleby_focus_guifont

def RelSize(expr: any, limit: number): number
  if type(expr) ==# v:t_number
    return expr
  endif
  var text: string = expr
  if text !~# '%$'
    return str2nr(text)
  endif
  return limit * str2nr(text[ : -2]) / 100
enddef

def ClampVal(val: number, lo: number, hi: number): number
  return min([max([val, lo]), hi])
enddef


# FUNCTION: Stop statusline plugins from redrawing during Focus, and
# return which ones were stopped. Plugins such as airline redraw their
# statusline on window and buffer events, so laststatus alone does not
# hide it. Each call is guarded with silent!, so a plugin that is not
# installed changes nothing. Converted from Goyo.

def DisableThirdPartyStatuslines(): dict<bool>
  var disabled: dict<bool> = {}

  disabled.gitgutter = get(g:, 'gitgutter_enabled', 0) != 0
  if disabled.gitgutter
    silent! execute 'GitGutterDisable'
  endif

  disabled.signify = !empty(getbufvar(bufnr('%'), SIGNIFY_VAR))
  if disabled.signify
    silent! execute 'SignifyToggle'
  endif

  disabled.airline = exists('#airline')
  if disabled.airline
    silent! execute 'AirlineToggle'
  endif

  disabled.powerline = exists('#PowerlineMain')
  if disabled.powerline
    augroup PowerlineMain
      autocmd!
    augroup END
    augroup! PowerlineMain
  endif

  disabled.lightline = exists('#lightline')
  if disabled.lightline
    silent! call lightline#disable()
  endif

  return disabled
enddef

def RestoreThirdPartyStatuslines(disabled: dict<bool>): void
  if get(disabled, 'gitgutter', false)
    silent! execute 'GitGutterEnable'
  endif

  if get(disabled, 'signify', false)
    silent! execute 'SignifyToggle'
  endif

  if get(disabled, 'airline', false) && !exists('#airline')
    silent! execute 'AirlineToggle'
    # Airline needs two refreshes to avoid a drawing error when it is turned
    # on again, as in Goyo.
    silent! execute 'AirlineRefresh'
    silent! execute 'AirlineRefresh'
  endif

  if get(disabled, 'powerline', false) && !exists('#PowerlineMain')
    doautocmd PowerlineStartup VimEnter
    silent! execute 'PowerlineReloadColorscheme'
  endif

  if get(disabled, 'lightline', false)
    silent! call lightline#enable()
  endif

  if exists('#Powerline')
    doautocmd Powerline ColorScheme
  endif
enddef

# FUNCTION: Map Ctrl-W keys to do nothing while any Focus session is open.
# The mappings are global, because window commands are global. As in
# Goyo, a second session maps only the keys that the first did not, and
# records in mappedKeys the ones it must unmap.

def MapsNop(): list<string>
  var candidates: list<string> = ['R', 'H', 'J', 'K', 'L', '|', '_']
  var mapped: list<string> = candidates->filter((_, c) => maparg('<C-w>' .. c, 'n') ==# '')
  for c in mapped
    execute 'nnoremap <C-w>' .. escape(c, '|') .. ' <nop>'
  endfor
  return mapped
enddef

# FUNCTION: Apply a Ctrl-W resize key to the session of the current tab.
# The mapping is global, but the resize must change only this tab.
def FocusResizeKey(key: string): void
  if !exists('t:bartleby_focus_session')
    return
  endif
  var session: FocusSession = t:bartleby_focus_session
  var count: number = v:count1
  if key ==# '='
    session.ResetDimensions(session.dimExpr)
  elseif key ==# '>'
    session.AdjustWidth(2 * count)
  elseif key ==# '<'
    session.AdjustWidth(-2 * count)
  elseif key ==# '+'
    session.AdjustHeight(2 * count)
  elseif key ==# '-'
    session.AdjustHeight(-2 * count)
  endif
enddef

def MapsResize(): list<string>
  var keys: list<string> = ['=', '>', '<', '+', '-']
  var mapped: list<string> = keys->filter((_, c) => maparg('<C-w>' .. c, 'n') ==# '')
  for c in mapped
    execute $'nnoremap <silent> <C-w>{c} <ScriptCmd>FocusResizeKey({string(c)})<CR>'
  endfor
  return mapped
enddef

def UnmapCtrlW(keys: list<string>): void
  for c in keys
    execute 'nunmap <C-w>' .. escape(c, '|')
  endfor
enddef

##############################################################################
# SECTION: Session lifecycle.
##############################################################################
# FUNCTION: Start a Focus session. Enter and Exit are functions, not
# methods, because they create and remove the FocusSession object and
# save and restore the global options around it.

def Enter(dimExpr: string): void
  if exists('t:bartleby_focus_session') || W.RefusedInPane(MW.Focus())
    return
  endif

  var dim: Dimensions = Dimensions.Parse(dimExpr)
  if dim is null_object
    log.Error(MW.InvalidDimensionExpr(dimExpr))
    return
  endif

  var origTabNr: number = tabpagenr()
  var saved: dict<any> = SavedOptions()

  tab split
  var pluginState: dict<bool> = DisableThirdPartyStatuslines()
  var mappedKeys: list<string> = MapsNop() + MapsResize()
  var session: FocusSession = FocusSession.new(origTabNr, winbufnr(0), dim, dimExpr, saved,
    mappedKeys, pluginState)
  t:bartleby_focus_session = session

  session.HideLinenr()
  ApplyFocusOptions()
  session.OpenPads()
  StartFocusHooks()

  session.HideStatusline()
  if has('gui_running')
    ApplyGuiSettings(saved)
  endif

  # Let other settings join Focus: autocmd User BartlebyFocusEnter, and
  # BartlebyFocusLeave to reverse them. From Goyo's GoyoEnter.
  if exists('#User#BartlebyFocusEnter')
    doautocmd User BartlebyFocusEnter
  endif
enddef

# FUNCTION: Return the options that Focus changes, as they are, for Exit to
# put back.
def SavedOptions(): dict<any>
  var saved: dict<any> = {
    laststatus: &laststatus,
    showtabline: &showtabline,
    fillchars: &fillchars,
    winminwidth: &winminwidth,
    winwidth: &winwidth,
    winminheight: &winminheight,
    winheight: &winheight,
    ruler: &ruler,
    sidescroll: &sidescroll,
    sidescrolloff: &sidescrolloff,
  }
  if has('gui_running')
    saved.guioptions = &guioptions
  endif
  return saved
enddef

# FUNCTION: Set the options of the Focus layout: no status or tab line, no
# window borders, and windows that can be as small as one line.
def ApplyFocusOptions(): void
  &winheight = max([&winminheight, 1])
  set winminheight=1
  set winheight=1
  set winminwidth=1 winwidth=1
  set laststatus=0
  set showtabline=0
  set noruler
  set fillchars+=vert:\ 
  set fillchars+=stl:\ 
  set fillchars+=stlnc:\ 
  set sidescroll=1
  set sidescrolloff=0

  # Hide the scrollbars on the left in GVim.
  if has('gui_running')
    set guioptions-=l
    set guioptions-=L
  endif
enddef

# FUNCTION: Start the hooks that keep Focus in shape while it is active.
def StartFocusHooks(): void
  augroup bartleby_focus
    autocmd!
    autocmd TabLeave * ++nested FocusAutoExit()
    autocmd VimResized * FocusAutoResize()
    autocmd ColorScheme * FocusAutoTranquilize()
    autocmd BufWinEnter * FocusAutoHideChrome()
    autocmd WinEnter,WinLeave * FocusAutoHideStatusline()
  augroup END
enddef

def Exit(): void
  if !exists('t:bartleby_focus_session')
    return
  endif
  var session: FocusSession = t:bartleby_focus_session

  # Runs before the teardown, so that a BartlebyFocusLeave handler can
  # reverse its own setup while the Focus window is still current.
  if exists('#User#BartlebyFocusLeave')
    doautocmd User BartlebyFocusLeave
  endif

  augroup bartleby_focus
    autocmd!
  augroup END
  augroup bartleby_focus_pad
    autocmd!
  augroup END
  UnmapCtrlW(session.mappedKeys)

  var origTabNr: number = session.origTab
  var masterBuf: number = session.masterBuf
  var saved: dict<any> = session.saved
  var savedLine: number = line('.')
  var savedCol: number = col('.')

  if tabpagenr() ==# 1
    tabnew
    normal! gt
    bdelete
  endif
  tabclose
  execute 'tabnext ' .. origTabNr
  if winbufnr(0) ==# masterBuf
    cursor(savedLine, savedCol)
  endif
  RestoreThirdPartyStatuslines(session.pluginState)

  &winwidth = saved.winwidth
  &winminwidth = saved.winminwidth
  &winheight = max([saved.winminheight, 1])
  &winminheight = saved.winminheight
  &winheight = saved.winheight
  &laststatus = saved.laststatus
  &showtabline = saved.showtabline
  &fillchars = saved.fillchars
  &ruler = saved.ruler
  &sidescroll = saved.sidescroll
  &sidescrolloff = saved.sidescrolloff
  if has_key(saved, 'guioptions')
    &guioptions = saved.guioptions
  endif
  RestoreGuiSettings(saved)

  # Tranquilize changed global highlight groups, which closing the tab does
  # not undo. Loading the colorscheme again restores them.
  if exists('g:colors_name')
    execute 'colorscheme ' .. g:colors_name
  else
    colorscheme default
  endif
enddef

# FUNCTION: Set the GUI font and fullscreen for Focus, from
# g:bartleby_focus_guifont and g:bartleby_focus_fullscreen. Each value is
# saved in saved before it changes, and RestoreGuiSettings restores it
# when Focus ends, also after :q in the Focus window, see Blank.
#
# Fullscreen: MacVim has a fullscreen option. The GTK and Windows GUIs
# use the s flag in guioptions, which Exit restores with the rest of
# guioptions. Other GUIs have no fullscreen.
#
# A Vim without a GUI has neither guifont nor fullscreen, so a compiled
# function cannot name them. eval and :execute reach them at run time,
# and only when has('gui_running') is true.
def ApplyGuiSettings(saved: dict<any>): void
  if focus_guifont !=# ''
    saved.guifont = eval('&guifont')
    try
      execute $'&guifont = {string(focus_guifont)}'
    catch
      log.Error(MW.CouldNotSet(focus_guifont, v:exception))
      remove(saved, 'guifont')
    endtry
  endif
  if !focusfullscreen
    return
  endif
  if exists('+fullscreen')
    saved.fullscreen = eval('&fullscreen')
    execute '&fullscreen = true'
  elseif has('gui_gtk') || has('gui_win32')
    set guioptions+=s
  else
    log.Warn(MW.GUIHasNo())
  endif
enddef

def RestoreGuiSettings(saved: dict<any>): void
  if has_key(saved, 'guifont')
    execute $'&guifont = {string(saved.guifont)}'
  endif
  if has_key(saved, 'fullscreen')
    execute $'&fullscreen = {saved.fullscreen ? "true" : "false"}'
  endif
enddef

##############################################################################
# SECTION: Autocommand handlers. The events are global, so each handler
# does nothing unless the current tab has a Focus session.
##############################################################################

def FocusAutoExit(): void
  if exists('t:bartleby_focus_session')
    Exit()
  endif
enddef

def FocusAutoResize(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.ResizePads()
  endif
enddef

def FocusAutoTranquilize(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.Tranquilize()
  endif
enddef

def FocusAutoHideChrome(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.HideLinenr()
    session.HideStatusline()
  endif
enddef

def FocusAutoHideStatusline(): void
  if exists('t:bartleby_focus_session')
    var session: FocusSession = t:bartleby_focus_session
    session.HideStatusline()
  endif
enddef

##############################################################################
# SECTION: Public entry points.
##############################################################################

# FUNCTION: Toggle Focus with the default size. <leader>bz calls this.
export def Toggle(): void
  if exists('t:bartleby_focus_session')
    Exit()
  else
    Enter('')
  endif
enddef

# FUNCTION: Run :BartlebyFocus. With a bang, always exit. With a size
# while Focus is on, resize the running session instead of restarting
# it, as :Goyo does.
export def Execute(bang: bool, dimExpr: string): void
  if bang
    Exit()
    return
  endif

  if !exists('t:bartleby_focus_session')
    Enter(dimExpr)
  elseif dimExpr !=# ''
    var session: FocusSession = t:bartleby_focus_session
    session.ResetDimensions(dimExpr)
  else
    Exit()
  endif
enddef

# CLASS: The size of the writing column: width and height, and xoff and
# yoff to move it off center.
class Dimensions
  var width: number
  var height: number
  var xoff: number = 0
  var yoff: number = 0

  static def Default(): Dimensions
    var dim: Dimensions = Dimensions.new()
    dim.width = RelSize(focus_width, &columns)
    if margin_top < 0 && margin_bottom < 0
      dim.height = RelSize(focus_height, &lines)
      dim.yoff = 0
    else
      var top: number = max([0, RelSize(margin_top < 0 ? 4 : margin_top, &lines)])
      var bot: number = max([0, RelSize(margin_bottom < 0 ? 4 : margin_bottom, &lines)])
      dim.height = &lines - top - bot
      dim.yoff = top - bot
    endif
    return dim
  enddef

  # METHOD: Parse a Goyo size expression, <width>[+-xoff]x<height>[+-yoff].
  # Every part is optional and falls back to the global defaults. Return
  # null_object for an invalid expression, so that a mistyped argument
  # does nothing instead of failing.
  static def Parse(expr: string): Dimensions
    var dim: Dimensions = Dimensions.Default()
    if expr ==# ''
      return dim
    endif
    var parts: list<string> = matchlist(expr,
      '^\s*\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\%(x\([0-9]\+%\?\)\?\([+-][0-9]\+%\?\)\?\)\?\s*$')
    if empty(parts)
      return null_object
    endif
    if parts[1] !=# ''
      dim.width = RelSize(parts[1], &columns)
    endif
    if parts[2] !=# ''
      dim.xoff = RelSize(parts[2], &columns)
    endif
    if parts[3] !=# ''
      dim.height = RelSize(parts[3], &lines)
    endif
    if parts[4] !=# ''
      dim.yoff = RelSize(parts[4], &lines)
    endif
    return dim
  enddef

  # METHOD: Clamp the size. Code outside the class cannot write its fields,
  # error E1335, so FocusSession changes an existing Dimensions with these
  # methods.
  def ClampTo(maxWidth: number, maxHeight: number): void
    this.width = ClampVal(this.width, 2, maxWidth)
    this.height = ClampVal(this.height, 2, maxHeight)
  enddef

  def AdjustWidth(delta: number): void
    this.width += delta
  enddef

  def AdjustHeight(delta: number): void
    this.height += delta
  enddef
endclass

# CLASS: One Focus session in its own tab. Holds as class fields what Goyo
# keeps in t:goyo variables, stored in t:bartleby_focus_session of its
# tab.
export class FocusSession
  var origTab: number
  var masterBuf: number
  var dim: Dimensions
  var dimExpr: string
  var saved: dict<any>
  var mappedKeys: list<string>
  var pluginState: dict<bool>
  var padBufs: dict<number> = {}

  def new(this.origTab, this.masterBuf, this.dim, this.dimExpr, this.saved, this.mappedKeys,
      this.pluginState)
  enddef

  def SetPadBufs(l: number, r: number, t: number, b: number): void
    this.padBufs = {l: l, r: r, t: t, b: b}
  enddef

  # METHOD: Move the cursor out of a pad window as soon as it enters one,
  # on WinEnter or CursorMoved of the pad buffer, see SetupPad. When the
  # pads have collapsed, because a pad was closed or resized, exit Focus
  # cleanly instead of leaving a broken layout. This is also how :q in the
  # Focus window ends Focus.
  def Blank(repel: string): void
    if bufwinnr(this.padBufs.r) <= bufwinnr(this.padBufs.l) + 1
        || bufwinnr(this.padBufs.b) <= bufwinnr(this.padBufs.t) + 3
      # Exit changes the window layout, which Vim does not allow inside a
      # WinEnter autocommand, error E1312. Run it just after this autocommand.
      timer_start(0, (_) => Exit())
      return
    endif
    execute 'noautocmd wincmd ' .. repel
  enddef

  def HideStatusline(): void
    setlocal statusline=\ 
  enddef

  def HideLinenr(): void
    if !linenr
      setlocal nonumber
      if exists('&relativenumber')
        setlocal norelativenumber
      endif
    endif
    if exists('&colorcolumn')
      setlocal colorcolumn=
    endif
  enddef

  # METHOD: Create one pad window with openCmd, such as vertical topleft
  # new, make it inert, and return to the previous window. Enter calls this
  # once for each side.
  def InitPad(openCmd: string): number
    execute openCmd
    setlocal buftype=nofile bufhidden=wipe nomodifiable nobuflisted noswapfile
    setlocal nonumber nocursorline nocursorcolumn winfixwidth winfixheight
    setlocal statusline=\ 
    if exists('&relativenumber')
      setlocal norelativenumber
    endif
    if exists('&colorcolumn')
      setlocal colorcolumn=
    endif
    var bufNr: number = winbufnr(0)
    execute ':' .. winnr('#') .. 'wincmd w'
    return bufNr
  enddef

  # METHOD: Size and place one pad, and set its Blank and HideStatusline
  # autocommands. repel is the wincmd direction that moves the cursor back
  # out of the pad.
  def SetupPad(bufNr: number, vert: bool, size: number, repel: string): void
    var win: number = bufwinnr(bufNr)
    execute ':' .. win .. 'wincmd w'
    execute (vert ? 'vertical ' : '') .. 'resize ' .. max([0, size])

    augroup bartleby_focus_pad
      execute $'autocmd WinEnter,CursorMoved <buffer> ++nested t:bartleby_focus_session.Blank({string(repel)})'
      autocmd WinLeave <buffer> ++nested t:bartleby_focus_session.HideStatusline()
    augroup END

    # Fill a short pad with blank lines, so the GUI shows no scrollbar beside
    # an empty buffer.
    var diff: number = winheight(0) - line('$')
    if diff > 0
      setlocal modifiable
      append(0, repeat([''], diff))
      normal! gg
      setlocal nomodifiable
    endif

    execute ':' .. winnr('#') .. 'wincmd w'
  enddef

  def ResizePads(): void
    augroup bartleby_focus_pad
      autocmd!
    augroup END

    this.dim.ClampTo(&columns, &lines)

    var vmargin: number = max([0, (&lines - this.dim.height) / 2 - 1])
    var yoff: number = ClampVal(this.dim.yoff, -vmargin, vmargin)
    var top: number = vmargin + yoff
    var bot: number = vmargin - yoff - 1
    this.SetupPad(this.padBufs.t, false, top, 'j')
    this.SetupPad(this.padBufs.b, false, bot, 'k')

    var nwidth: number = max([len(string(line('$'))) + 1, &numberwidth])
    var width: number = this.dim.width + (&number ? nwidth : 0)
    var hmargin: number = max([0, (&columns - width) / 2 - 1])
    var xoff: number = ClampVal(this.dim.xoff, -hmargin, hmargin)
    this.SetupPad(this.padBufs.l, true, hmargin + xoff, 'l')
    this.SetupPad(this.padBufs.r, true, hmargin - xoff, 'h')
  enddef

  # METHOD: Give the chrome highlight groups the background color, so the
  # pads, the statusline, and the split lines look like empty space.
  def Tranquilize(): void
    var bg: string = synIDattr(synIDtrans(hlID('Normal')), 'bg#')
    var gui: bool = has('gui_running') || (has('termguicolors') && &termguicolors)
    var attr: string = gui ? 'gui' : 'cterm'
    var groups: list<string> = ['NonText', 'FoldColumn', 'ColorColumn',
      'VertSplit', 'StatusLine', 'StatusLineNC', 'SignColumn']
    for grp in groups
      if bg ==# BG_1 || bg ==# ''
        execute $'highlight {grp} {attr}fg={focus_bg} {attr}bg=NONE'
      else
        execute $'highlight {grp} {attr}fg={bg} {attr}bg={bg}'
      endif
      execute $'highlight {grp} {attr}=NONE'
    endfor
  enddef

  def AdjustWidth(delta: number): void
    this.dim.AdjustWidth(delta)
    this.ResizePads()
  enddef

  def AdjustHeight(delta: number): void
    this.dim.AdjustHeight(delta)
    this.ResizePads()
  enddef

  # METHOD: Open the four empty windows around the text, and size them.
  def OpenPads(): void
    var lBuf: number = this.InitPad('vertical topleft new')
    var rBuf: number = this.InitPad('vertical botright new')
    var tBuf: number = this.InitPad('topleft new')
    var bBuf: number = this.InitPad('botright new')
    this.SetPadBufs(lBuf, rBuf, tBuf, bBuf)
    this.ResizePads()
    this.Tranquilize()
  enddef

  # METHOD: Set the size to expr, and keep expr as the size that Ctrl-W =
  # goes back to, so that it is the size asked for last. An invalid expr
  # changes nothing, with the error that Enter gives.
  def ResetDimensions(expr: string): void
    var parsed: Dimensions = Dimensions.Parse(expr)
    if parsed is null_object
      log.Error(MW.InvalidDimensionExpr(expr))
      return
    endif
    this.dim = parsed
    this.dimExpr = expr
    this.ResizePads()
  enddef
endclass
