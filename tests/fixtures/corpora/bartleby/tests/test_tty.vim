vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_tty.vim: the colors for terminals with 8 or 16 colors in
# tty.vim and colors/. The tests set the color count and apply the colors,
# and check that they use only the basic colors, that bright text follows
# what Vim sends for each color count, that the text is readable on the
# colors of the Linux console, that every group of Vim's own checklist is
# set, that startup applies the colors only when it should, and that
# Spotlight dims to dark gray there. Contrast is computed here, separately
# from the code under test, with the colors of the Linux console. The state
# of the colors is saved and restored around the tests.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/tty.vim' as TY
import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/spotlight.vim' as SP
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

const NAME: string = tolower(CO.PLUGIN_NAME)

# The colors 0 to 15 of the Linux console, as red, green, and blue.
const CONSOLE: list<list<number>> = [
  [0, 0, 0], [170, 0, 0], [0, 170, 0], [170, 85, 0],
  [0, 0, 170], [170, 0, 170], [0, 170, 170], [170, 170, 170],
  [85, 85, 85], [255, 85, 85], [85, 255, 85], [255, 255, 85],
  [85, 85, 255], [255, 85, 255], [85, 255, 255], [255, 255, 255],
]

# Marks that should hardly show, so they need less contrast.
const QUIET: list<string> = ['LineNr', 'NonText', 'SpecialKey', 'Whitespace', 'Conceal', 'Ignore']

# Groups that draw no text, so they have no text contrast to check.
const NO_TEXT: list<string> = ['PmenuSbar', 'PmenuThumb', 'PmenuShadow']

# The groups that Vim's own color scheme checker requires, from
# colors/tools/check_colors.vim of the Vim runtime, without Normal, which
# the scheme leaves to the terminal.
const REQUIRED: list<string> = [
  'ColorColumn', 'Comment', 'Conceal', 'Constant', 'CurSearch', 'Cursor',
  'CursorColumn', 'CursorLine', 'CursorLineNr', 'CursorLineFold',
  'CursorLineSign', 'DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText',
  'Directory', 'EndOfBuffer', 'Error', 'ErrorMsg', 'FoldColumn', 'Folded',
  'Identifier', 'Ignore', 'IncSearch', 'LineNr', 'LineNrAbove',
  'LineNrBelow', 'MatchParen', 'ModeMsg', 'MoreMsg', 'NonText',
  'Pmenu', 'PmenuSbar', 'PmenuSel', 'PmenuThumb', 'PopupNotification',
  'PreProc', 'Question', 'QuickFixLine', 'Search', 'SignColumn', 'Special',
  'SpecialKey', 'SpellBad', 'SpellCap', 'SpellLocal', 'SpellRare',
  'Statement', 'StatusLine', 'StatusLineNC', 'StatusLineTerm',
  'StatusLineTermNC', 'TabLine', 'TabLineFill', 'TabLineSel', 'Title',
  'Todo', 'ToolbarButton', 'ToolbarLine', 'Type', 'Underlined', 'VertSplit',
  'Visual', 'VisualNOS', 'WarningMsg', 'WildMenu', 'debugPC',
  'debugBreakpoint',
]

def Channel(value: number): float
  var level: float = value / 255.0
  return level <= 0.03928 ? level / 12.92 : pow((level + 0.055) / 1.055, 2.4)
enddef

def Luminance(color: number): float
  var rgb: list<number> = CONSOLE[color]
  return 0.2126 * Channel(rgb[0]) + 0.7152 * Channel(rgb[1]) + 0.0722 * Channel(rgb[2])
enddef

# FUNCTION: Return the contrast of two colors of the console as WCAG
# defines it: the relative luminance of the lighter plus 0.05 over that of
# the darker.
def Contrast(first: number, second: number): float
  var a: float = Luminance(first)
  var b: float = Luminance(second)
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05)
enddef

# FUNCTION: Return the color that shows for a text color and attributes: on
# 8 colors, bold with a color from 0 to 7 is the bright color.
def Shown(color: number, bold: bool, colors: number): number
  return colors == 8 && bold && color < 8 ? color + 8 : color
enddef

def Attr(group: string, what: string): string
  return synIDattr(synIDtrans(hlID(group)), what, 'cterm')
enddef

# FUNCTION: Apply the colors for a number of colors, as at startup.
def Use(colors: number): void
  &t_Co = string(colors)
  execute 'colorscheme ' .. NAME
enddef

def SaveState(): dict<any>
  return {tco: &t_Co, background: &background, scheme: get(g:, 'colors_name', ''),
    setting: get(g:, 'bartleby_tty_colors', true)}
enddef

# FUNCTION: Put back what SaveState saved, and the default highlights.
def RestoreState(saved: dict<any>): void
  SP.Execute(true, '')
  silent! unlet g:colors_name
  &t_Co = saved.tco
  execute 'set background=' .. saved.background
  highlight clear
  g:bartleby_tty_colors = saved.setting
  if saved.scheme !=# ''
    g:colors_name = saved.scheme
  endif
enddef

def Test_only_8_and_16_colors_count_as_a_console(): void
  var saved = SaveState()
  for [colors, expected] in [['8', true], ['16', true], ['0', false], ['', false],
      ['2', false], ['88', false], ['256', false]]
    &t_Co = colors
    assert_equal(expected, TY.IsLowColor(), $'t_Co {colors}')
  endfor
  RestoreState(saved)
enddef

def Test_scheme_uses_only_the_basic_colors(): void
  var saved = SaveState()
  for colors in [8, 16]
    Use(colors)
    for group in TY.GroupNames()
      var fg: string = Attr(group, 'fg')
      var bg: string = Attr(group, 'bg')
      assert_true(bg ==# '' || str2nr(bg) <= 7, $'{colors}: {group} background {bg}')
      assert_true(fg ==# '' || str2nr(fg) <= (colors == 8 ? 7 : 15), $'{colors}: {group} text {fg}')
    endfor
  endfor
  RestoreState(saved)
enddef

# FUNCTION: Vim sends bold with a color from 0 to 7 on 8 colors, drops it
# on 16 colors, and sends a color from 8 to 15 there as bold with the color
# below it. So each row must use what works on each count.
def Test_bright_text_follows_the_number_of_colors(): void
  var saved = SaveState()
  for [colors, group, fg, bold] in [
      [8, 'Directory', '4', '1'], [16, 'Directory', '12', '1'],
      [8, 'Title', '3', '1'], [16, 'Title', '11', '1'],
      [8, 'LineNr', '0', '1'], [16, 'LineNr', '8', '1'],
      [8, 'Comment', '6', ''], [16, 'Comment', '6', ''],
      [8, 'String', '2', ''], [16, 'String', '2', '']]
    Use(colors)
    assert_equal(fg, Attr(group, 'fg'), $'{colors}: {group} text')
    assert_equal(bold, Attr(group, 'bold'), $'{colors}: {group} bold')
  endfor
  RestoreState(saved)
enddef

def Test_text_is_readable_on_the_console_colors(): void
  for row in TY.Rows()
    var [group, fg, bg, attr] = row
    if attr =~# 'reverse' || index(NO_TEXT, group) >= 0
      continue
    endif
    var bold: bool = attr =~# 'bold'
    var text: number = fg ==# 'NONE' ? 7 : Shown(str2nr(fg), bold, 8)
    var back: number = bg ==# 'NONE' ? 0 : str2nr(bg)
    var needed: float = index(QUIET, group) >= 0 ? 2.5 : 4.0
    assert_true(Contrast(text, back) >= needed, $'{group}: {text} on {back}')
  endfor
enddef

# FUNCTION: Spotlight dims to dark gray, so no text color may be the same,
# or a comment in the bright paragraph would look dimmed.
def Test_no_text_color_is_the_dimmed_gray(): void
  for row in TY.Rows()
    var [group, fg, bg, attr] = row
    if fg ==# 'NONE' || index(QUIET, group) >= 0 || bg !=# 'NONE'
      continue
    endif
    assert_notequal(8, Shown(str2nr(fg), attr =~# 'bold', 8), $'{group} is dark gray')
  endfor
enddef

def Test_every_group_vim_requires_is_set(): void
  var names: list<string> = TY.GroupNames()
  for group in REQUIRED
    assert_true(index(names, group) >= 0, $'{group} is not set by the scheme')
  endfor
enddef

def Test_normal_is_left_to_the_terminal(): void
  var saved = SaveState()
  for colors in [8, 16]
    Use(colors)
    assert_equal('', Attr('Normal', 'fg'), $'{colors}: Normal text')
    assert_equal('', Attr('Normal', 'bg'), $'{colors}: Normal background')
  endfor
  RestoreState(saved)
enddef

# FUNCTION: Vim assumes a light background on 16 colors, whose colors are
# hard to read on a black console, so the scheme sets a dark one.
def Test_scheme_sets_a_dark_background(): void
  var saved = SaveState()
  set background=light
  Use(16)
  assert_equal('dark', &background)
  assert_equal(NAME, g:colors_name)
  RestoreState(saved)
enddef

def Test_startup_applies_the_colors_only_when_it_should(): void
  var saved = SaveState()
  for colors in [8, 16]
    # A console with no color scheme: applied.
    silent! unlet g:colors_name
    g:bartleby_tty_colors = true
    &t_Co = string(colors)
    TY.AutoApply()
    assert_equal(NAME, get(g:, 'colors_name', ''), $'{colors}: not applied')
    # A color scheme the user chose: left alone.
    g:colors_name = 'mine'
    TY.AutoApply()
    assert_equal('mine', g:colors_name, $'{colors}: replaced the choice of the user')
    # The setting is off: left alone.
    silent! unlet g:colors_name
    g:bartleby_tty_colors = false
    TY.AutoApply()
    assert_false(exists('g:colors_name'), $'{colors}: applied with the setting off')
  endfor
  # More colors keep the theme of the user.
  g:bartleby_tty_colors = true
  &t_Co = '256'
  TY.AutoApply()
  assert_false(exists('g:colors_name'), 'applied with 256 colors')
  RestoreState(saved)
enddef

def Test_spotlight_dims_to_dark_gray_on_a_console(): void
  var saved = SaveState()
  for [colors, fg, bold] in [[8, '0', '1'], [16, '8', '']]
    Use(colors)
    new
    setlocal buftype=nofile
    setline(1, ['One paragraph here.', '', 'Another paragraph here.'])
    cursor(1, 1)
    SP.Execute(false, 'Paragraph')
    assert_true(SP.IsOn(), $'{colors}: Spotlight did not turn on')
    assert_equal(fg, Attr('SpotlightDim', 'fg'), $'{colors}: dim color')
    # On 16 colors the number 8 is bold black without the attribute.
    assert_equal(bold, Attr('SpotlightDim', 'bold'), $'{colors}: dim bold')
    SP.Execute(true, '')
    bwipe!
  endfor
  RestoreState(saved)
enddef

# FUNCTION: A color scheme clears the highlights, so Spotlight must dim
# again when one is applied, as at startup.
def Test_spotlight_dims_again_after_the_scheme(): void
  var saved = SaveState()
  &t_Co = '16'
  new
  setlocal buftype=nofile
  setline(1, ['One paragraph here.'])
  SP.Execute(false, 'Paragraph')
  execute 'colorscheme ' .. NAME
  assert_equal('8', Attr('SpotlightDim', 'fg'))
  SP.Execute(true, '')
  bwipe!
  RestoreState(saved)
enddef

# FUNCTION: The text of a popup inherits the attributes of Pmenu. With bold
# there, the selected entry, black on gray, would be bold black, which is
# dark gray, and hard to read.
def Test_popup_text_is_not_bold(): void
  var saved = SaveState()
  for colors in [8, 16]
    Use(colors)
    assert_equal('', Attr('Pmenu', 'bold'), $'{colors}: Pmenu is bold')
  endfor
  RestoreState(saved)
enddef

# FUNCTION: Run a real Vim to the end of its startup, with Spotlight turned
# on by a command argument, which runs before VimEnter, and return the dim
# color and the scheme name that it ends with. The startup hook applies the
# scheme inside VimEnter, so its ColorScheme event only fires when the hook
# is nested. If it does not, Spotlight keeps no dim color.
def StartupState(colors: number, setup: string = ''): string
  var root: string = FI.Slashed(LA.PluginRoot())
  var script: string = FI.Slashed(tempname())
  var log: string = FI.Slashed(tempname())
  writefile([
    'vim9script',
    'augroup probe',
    '  autocmd VimEnter * ++once writefile([synIDattr(synIDtrans(hlID("SpotlightDim")), "fg", "cterm")'
      .. ' .. " " .. get(g:, "colors_name", "")], "' .. log .. '")',
    'augroup END',
  ], script)
  FI.Spawn($'{v:progpath} -es -u NONE -N --cmd "set rtp+={root},{FI.LoggerDir()}"'
    .. $' --cmd "set t_Co={colors}" {setup} -c "runtime plugin/bartleby.vim"'
    .. $' -c "BartlebySpotlight Paragraph" -S {script}')
  var result: string = filereadable(log) ? trim(join(readfile(log), ' ')) : 'no result'
  delete(script)
  delete(log)
  return result
enddef

def Test_startup_scheme_keeps_the_dim_color(): void
  assert_equal('0 ' .. NAME, StartupState(8))
  assert_equal('8 ' .. NAME, StartupState(16))
enddef

# FUNCTION: The setting for the color of dimmed text still wins on a
# console, as the documentation says. Spotlight reads it when it loads.
def Test_setting_for_dimmed_text_wins_on_a_console(): void
  # The color may be written as a number or as text.
  for setup in ['--cmd "let g:bartleby_spotlight_conceal_ctermfg = 3"',
      "--cmd \"let g:bartleby_spotlight_conceal_ctermfg = '3'\""]
    assert_equal('3 ' .. NAME, StartupState(8, setup), setup)
    assert_equal('3 ' .. NAME, StartupState(16, setup), setup)
  endfor
enddef

export def RunAll(): void
  # Nothing here applies to Windows. The suite sets t_Co to 8 or 16 and
  # measures the colors against the palette of the Linux console, and the
  # console of Windows has no such mode: Vim reports its own count there,
  # so tty#Apply is a path that no user of Windows reaches. Left in, the
  # suite never returned in CI, where each scheme that it applies sources
  # the color files again.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/44
  if has('win32')
    return
  endif
  Test_only_8_and_16_colors_count_as_a_console()
  Test_scheme_uses_only_the_basic_colors()
  Test_bright_text_follows_the_number_of_colors()
  Test_text_is_readable_on_the_console_colors()
  Test_no_text_color_is_the_dimmed_gray()
  Test_every_group_vim_requires_is_set()
  Test_normal_is_left_to_the_terminal()
  Test_scheme_sets_a_dark_background()
  Test_startup_applies_the_colors_only_when_it_should()
  Test_spotlight_dims_to_dark_gray_on_a_console()
  Test_spotlight_dims_again_after_the_scheme()
  Test_popup_text_is_not_bold()
  Test_startup_scheme_keeps_the_dim_color()
  Test_setting_for_dimmed_text_wins_on_a_console()
enddef
