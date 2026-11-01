vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# tty.vim: the colors for text consoles with 8 or 16 colors, such as the
# Linux virtual terminal. A terminal with more colors keeps the colors of
# the user's own theme, and Bartleby does not set any.
#
# A console like this has a black background, so Apply sets the background
# option to dark. That matters on 16 colors: Vim assumes a light background
# there, and its colors for it, such as dark blue, are hard to read on black.
#
# Design rules:
#   Only colors 0 to 7 are used for backgrounds, because Vim sends blink for
#   a bright background, which is bright only on the Linux console. Bright
#   text depends on the number of colors, because Vim treats it differently.
#   On 8 colors, bold with a color from 0 to 7 is bright, and Vim sends
#   nothing for a color from 8 to 15. On 16 colors, Vim drops bold when a
#   color from 0 to 7 is set, and sends a color from 8 to 15 as bold with
#   the color below it. So the table below says bold, and Apply uses the
#   number from 8 to 15 on 16 colors. Bold black is the dark gray.
#   Normal is left to the terminal, so a console with its own default
#   colors keeps them.
#   Text keeps a contrast of 4.0 or more on black, measured with the colors
#   of the Linux console. Marks that should hardly show, such as line
#   numbers, are dark gray, and keep 2.5.
#   Comments are cyan, never dark gray, so that a comment inside the bright
#   paragraph never looks like text that Spotlight has dimmed. Spotlight
#   dims to dark gray here, see spotlight.vim.
# License: GNU GPL 3.0
##############################################################################

import 'bartleby/variables/constants.vim' as CO

const HL_CURSOR: string = 'Cursor'
const HL_LINE_NR: string = 'LineNr'
const DIM_BOLD: string = 'ctermfg=0 cterm=bold'
const DIM_GREY: string = 'ctermfg=8'

# The groups, one per row: name, text color, background color, attributes.
# Colors are the numbers 0 to 7, and NONE leaves a color unset. Attributes
# are for the terminal, and NONE removes the defaults. Bold means bright
# text, see Apply. Pmenu has no bold, because a popup's text inherits it,
# and bold black in the selected entry is dark gray.
const GROUPS: list<string> = [
  'Comment        6     NONE  NONE',
  'Constant       3     NONE  NONE',
  'String         2     NONE  NONE',
  'Identifier     6     NONE  bold',
  'Statement      1     NONE  bold',
  'PreProc        5     NONE  bold',
  'Type           4     NONE  bold',
  'Special        5     NONE  bold',
  'Underlined     4     NONE  bold,underline',
  'Ignore         0     NONE  bold',
  'Todo           0     3     NONE',
  'Title          3     NONE  bold',
  'Directory      4     NONE  bold',
  'Question       2     NONE  bold',
  'MoreMsg        2     NONE  bold',
  'ModeMsg        NONE  NONE  bold',
  'WarningMsg     1     NONE  bold',
  'ErrorMsg       7     1     bold',
  'Error          7     1     bold',
  'Added          2     NONE  bold',
  'Changed        3     NONE  bold',
  'Removed        1     NONE  bold',
  'LineNr         0     NONE  bold',
  'CursorLineNr   3     NONE  bold',
  'NonText        0     NONE  bold',
  'SpecialKey     0     NONE  bold',
  'Whitespace     0     NONE  bold',
  'Conceal        0     NONE  bold',
  'SignColumn     6     NONE  NONE',
  'FoldColumn     6     NONE  NONE',
  'Folded         7     4     NONE',
  'ColorColumn    NONE  4     NONE',
  'CursorLine     NONE  NONE  underline',
  'CursorColumn   NONE  4     NONE',
  'Cursor         NONE  NONE  reverse',
  'Visual         NONE  NONE  reverse',
  'VisualNOS      NONE  NONE  underline',
  'Search         0     2     NONE',
  'IncSearch      NONE  NONE  reverse',
  'MatchParen     0     6     NONE',
  'QuickFixLine   0     6     NONE',
  'WildMenu       0     7     NONE',
  'Pmenu          7     4     NONE',
  'PmenuSel       0     7     NONE',
  'PmenuSbar      NONE  0     NONE',
  'PmenuThumb     NONE  7     NONE',
  'PmenuShadow    NONE  0     NONE',
  'StatusLine     0     7     NONE',
  'StatusLineNC   7     4     NONE',
  'VertSplit      7     4     NONE',
  'TabLine        7     4     NONE',
  'TabLineSel     0     7     NONE',
  'TabLineFill    NONE  4     NONE',
  'ToolbarLine    NONE  4     NONE',
  'ToolbarButton  0     7     NONE',
  'DiffAdd        0     2     NONE',
  'DiffChange     7     4     bold',
  'DiffDelete     7     1     bold',
  'DiffText       0     6     NONE',
  'SpellBad       1     NONE  bold,underline',
  'SpellCap       4     NONE  bold,underline',
  'SpellRare      5     NONE  bold,underline',
  'SpellLocal     6     NONE  bold,underline',
  'debugPC        NONE  4     NONE',
  'debugBreakpoint 7    1     bold',
]

# Groups that only point at another group.
const LINKS: list<list<string>> = [
  ['lCursor', HL_CURSOR],
  ['CursorIM', HL_CURSOR],
  ['CursorLineFold', 'FoldColumn'],
  ['CursorLineSign', 'SignColumn'],
  ['LineNrAbove', HL_LINE_NR],
  ['LineNrBelow', HL_LINE_NR],
  ['CurSearch', 'IncSearch'],
  ['StatusLineTerm', 'StatusLine'],
  ['StatusLineTermNC', 'StatusLineNC'],
  ['PopupNotification', CO.HL_PMENU],
  ['MessageWindow', CO.HL_PMENU],
  ['Terminal', 'Normal'],
  ['EndOfBuffer', 'NonText'],
]

# FUNCTION: Return true in a terminal with 8 or 16 colors, and false in a
# GUI, with termguicolors, and with any other number of colors.
export def IsLowColor(): bool
  var colors: number = str2nr(&t_Co)
  return !has('gui_running') && !(has('termguicolors') && &termguicolors)
    && (colors == 8 || colors == 16)
enddef

# FUNCTION: Return the names of the groups that the scheme sets, the rows
# of the table and the groups that only link.
export def GroupNames(): list<string>
  return GROUPS->mapnew((_, row) => split(row)[0]) + LINKS->mapnew((_, link) => link[0])
enddef

# FUNCTION: Return the table rows as lists of name, text color, background
# color, and attributes. The tests read the colors from it.
export def Rows(): list<list<string>>
  return GROUPS->mapnew((_, row) => split(row))
enddef

# FUNCTION: Return the text color of a row: the color from the table, or
# on 16 colors or more the bright number, 8 higher, when the row says bold.
def TextColor(color: string, attr: string): string
  if color ==# 'NONE' || attr !~# 'bold' || str2nr(&t_Co) < 16
    return color
  endif
  return string(str2nr(color) + 8)
enddef

# FUNCTION: Return the arguments of highlight for the dark gray that
# Spotlight dims to: bold black on 8 colors, and color 8 on 16 colors.
export def DimArgs(): string
  return str2nr(&t_Co) < 16 ? DIM_BOLD : DIM_GREY
enddef

# FUNCTION: Apply the colors under name, which colors/<name>.vim passes
# from its own file name. The background option is set first, because
# highlight clear uses it to choose its defaults.
export def Apply(name: string): void
  set background=dark
  highlight clear
  g:colors_name = name
  for row in GROUPS
    var column: list<string> = split(row)
    execute $'highlight {column[0]} ctermfg={TextColor(column[1], column[3])}'
      .. $' ctermbg={column[2]} cterm={column[3]}'
  endfor
  for link in LINKS
    execute $'highlight! link {link[0]} {link[1]}'
  endfor
enddef

# FUNCTION: Apply the colors at startup in a terminal with 8 or 16 colors,
# unless g:bartleby_tty_colors is off, or the user already chose a color
# scheme. The scheme file has the lowercase name of the plugin.
export def AutoApply(): void
  if !get(g:, 'bartleby_tty_colors', true) || exists('g:colors_name') || !IsLowColor()
    return
  endif
  execute 'colorscheme ' .. tolower(CO.PLUGIN_NAME)
enddef
