vim9script

##############################################################################
# Plugin_Name: Bartleby
# syntax/fountain.vim: highlighting for Fountain screenplays. Fountain has
# structure that Markdown lacks: scene headings, character cues, dialogue
# without quotes, and transitions. ftdetect/fountain.vim gives these
# files their own filetype.
#
# Cue and dialogue detection and the rule order follow the vim-fountain
# plugin by Carson Fire. A cue line is \L*, no lowercase letter, which is
# simpler and more robust than a list of characters. When rules match at
# the same position, the one defined last wins, so scene headings and
# transitions, which are also lines in capitals, are defined after the
# dialogue region instead of being excluded from its pattern.
#
# No s:is_loaded guard: a syntax file runs once for every buffer.
# License: GNU GPL 3.0
##############################################################################

if exists('b:current_syntax')
  finish
endif

import 'bartleby/variables/constants.vim' as CO
syntax sync minlines=200

# Title page: lines of the form Key: value at the start of the file, up to
# the first blank line. Only when the first line has a colon, so a script
# that starts with a scene heading is not read as a title page.
syntax region fountainTitlePage start=/\%^.*:/ end=/^\s*$/ contains=fountainTitleKey keepend
syntax match fountainTitleKey /^\a[A-Za-z0-9 ]*:/ contained contains=NONE

# A character cue and its dialogue, as one region. The cue, the
# matchgroup, is a line with no lowercase letter. The dialogue is
# everything up to the next blank line. A region, not a match per line,
# gives the dialogue its own highlight, apart from the action lines.
execute 'syntax region fountainDialogue matchgroup=fountainCharacter'
  .. $' start=/{CO.FOUNTAIN_CHAR_PAT}/ end=/^\s*$/'
  .. ' contains=fountainParenthetical,fountainNote,fountainBoneyard,@fountainEmphasis'

# Parenthetical: a whole line in parentheses, inside a dialogue block.
syntax match fountainParenthetical /^\s*(.*)\s*$/ contained

# Scene headings: an INT, EXT, EST, or I/E prefix followed by a period, a
# slash, or a space, or a leading period that forces a heading, Fountain's
# escape for a heading without a standard prefix. Defined after
# fountainDialogue, so these lines are not read as character cues.
execute $'syntax region fountainSceneHeading start=/{CO.FOUNTAIN_SCENE_PREFIX_PAT}/ end=/$/'
  .. ' contains=fountainSceneNumber'
execute $'syntax match fountainSceneHeading /{CO.FOUNTAIN_FORCED_SCENE_PAT}.*$/'
syntax region fountainSceneNumber start=/#/ end=/#/ contained

# Transitions: a line in capitals that ends in TO:, or one of a few fixed
# transitions. Defined after fountainDialogue for the same reason as
# scene headings.
syntax match fountainTransition /^\L* TO:$/
syntax match fountainTransition /^\c\(fade in\|fade out\|fade to black\)[.:]\s*$/

# Sections, the outline of the script, which have nothing to do with scene
# headings: one to six number signs at the start of a line, then a space.
syntax match fountainSection /^#\{1,6}\s.*$/

# Synopsis: one leading equals sign, not three, see the page break rule.
syntax match fountainSynopsis /^=\([^=].*\)\?$/

# Page break: a line of three or more equals signs and nothing else.
syntax match fountainPageBreak /^=\{3,}\s*$/

# Lyrics: a leading tilde.
syntax match fountainLyric /^\s*\~.*$/

# Notes in double brackets, and boneyard blocks between /* and */. Both
# are left out of the compiled output, so they look like comments.
syntax region fountainNote start=/\[\[/ end=/\]\]/
syntax region fountainBoneyard start=/\/\*/ end=/\*\//

# Centered text between > and <. A leading > without a closing < is a
# forced transition instead.
syntax match fountainCenter /^\s*>.\{-}<\s*$/
syntax match fountainTransitionForced /^\s*>[^<]*$/

# Emphasis, Fountain's inline styling like Markdown. When several rules
# match at the same position, the one defined last wins, so the shortest
# marker comes first and the longest last: *** is bold italic, not
# italic.
syntax region fountainItalic start=/\*/ end=/\*/ oneline skip=/\\\*/
syntax region fountainBold start=/\*\*/ end=/\*\*/ oneline
syntax region fountainBoldItalic start=/\*\*\*/ end=/\*\*\*/ oneline
syntax region fountainUnderline start=/_/ end=/_/ oneline skip=/\\_/
syntax cluster fountainEmphasis contains=fountainBoldItalic,fountainBold,fountainItalic,fountainUnderline

highlight default link fountainTitlePage Comment
highlight default link fountainTitleKey Keyword
highlight default link fountainSceneHeading Statement
highlight default link fountainSceneNumber Number
highlight default link fountainTransition Statement
highlight default link fountainTransitionForced Statement
highlight default link fountainCharacter Type
highlight default link fountainDialogue String
highlight default link fountainParenthetical Comment
highlight default link fountainSection Title
highlight default link fountainSynopsis Comment
highlight default link fountainPageBreak Comment
highlight default link fountainLyric String
highlight default link fountainNote Todo
highlight default link fountainBoneyard Comment
highlight default link fountainCenter Statement
highlight default link fountainBoldItalic Special
highlight default link fountainBold Special
highlight default link fountainItalic Special
highlight default link fountainUnderline Underlined

b:current_syntax = 'fountain'
