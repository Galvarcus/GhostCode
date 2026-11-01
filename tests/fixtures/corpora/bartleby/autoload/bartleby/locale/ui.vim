vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/ui.vim:
# the messages of popups, commands, the palette, and the menu.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/ui.vim' as MI
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: bartleby.vim
##############################################################################

export def NoScriveName(): string
  return IN.T("no scrive name given, and no previously-opened scrive to fall back to - showing the scrive list")
enddef

export def ScriveType(): string
  return IN.T("Scrive Type")
enddef

export def CurBufNot(): string
  return IN.T("current buffer is not a document of the open scrive")
enddef

export def NoFileFolder(path: any): string
  return printf(IN.T("no file or folder at %s"), path)
enddef

export def NothingImported(path: any): string
  return printf(IN.T("nothing to import from %s, so no scrive was created"), path)
enddef

export def NoScriveOpen(): string
  return IN.T("no scrive open - run :BartlebyRecover <name> for a scrive that does not open")
enddef

export def EveryDocDisk(): string
  return IN.T("every document on disk is in the Binder")
enddef

export def RecoveredDocFolder(count: number): string
  return printf(IN.N("recovered %d document into the folder Recovered", "recovered %d documents into the folder Recovered", count), count)
enddef

export def OpensOpenThen(name: any): string
  return printf(IN.T("\"%s\" opens. Open it, then run :BartlebyRecover to recover its documents."), name)
enddef

export def RebuildBinderDamaged(name: any): string
  return printf(IN.T("Rebuild the Binder of \"%s\"? The damaged project.json is kept as project.json.damaged, its backup is used if it loads, and every document on disk is recovered."), name)
enddef

export def FilesAlreadyFollow(): string
  return IN.T("the files already follow the Binder")
enddef

export def MoveFileSo(count: number): string
  return printf(IN.N("Move %d file, so that the folders on disk follow the Binder?", "Move %d files, so that the folders on disk follow the Binder?", count), count)
enddef

export def MovedFile(count: number): string
  return printf(IN.N("moved %d file", "moved %d files", count), count)
enddef

export def FilesDidNot(files: any): string
  return printf(IN.T("these files did not move, so save any changes and run it again: %s"), files)
enddef

export def NoScriveningOpen(): string
  return IN.T("no Scrivening is open")
enddef

export def ScriveningStaysOpen(): string
  return IN.T("the Scrivening stays open, because it could not be saved")
enddef

##############################################################################
# SECTION: bartlebymenu.vim
##############################################################################

export def Scrive(): string
  return IN.T("Scrive")
enddef

export def List(): string
  return IN.T("List...")
enddef

export def Open(): string
  return IN.T("Open...")
enddef

export def OpenScrive(): string
  return IN.T("Open Scrive")
enddef

export def New(): string
  return IN.T("New...")
enddef

export def NewFrom(): string
  return IN.T("New from existing work...")
enddef

export def NewScrive(): string
  return IN.T("New Scrive")
enddef

export def NewScriveFrom(): string
  return IN.T("New Scrive from Existing Work")
enddef

export def Toggle(): string
  return IN.T("Toggle")
enddef

export def Search(): string
  return IN.T("Search")
enddef

export def Import(): string
  return IN.T("Import...")
enddef

export def EmptyTrash(): string
  return IN.T("Empty Trash")
enddef

export def RecoverFiles(): string
  return IN.T("Recover Files")
enddef

export def TidyFiles(): string
  return IN.T("Tidy Files")
enddef

export def CloseScrivening(): string
  return IN.T("Close Scrivening")
enddef

export def ToggleInspector(): string
  return IN.T("Toggle Inspector")
enddef

export def ToggleFocus(): string
  return IN.T("Toggle Focus")
enddef

export def WritingProgress(): string
  return IN.T("Writing Progress")
enddef

export def WritingGoals(): string
  return IN.T("Writing Goals")
enddef

export def ToggleSpotlight(): string
  return IN.T("Toggle Spotlight")
enddef

export def PickSpotlightMode(): string
  return IN.T("Pick Spotlight Mode")
enddef

export def ToggleQuill(): string
  return IN.T("Toggle Quill")
enddef

export def Doc(): string
  return IN.T("Document")
enddef

export def TakeSnap(): string
  return IN.T("Take Snapshot")
enddef

export def ViewSnaps(): string
  return IN.T("View Snapshots")
enddef

export def DefineWord(): string
  return IN.T("Define Word")
enddef

export def Thesaurus(): string
  return IN.T("Thesaurus")
enddef

export def Proj(): string
  return IN.T("Project")
enddef

export def EditProfile(): string
  return IN.T("Edit Profile")
enddef

export def EditInfo(): string
  return IN.T("Edit Info")
enddef

##############################################################################
# SECTION: buttonspopup.vim
##############################################################################

export def PopupButtonMenuBtnsList(): string
  return IN.T("PopupButtonMenu: buttons list must not be empty")
enddef

export def PopupButtonMenuOptsCb(): string
  return IN.T("PopupButtonMenu: opts.callback is required")
enddef

##############################################################################
# SECTION: commandpalette.vim
##############################################################################

export def CmdPalette(): string
  return IN.T("Command Palette")
enddef

export def ListScrives(): string
  return IN.T("List Scrives")
enddef

export def ToggleBinder(): string
  return IN.T("Toggle Binder")
enddef

export def SearchScrive(): string
  return IN.T("Search Scrive")
enddef

export def ImportFiles(): string
  return IN.T("Import Files or Folders")
enddef

export def EditProjInfo(): string
  return IN.T("Edit Project Info")
enddef

export def CloseScrive(): string
  return IN.T("Close Scrive")
enddef

##############################################################################
# SECTION: dialog_popup.vim
##############################################################################

export def Es(): string
  return IN.T("[Y]es")
enddef

export def Msg(): string
  return IN.T("[N]o")
enddef

export def Confirm(): string
  return IN.T("Confirm")
enddef

##############################################################################
# SECTION: inputpopup.vim
##############################################################################

export def Save(title: any): string
  return printf(IN.T(" %s (C-s to save) "), title)
enddef

export def Submit(): string
  return IN.T("Submit")
enddef

export def InputPopupFieldRowsProduced(): string
  return IN.T("InputPopup: fieldRows produced no fields")
enddef

export def NoMatches(): string
  return IN.T("(no matches)")
enddef

export def Input(): string
  return IN.T("Input")
enddef

##############################################################################
# SECTION: table.vim
##############################################################################

export def InsertTable(): string
  return IN.T("Insert Table")
enddef
