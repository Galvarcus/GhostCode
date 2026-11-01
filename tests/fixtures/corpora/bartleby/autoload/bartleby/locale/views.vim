vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/views.vim:
# the messages of the Corkboard, the Outliner, and lists.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/views.vim' as MV
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: corkboard.vim
##############################################################################

export def AlreadyEndFolder(): string
  return IN.T("already at that end of the folder")
enddef

export def Corkboard(): string
  return IN.T("Corkboard")
enddef

export def Arrows(): string
  return IN.T("Arrows")
enddef

export def MoveBetweenCards(): string
  return IN.T("Move between cards")
enddef

export def OpenSelDoc(): string
  return IN.T("Open the selected document")
enddef

export def EditSynopsis(): string
  return IN.T("Edit the synopsis")
enddef

export def MoveCardLater(): string
  return IN.T("Move the card later / earlier")
enddef

export def HasNoDocs(title: any): string
  return printf(IN.T("\"%s\" has no documents to show on the corkboard"), title)
enddef

##############################################################################
# SECTION: helppopup.vim
##############################################################################

export def Help(): string
  return IN.T("Help")
enddef

export def PressEscClose(): string
  return IN.T("Press Esc to close")
enddef

##############################################################################
# SECTION: outliner.vim
##############################################################################

export def TreeOrder(): string
  return IN.T("Tree Order")
enddef

export def Title(): string
  return IN.T("Title")
enddef

export def Outliner(title: any): string
  return printf(IN.T(" Outliner: %s "), title)
enddef

export def SortBy(): string
  return IN.T("Sort by")
enddef

export def Outliner2(): string
  return IN.T("Outliner")
enddef

export def OpenDocUnder(): string
  return IN.T("Open document under cursor")
enddef

export def Sort(): string
  return IN.T("Sort")
enddef

export def CloseOutliner(): string
  return IN.T("Close Outliner")
enddef

export def Empty(): string
  return IN.T("(empty)")
enddef

##############################################################################
# SECTION: scrivelist.vim
##############################################################################

export def SkippedFolderUnder(count: number, root: any): string
  return printf(IN.N("skipped %d folder under %s with no valid project.json", "skipped %d folders under %s with no valid project.json", count), count, root)
enddef

export def NoScrivesFound(root: any): string
  return printf(IN.T("no scrives found under %s - name a new one to create it"), root)
enddef

export def NoScrivesCreate(): string
  return IN.T("No scrives - create one")
enddef

export def Scrives(): string
  return IN.T("Scrives")
enddef

export def OpenSelScrive(): string
  return IN.T("Open the selected scrive")
enddef

export def NextScrive(): string
  return IN.T("Next scrive")
enddef

export def PrevScrive(): string
  return IN.T("Previous scrive")
enddef

export def Type(): string
  return IN.T("Type")
enddef

##############################################################################
# SECTION: search.vim
##############################################################################

export def SearchScrive(): string
  return IN.T("Search scrive")
enddef

export def NoDocsSearch(): string
  return IN.T("no documents to search")
enddef

export def NoMatches(query: any): string
  return printf(IN.T("no matches for \"%s\""), query)
enddef
