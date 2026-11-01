vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/common.vim:
# the messages of messages that more than one component shows.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/common.vim' as MC
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: progress.vim
##############################################################################

export def NoScriveOpen(): string
  return IN.T("no scrive open - run :BartlebyOpen <name> first")
enddef

##############################################################################
# SECTION: binder.vim
##############################################################################

export def SnapLabelOptional(): string
  return IN.T("Snapshot label (optional)")
enddef

export def NoSnaps(title: any): string
  return printf(IN.T("no snapshots for \"%s\""), title)
enddef

export def Snaps(): string
  return IN.T("Snapshots")
enddef

export def Msg(choice: any): string
  return printf(IN.T(" %s "), choice)
enddef

export def Restore(): string
  return IN.T("Restore")
enddef

export def Cancel(): string
  return IN.T("Cancel")
enddef

export def ScriveningOpensOnly(): string
  return IN.T("a Scrivening opens only for a folder in the Manuscript")
enddef

export def MissingFileDisk(path: any): string
  return printf(IN.T("missing file on disk: %s"), path)
enddef

export def Chapter(): string
  return IN.T("Chapter")
enddef

export def Part(): string
  return IN.T("Part")
enddef

export def Label(): string
  return IN.T("Label")
enddef

export def Status(): string
  return IN.T("Status")
enddef

export def SetLabel(): string
  return IN.T("Set label")
enddef

export def SetStatus(): string
  return IN.T("Set status")
enddef

export def Help(): string
  return IN.T("This help")
enddef

##############################################################################
# SECTION: scrive.vim
##############################################################################

export def NoScriveNamed(name: any, root: any): string
  return printf(IN.T("no scrive named \"%s\" under %s"), name, root)
enddef

##############################################################################
# SECTION: bartlebymenu.vim
##############################################################################

export def Close(): string
  return IN.T("Close")
enddef

export def Binder(): string
  return IN.T("Binder")
enddef

export def OpenScrivening(): string
  return IN.T("Open Scrivening")
enddef

export def View(): string
  return IN.T("View")
enddef

export def Compile(): string
  return IN.T("Compile")
enddef

##############################################################################
# SECTION: compile.vim
##############################################################################

export def Manuscript(): string
  return IN.T("Manuscript")
enddef

export def Screenplay(): string
  return IN.T("Screenplay")
enddef

##############################################################################
# SECTION: corkboard.vim
##############################################################################

export def Synopsis(): string
  return IN.T("Synopsis")
enddef

##############################################################################
# SECTION: inputpopup.vim
##############################################################################

export def Save(): string
  return IN.T("Save")
enddef

##############################################################################
# SECTION: inspector.vim
##############################################################################

export def Over(amt: any): string
  return printf(IN.T("%s over"), amt)
enddef

export def Under(amt: any): string
  return printf(IN.T("%s under"), amt)
enddef

export def Keywords(): string
  return IN.T("Keywords")
enddef

##############################################################################
# SECTION: outliner.vim
##############################################################################

export def Words(): string
  return IN.T("Words")
enddef

export def Target(): string
  return IN.T("Target")
enddef

##############################################################################
# SECTION: table.vim
##############################################################################

export def Yes(): string
  return IN.T("Yes")
enddef

export def No(): string
  return IN.T("No")
enddef
