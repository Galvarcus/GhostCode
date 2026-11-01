vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/writing.vim:
# the messages of the writing tools.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/writing.vim' as MW
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: autosave.vim
##############################################################################

export def AutoSaveFailed(file: any, err: any): string
  return printf(IN.T("auto-save failed for %s: %s"), file, err)
enddef

##############################################################################
# SECTION: focus.vim
##############################################################################

export def Focus(): string
  return IN.T("Focus")
enddef

export def InvalidDimensionExpr(dimExpr: any): string
  return printf(IN.T("invalid dimension expression: %s"), dimExpr)
enddef

export def CouldNotSet(font: any, err: any): string
  return printf(IN.T("could not set g:bartleby_focus_guifont \"%s\": %s"), font, err)
enddef

export def GUIHasNo(): string
  return IN.T("this GUI has no fullscreen mode - g:bartleby_focus_fullscreen has no effect")
enddef

##############################################################################
# SECTION: quill.vim
##############################################################################

export def AutoformatCanOnly(): string
  return IN.T("autoformat can only be enabled in hard line break mode")
enddef

export def Quill(): string
  return IN.T("Quill")
enddef

##############################################################################
# SECTION: scrivenings.vim
##############################################################################

export def FolderHasNo(): string
  return IN.T("this folder has no documents")
enddef

export def ScriveningNotSaved(): string
  return IN.T("the Scrivening was not saved, because a title line was changed or removed. Press u to undo it")
enddef

export def CouldNotWritten(path: any): string
  return printf(IN.T("%s could not be written"), path)
enddef

export def TitleLinesScrivening(): string
  return IN.T("the title lines of a Scrivening cannot be changed")
enddef

##############################################################################
# SECTION: spotlight.vim
##############################################################################

export def InvalidSpotlightDefault(): string
  return IN.T("Invalid g:bartleby_spotlight_default_coefficient. Expected: 0.0 to 1.0")
enddef

export def CannotCalcBg(): string
  return IN.T("Cannot calculate background color.")
enddef

export def UnsupportedColorScheme(varName: any): string
  return printf(IN.T("Unsupported color scheme. %s required."), varName)
enddef

export def UnsupportedTerminal(): string
  return IN.T("Unsupported terminal.")
enddef

export def Spotlight(): string
  return IN.T("Spotlight")
enddef

export def UnknownSpotlightMode(actualMode: any): string
  return printf(IN.T("unknown Spotlight mode: %s"), actualMode)
enddef

export def SpotlightModeNeeds(mode: any): string
  return printf(IN.T("Spotlight mode %s needs a part-of-speech tagger. Set g:bartleby_spotlight_tagger"), mode)
enddef

export def SpotlightModeNeedsPart(mode: any, reason: any): string
  return printf(IN.T("Spotlight mode %s needs a part-of-speech tagger: %s"), mode, reason)
enddef

export def Para(): string
  return IN.T("Paragraph")
enddef

export def Dialogue(): string
  return IN.T("Dialogue")
enddef

export def Nouns(): string
  return IN.T("Nouns")
enddef

export def Verbs(): string
  return IN.T("Verbs")
enddef

export def Adjectives(): string
  return IN.T("Adjectives")
enddef

export def Adverbs(): string
  return IN.T("Adverbs")
enddef

export def Pronouns(): string
  return IN.T("Pronouns")
enddef

export def Determiners(): string
  return IN.T("Determiners")
enddef

export def Prepositions(): string
  return IN.T("Prepositions")
enddef

export def Conjunctions(): string
  return IN.T("Conjunctions")
enddef

export def Auxiliaries(): string
  return IN.T("Auxiliaries")
enddef

export def Contractions(): string
  return IN.T("Contractions")
enddef

export def Fillers(): string
  return IN.T("Fillers")
enddef

export def Passive(): string
  return IN.T("Passive")
enddef

export def SpotlightMode(mode: any): string
  return printf(IN.T("Spotlight Mode: %s"), mode)
enddef

##############################################################################
# SECTION: table.vim
##############################################################################

export def Table(): string
  return IN.T("Table")
enddef

export def Columns(): string
  return IN.T("Columns")
enddef

export def Rows(): string
  return IN.T("Rows")
enddef

export def HeaderRow(): string
  return IN.T("Header row")
enddef

export def Alignment(): string
  return IN.T("Alignment")
enddef

export def Caption(): string
  return IN.T("Caption")
enddef

export def Left(): string
  return IN.T("Left")
enddef

export def Center(): string
  return IN.T("Center")
enddef

export def Right(): string
  return IN.T("Right")
enddef

export def AsIs(): string
  return IN.T("As it is")
enddef

export def Insert(): string
  return IN.T("Insert")
enddef

export def NoTables(): string
  return IN.T("A screenplay has no tables")
enddef

export def NoTableHere(): string
  return IN.T("No table under the cursor")
enddef

export def ColumnN(n: number): string
  return printf(IN.T("Column %d"), n)
enddef

export def BadShape(maxCols: number, maxRows: number): string
  return printf(IN.T("A table has 1 to %d columns and 1 to %d rows"), maxCols, maxRows)
enddef

export def DropCells(count: number): string
  return printf(IN.N("Drop %d cell that has text?", "Drop %d cells that have text?", count), count)
enddef
