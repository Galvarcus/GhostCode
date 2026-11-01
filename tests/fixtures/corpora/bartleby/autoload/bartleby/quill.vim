vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# quill.vim: Quill, a word-processing mode for one buffer, converted from
# vim-pencil, github.com/preservim/vim-pencil, to a Vim9 class. For
# Focus and the normal editor window. Documents of the open scrive get
# Quill automatically, see AutoApply.
#
# Three wrap modes. Off. Hard: textwidth, and autoformat while you type.
# Soft: display wrap without textwidth, and movement by screen line as
# with gj and gk. Detection reads modelines and long lines, as Pencil's
# detect_wrap_mode does.
#
# QuillSession is defined before the functions that use it because
# several of them name it in a parameter or return type, and Vim9
# resolves a signature when the function is defined.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/locale/writing.vim' as MW
import autoload 'bartleby/table.vim' as TB
import 'bartleby/variables/constants.vim' as CO

const QUILLWRAPMODEDEFAULT_SOFT: string = 'soft'
const QUILLWRAPMODEDEFAULT_OFF: string = 'off'
const ATTR_NAME: string = 'name'
const KEYS_C_O_G_UP: string = "\<C-o>g\<Up>"
const KEYS_C_O_G_DOWN: string = "\<C-o>g\<Down>"
const KEY_NAME_CR: string = '<CR>'
const KEYS_UNDO_CR: string = "\<C-g>u\<CR>"
const WRAP_ARG_DETECT: string = 'detect'
const WRAP_ARG_TOGGLE: string = 'toggle'
const WRAP_ARG_HARD: string = 'hard'
const WRAP_ARG_ON: string = 'on'

var log = L.New(expand('<sfile>:t'))
var wrap_mode_default: string = g:bartleby_quill_wrap_mode_default
var quill_textwidth: number = g:bartleby_quill_textwidth
var autoformat: bool = g:bartleby_quill_autoformat
var quill_joinspaces: bool = g:bartleby_quill_joinspaces
var cursorwrap: bool = g:bartleby_quill_cursorwrap
var quill_conceallevel: number = g:bartleby_quill_conceallevel
var quill_concealcursor: string = g:bartleby_quill_concealcursor
var auto: bool = g:bartleby_quill_auto
var autoformat_config: dict<any> = g:bartleby_quill_autoformat_config
var autoformat_aliases: dict<any> = g:bartleby_quill_autoformat_aliases

const MODE_OFF: number = 0
const MODE_HARD: number = 1
const MODE_SOFT: number = 2
var soft_detect_sample: number = g:bartleby_quill_soft_detect_sample
var soft_detect_threshold: number = g:bartleby_quill_soft_detect_threshold

##############################################################################
# SECTION: Wrap mode detection. Reads modelines and sample lines for a
# hint, from Pencil's doModelines, doOne, and detect_wrap_mode.
##############################################################################

def ScanModelineItem(item: string, maxTw: number): number
  var m: list<string> = matchlist(item, '^\([a-z]\+\)=\([a-zA-Z0-9_.-]\+\)$')
  if len(m) > 1 && m[1] =~# 'textwidth\|tw'
    return max([maxTw, str2nr(m[2])])
  endif
  return maxTw
enddef

def ScanModeline(line: string, maxTw: number): number
  var result: number = maxTw
  var m: list<string> = matchlist(line,
    '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\s*\%(set\s\+\)\?\([^:]\+\):\S\@!')
  if len(m) > 0
    for item in split(m[3])
      result = ScanModelineItem(item, result)
    endfor
  endif
  var m2: list<string> = matchlist(line, '\%(\S\@<!\%(vi\|vim\([<>=]\?\)\([0-9]\+\)\?\)\|\sex\):\(.\+\)')
  if len(m2) > 0
    for item in split(m2[3], '[ \t:]')
      result = ScanModelineItem(item, result)
    endfor
  endif
  return result
enddef

def MaxTextwidthFromModelines(): number
  var maxTw: number = -1
  if line('$') > &modelines
    var candidates: list<string> = getline(1, &modelines) + getline(line('$') - &modelines, '$')
    for l in candidates
      if l =~# ':'
        maxTw = ScanModeline(l, maxTw)
      endif
    endfor
  else
    for l in getline(1, '$')
      maxTw = ScanModeline(l, maxTw)
    endfor
  endif
  return maxTw
enddef

def DetectWrapMode(maxTextwidth: number): number
  if maxTextwidth > 0
    return MODE_HARD
  endif
  if maxTextwidth ==# 0 || wrap_mode_default ==# QUILLWRAPMODEDEFAULT_SOFT
    return MODE_SOFT
  endif
  var sample: number = soft_detect_sample
  var threshold: number = soft_detect_threshold
  for l in getline(1, sample)
    if len(l) > threshold
      return MODE_SOFT
    endif
  endfor
  return wrap_mode_default ==# QUILLWRAPMODEDEFAULT_OFF ? MODE_OFF : MODE_HARD
enddef

# CLASS: The Quill state of one buffer, stored in b:bartleby_quill.

export class QuillSession
  var wrapMode: number = MODE_OFF
  var maxTextwidth: number = -1
  var suspendAf: bool = false
  var crMapped: bool = false
  var lastAutoformat: bool = false

  def SetWrapMode(mode: number): void
    this.wrapMode = mode
  enddef

  def SetMaxTextwidth(tw: number): void
    this.maxTextwidth = tw
  enddef

  def SetSuspendAf(val: bool): void
    this.suspendAf = val
  enddef

  def SetCrMapped(val: bool): void
    this.crMapped = val
  enddef

  def SetLastAutoformat(val: bool): void
    this.lastAutoformat = val
  enddef
endclass

def CurSession(): QuillSession
  var session: QuillSession = get(b:, 'bartleby_quill', null_object)
  if session is null_object
    session = QuillSession.new()
    b:bartleby_quill = session
  endif
  return session
enddef

##############################################################################
# SECTION: Autoformat. On only in hard mode, only in Insert mode, and
# only when the cursor is not in a syntax region that
# g:bartleby_quill_autoformat_config excludes, such as a code block or a
# heading.
##############################################################################

def SynStackNames(lnum: number, col: number): list<string>
  return synstack(lnum, col)->mapnew((_, id) => synIDattr(id, ATTR_NAME))
enddef

def MaybeEnableAutoformat(): void
  var session: QuillSession = CurSession()
  if session.suspendAf
    session.SetSuspendAf(false)
    return
  endif
  # Autoformat does not use formatexpr, and would join the rows of a table.
  if TB.InPara(line('.'))
    return
  endif

  var ft: string = get(autoformat_aliases, &filetype, &filetype)
  var cfg: dict<any> = get(autoformat_config, ft, {})
  var black: list<string> = get(cfg, 'black', [])
  var white: list<string> = get(cfg, 'white', [])
  var blackRe: string = empty(black) ? '' : '\v(' .. join(black, '|') .. ')'
  var whiteRe: string = empty(white) ? '' : '\v(' .. join(white, '|') .. ')'
  var enforcePrevLine: bool = get(cfg, 'enforce-previous-line', false)

  var lnum: number = line('.')
  var names: list<string> = SynStackNames(lnum, col('.'))
  var okay: bool = true

  if !empty(blackRe)
    for name in names
      if match(name, blackRe) >= 0
        okay = false
        break
      endif
    endfor
  endif

  if !empty(whiteRe) && !okay
    if empty(synstack(lnum, 1)) || empty(synstack(lnum, col('$') - 1))
      for name in names
        if match(name, whiteRe) >= 0
          okay = true
          break
        endif
      endfor
    endif
  endif

  if !empty(blackRe) && enforcePrevLine && okay && lnum > 1
    for name in SynStackNames(lnum - 1, 1)
      if match(name, blackRe) >= 0
        okay = false
        break
      endif
    endfor
  endif

  if okay
    set formatoptions+=a
  endif
enddef

# FUNCTION: Turn autoformat off when the cursor moves into a table while
# you type. It comes back at the next InsertEnter outside a table.
def StopAutoformatInTable(): void
  if &formatoptions =~# 'a' && TB.InPara(line('.'))
    set formatoptions-=a
  endif
enddef

# FUNCTION: Set autoformat for the buffer. af is 1 to turn it on, 0 to
# turn it off, and -1 to toggle it.
export def SetAutoFmt(af: number): void
  var session: QuillSession = CurSession()
  var newAf: bool = af ==# -1 ? !session.lastAutoformat : af ==# 1
  var isHard: bool = session.wrapMode ==# MODE_HARD

  if newAf && isHard
    augroup bartleby_quill_autoformat
      autocmd! * <buffer>
      autocmd InsertEnter <buffer> MaybeEnableAutoformat()
      autocmd CursorMovedI <buffer> StopAutoformatInTable()
      autocmd InsertLeave <buffer> set formatoptions-=a
    augroup END
  else
    augroup bartleby_quill_autoformat
      autocmd! * <buffer>
    augroup END
    if newAf && !isHard
      log.Warn(MW.AutoformatCanOnly())
      return
    endif
  endif
  session.SetLastAutoformat(newAf)
enddef

##############################################################################
# SECTION: Setup. Applies the wrap mode settings and mappings to the
# current buffer. The wrap argument is detect, off, hard, soft, or toggle.
##############################################################################

def ApplyHardSettings(session: QuillSession): void
  if &modeline ==# false && session.maxTextwidth > 0
    execute $'setlocal textwidth={session.maxTextwidth}'
  elseif &textwidth ==# 0
    execute $'setlocal textwidth={quill_textwidth}'
  else
    setlocal textwidth<
  endif
  setlocal nowrap
enddef

def ApplySoftSettings(): void
  setlocal textwidth=0
  setlocal wrap
  if exists('&linebreak')
    setlocal linebreak
    setlocal breakat-=*
  endif
  if exists('&breakindent')
    setlocal breakindent
  endif
enddef

def ClearWrapSettings(): void
  if exists('&breakindent')
    setlocal breakindent<
  endif
  if exists('&smartindent')
    setlocal smartindent<
  endif
  if exists('&cindent')
    setlocal cindent<
  endif
  if exists('&conceal')
    setlocal conceallevel<
    setlocal concealcursor<
  endif
  setlocal indentexpr<
  setlocal autoindent<
  setlocal list<
  setlocal wrapmargin<
  setlocal formatoptions<
  setlocal formatexpr<
enddef

def SetupNavigationMaps(wrapMode: number): void
  if wrapMode ==# MODE_SOFT
    nnoremap <buffer> <silent> $ g$
    nnoremap <buffer> <silent> 0 g0
    xnoremap <buffer> <silent> $ g$
    xnoremap <buffer> <silent> 0 g0
    noremap <buffer> <silent> <Home> g<Home>
    noremap <buffer> <silent> <End> g<End>
    nnoremap <buffer> <silent> g0 0
    nnoremap <buffer> <silent> g$ $
    xnoremap <buffer> <silent> g0 0
    xnoremap <buffer> <silent> g$ $
    inoremap <buffer> <silent> <Home> <C-o>g<Home>
    inoremap <buffer> <silent> <End> <C-o>g<End>
  else
    silent! nunmap <buffer> $
    silent! nunmap <buffer> 0
    silent! xunmap <buffer> $
    silent! xunmap <buffer> 0
    silent! nunmap <buffer> <Home>
    silent! nunmap <buffer> <End>
    silent! iunmap <buffer> <Home>
    silent! iunmap <buffer> <End>
  endif

  if wrapMode !=# MODE_OFF
    nnoremap <buffer> <silent> j gj
    nnoremap <buffer> <silent> k gk
    xnoremap <buffer> <silent> j gj
    xnoremap <buffer> <silent> k gk
    noremap <buffer> <silent> <Up> gk
    noremap <buffer> <silent> <Down> gj
    nnoremap <buffer> <silent> gj j
    nnoremap <buffer> <silent> gk k
    xnoremap <buffer> <silent> gj j
    xnoremap <buffer> <silent> gk k
    # A Scrivening maps the arrow keys itself, so that they pass its title
    # lines, and moves by screen lines otherwise.
    if SV.IsScrivening(bufnr())
      SV.MapArrows(KEYS_C_O_G_UP, KEYS_C_O_G_DOWN)
    else
      # The plain key while a completion menu shows, which C-o would close.
      inoremap <buffer> <silent> <expr> <Up> pumvisible() ? CO.KEY_UP : KEYS_C_O_G_UP
      inoremap <buffer> <silent> <expr> <Down> pumvisible() ? CO.KEY_DOWN : KEYS_C_O_G_DOWN
    endif
  else
    silent! nunmap <buffer> j
    silent! nunmap <buffer> k
    silent! xunmap <buffer> j
    silent! xunmap <buffer> k
    silent! unmap <buffer> <Up>
    silent! unmap <buffer> <Down>
    if SV.IsScrivening(bufnr())
      SV.MapArrows()
    else
      silent! iunmap <buffer> <Up>
      silent! iunmap <buffer> <Down>
    endif
  endif
enddef

def SetupPunctuationMaps(session: QuillSession): void
  if session.wrapMode !=# MODE_OFF
    for ch in ['.', '!', '?', ',', ';', ':']
      execute $'inoremap <buffer> {ch} {ch}<C-g>u'
    endfor
    inoremap <buffer> <C-u> <C-g>u<C-u>
    inoremap <buffer> <C-w> <C-g>u<C-w>
    if empty(maparg(KEY_NAME_CR, 'i'))
      # Enter picks from a completion menu, which C-g u would close.
      inoremap <buffer> <expr> <CR> pumvisible() ? CO.KEY_CR : KEYS_UNDO_CR
      session.SetCrMapped(true)
    else
      session.SetCrMapped(false)
    endif
  else
    for ch in ['.', '!', '?', ',', ';', ':']
      execute $'silent! iunmap <buffer> {ch}'
    endfor
    silent! iunmap <buffer> <C-u>
    silent! iunmap <buffer> <C-w>
    if session.crMapped
      silent! iunmap <buffer> <CR>
    endif
  endif
enddef

export def Init(wrapArg: string = WRAP_ARG_DETECT): void
  if W.RefusedInPane(MW.Quill())
    return
  endif
  var session: QuillSession = CurSession()
  session.SetSuspendAf(false)

  var mode: number = session.wrapMode
  if (mode !=# MODE_OFF && wrapArg ==# WRAP_ARG_TOGGLE) || wrapArg =~# '^\(0\|off\|disable\|false\)$'
    mode = MODE_OFF
  elseif wrapArg ==# WRAP_ARG_HARD
    mode = MODE_HARD
  elseif wrapArg ==# QUILLWRAPMODEDEFAULT_SOFT
    mode = MODE_SOFT
  elseif wrapArg ==# WRAP_ARG_ON || wrapArg ==# WRAP_ARG_TOGGLE
    session.SetMaxTextwidth(MaxTextwidthFromModelines())
    mode = DetectWrapMode(session.maxTextwidth)
  else
    session.SetMaxTextwidth(MaxTextwidthFromModelines())
    mode = DetectWrapMode(session.maxTextwidth)
  endif
  session.SetWrapMode(mode)

  SetAutoFmt(mode ==# MODE_HARD && autoformat ? 1 : 0)

  if mode ==# MODE_HARD
    ApplyHardSettings(session)
  elseif mode ==# MODE_SOFT
    ApplySoftSettings()
  else
    ClearWrapSettings()
  endif

  if mode !=# MODE_OFF
    setlocal display+=lastline
    setlocal backspace=indent,eol,start
    if quill_joinspaces
      setlocal joinspaces
    else
      setlocal nojoinspaces
    endif
  endif

  if cursorwrap && mode !=# MODE_OFF
    setlocal whichwrap+=<,>,b,s,h,l,[,]
  endif

  if mode !=# MODE_OFF
    setlocal nolist
    setlocal wrapmargin=0
    setlocal autoindent
    setlocal indentexpr=
    if exists('&smartindent')
      setlocal nosmartindent
    endif
    if exists('&cindent')
      setlocal nocindent
    endif
    setlocal formatoptions+=n1t
    setlocal formatoptions-=vwa2
    # Autoformat and wrapping leave a table alone, see table.vim.
    setlocal formatexpr=bartleby#table#FormatExpr()
    if exists('&conceal')
      execute $'setlocal conceallevel={quill_conceallevel}'
      execute $'setlocal concealcursor={quill_concealcursor}'
    endif
  endif

  SetupNavigationMaps(mode)
  SetupPunctuationMaps(session)
enddef

##############################################################################
# SECTION: Public entry points.
##############################################################################

export def Toggle(): void
  Init(WRAP_ARG_TOGGLE)
enddef

# FUNCTION: Apply Quill in hard wrap mode to a document of the open
# scrive. Runs on BufEnter, set in plugin/bartleby.vim, when
# g:bartleby_quill_auto is on.
export def AutoApply(): void
  if !auto || exists('b:bartleby_quill')
    return
  endif
  if W.IsChromeBuf(bufnr('%'))
    return
  endif
  var project: PO.Project = ST.Get()
  if project is null_object
    return
  endif
  if SV.DocHere(project) is null_object
    return
  endif
  Init(WRAP_ARG_DETECT)
enddef
