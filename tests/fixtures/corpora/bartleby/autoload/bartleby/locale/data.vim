vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/data.vim:
# the messages of data on disk.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/data.vim' as MD
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: document.vim
##############################################################################

export def None(): string
  return IN.T("None")
enddef

export def Red(): string
  return IN.T("Red")
enddef

export def Orange(): string
  return IN.T("Orange")
enddef

export def Yellow(): string
  return IN.T("Yellow")
enddef

export def Green(): string
  return IN.T("Green")
enddef

export def Blue(): string
  return IN.T("Blue")
enddef

export def Purple(): string
  return IN.T("Purple")
enddef

export def Do(): string
  return IN.T("To Do")
enddef

export def WorkingDraft(): string
  return IN.T("Working Draft")
enddef

export def FirstDraft(): string
  return IN.T("First Draft")
enddef

export def Revised(): string
  return IN.T("Revised")
enddef

export def FinalDraft(): string
  return IN.T("Final Draft")
enddef

export def Done(): string
  return IN.T("Done")
enddef

##############################################################################
# SECTION: persist.vim
##############################################################################

export def NoSuchFile(path: any): string
  return printf(IN.T("no such file: %s"), path)
enddef

export def CouldNotWritten(path: any, detail: any): string
  return printf(IN.T("%s could not be written, so it was not changed: %s"), path, detail)
enddef

##############################################################################
# SECTION: profile.vim
##############################################################################

export def Prefix(): string
  return IN.T("Prefix")
enddef

export def First(): string
  return IN.T("First")
enddef

export def Middle(): string
  return IN.T("Middle")
enddef

export def Surname(): string
  return IN.T("Surname")
enddef

export def Suffix(): string
  return IN.T("Suffix")
enddef

export def AuthorName(): string
  return IN.T("Author Name")
enddef

export def Addr(): string
  return IN.T("Address")
enddef

export def City(): string
  return IN.T("City")
enddef

export def State(): string
  return IN.T("State")
enddef

export def Country(): string
  return IN.T("Country")
enddef

export def Zip(): string
  return IN.T("Zip")
enddef

export def PhoneNum(): string
  return IN.T("Phone Number")
enddef

export def Email(): string
  return IN.T("Email")
enddef

export def NameRequired(): string
  return IN.T("Name is required")
enddef

export def Profile(PLUGIN_NAME: any): string
  return printf(IN.T(" %s Profile "), PLUGIN_NAME)
enddef

export def Info(name: any): string
  return printf(IN.T(" %s Info "), name)
enddef

##############################################################################
# SECTION: recover.vim
##############################################################################

export def Recovered(): string
  return IN.T("Recovered")
enddef

##############################################################################
# SECTION: restore.vim
##############################################################################

export def SessionPreviouslyActive(path: any): string
  return printf(IN.T("session: previously active document no longer exists: %s"), path)
enddef

##############################################################################
# SECTION: snapshot.vim
##############################################################################

export def SnapTaken(title: any, suffix: any): string
  return printf(IN.T("snapshot taken: %s%s"), title, suffix)
enddef

export def BeforeRestore(): string
  return IN.T("before restore")
enddef

export def RestoredSnap(title: any, snap: any): string
  return printf(IN.T("restored \"%s\" to snapshot from %s"), title, snap)
enddef
