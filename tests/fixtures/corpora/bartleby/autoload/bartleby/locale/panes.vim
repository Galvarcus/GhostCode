vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/panes.vim:
# the messages of panes and windows.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/panes.vim' as MP
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: closeall.vim
##############################################################################

export def NothingOpen(): string
  return IN.T("nothing of Bartleby is open")
enddef

export def ScriveningCouldNot(): string
  return IN.T("the Scrivening could not be saved, so it stays open. Use :BartlebyClose! to throw its changes away")
enddef

export def CouldNotSaved(name: any): string
  return printf(IN.T("%s could not be saved, so the windows stay open. Use :BartlebyClose! to throw its changes away"), name)
enddef

##############################################################################
# SECTION: inspector.vim
##############################################################################

export def Title(): string
  return IN.T("Title:")
enddef

export def Label(): string
  return IN.T("Label:")
enddef

export def Status(): string
  return IN.T("Status:")
enddef

export def Target(): string
  return IN.T("Target:")
enddef

export def Keywords(): string
  return IN.T("Keywords:")
enddef

export def Synopsis(): string
  return IN.T("Synopsis:")
enddef

export def Inspector(): string
  return IN.T("Inspector")
enddef

export def Session(): string
  return IN.T("Session:")
enddef

export def Today(): string
  return IN.T("Today:")
enddef

export def Tracker(): string
  return IN.T("Tracker:")
enddef

export def Starts(start: any): string
  return printf(IN.T("starts %s"), start)
enddef

export def Day(day: any, days: any): string
  return printf(IN.T("day %d of %d"), day, days)
enddef

export def Goals(): string
  return IN.T("Goals")
enddef

export def LinkedFrom(): string
  return IN.T("Linked from")
enddef

export def TargetWordCount(): string
  return IN.T("Target word count")
enddef

export def NoScriveOpen(): string
  return IN.T("no scrive open")
enddef

export def CurBufNot(): string
  return IN.T("current buffer is not a document in the open scrive")
enddef

##############################################################################
# SECTION: windows.vim
##############################################################################

export def WorksOnlyEdit(feature: any): string
  return printf(IN.T("%s works only in the edit window"), feature)
enddef
