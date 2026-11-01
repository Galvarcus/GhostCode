vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/binder.vim:
# the messages of the Binder and the scrive tree.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/binder.vim' as MB
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: binder.vim
##############################################################################

export def NewDocTitle(): string
  return IN.T("New document title")
enddef

export def FileToImport(): string
  return IN.T("File or folder to import")
enddef

export def AddFolder(): string
  return IN.T("Add Folder")
enddef

export def Folder(): string
  return IN.T("Folder")
enddef

export def NewFolderTitle(): string
  return IN.T("New folder title")
enddef

export def NewPartTitle(): string
  return IN.T("New Part title, or blank for the next number")
enddef

export def NewChapterTitle(): string
  return IN.T("New Chapter title, or blank for the next number")
enddef

export def NoManuscriptPart(): string
  return IN.T("no Manuscript/Part folder found to add a chapter into")
enddef

export def NoManuscriptFolder(): string
  return IN.T("no Manuscript folder found to add a part into")
enddef

export def DeleteFilesGood(title: any): string
  return printf(IN.T("Delete \"%s\" and its files for good? This cannot be undone."), title)
enddef

export def DeletedGood(title: any): string
  return printf(IN.T("deleted \"%s\" for good"), title)
enddef

export def AlreadyEmpty(title: any): string
  return printf(IN.T("\"%s\" is already empty"), title)
enddef

export def MoveAllContents(title: any): string
  return printf(IN.T("Move all contents of \"%s\" to the Trash? The folder itself will remain."), title)
enddef

export def MovedContentsTrash(title: any): string
  return printf(IN.T("moved the contents of \"%s\" to the Trash"), title)
enddef

export def MovedTrash(title: any): string
  return printf(IN.T("moved \"%s\" to the Trash"), title)
enddef

export def RemovedWhichHad(title: any): string
  return printf(IN.T("removed \"%s\", which had no files on disk"), title)
enddef

export def RestoresItemTrash(): string
  return IN.T("u restores an item from the Trash")
enddef

export def RestoreFolderHolds(): string
  return IN.T("restore the folder that holds this item, or move it out with m")
enddef

export def Restored(title: any): string
  return printf(IN.T("restored \"%s\""), title)
enddef

export def FolderGoneChoose(title: any): string
  return printf(IN.T("the folder of \"%s\" is gone. Choose where to restore it"), title)
enddef

export def TrashEmpty(): string
  return IN.T("the Trash is empty")
enddef

export def DeleteItemTrash(count: number): string
  return printf(IN.N("Delete the %d item in the Trash and its files for good? This cannot be undone.", "Delete the %d items in the Trash and their files for good? This cannot be undone.", count), count)
enddef

export def EmptiedTrash(): string
  return IN.T("emptied the Trash")
enddef

export def CouldNotDelete(files: any): string
  return printf(IN.T("could not delete: %s"), files)
enddef

export def TrashRestoresMoves(): string
  return IN.T("in the Trash, u restores, m moves out, and dd deletes for good")
enddef

export def CannotRenamed(title: any): string
  return printf(IN.T("\"%s\" cannot be renamed"), title)
enddef

export def Rename(): string
  return IN.T("Rename to")
enddef

export def ItemCannotReordered(): string
  return IN.T("this item cannot be reordered here")
enddef

export def ItemCannotMoved(): string
  return IN.T("this item cannot be moved to another folder")
enddef

export def Move(): string
  return IN.T("Move to")
enddef

export def NoValidFolder(): string
  return IN.T("no valid folder above to indent into")
enddef

export def AlreadyTopLevel(): string
  return IN.T("already at the top level, or not a valid destination for this item")
enddef

export def OpenDocToggle(): string
  return IN.T("Open document / toggle folder")
enddef

export def ToggleFolderCollapse(): string
  return IN.T("Toggle folder collapse")
enddef

export def NewDoc(): string
  return IN.T("New document")
enddef

export def NewFolderChapter(): string
  return IN.T("New folder (Chapter/Part when applicable)")
enddef

export def ImportFile(): string
  return IN.T("Import a file or folder")
enddef

export def MoveItemTrash(): string
  return IN.T("Move item to the Trash, or in the Trash delete it for good")
enddef

export def RestoreItemTrash(): string
  return IN.T("Restore item from the Trash")
enddef

export def RenameItemUnder(): string
  return IN.T("Rename item under cursor")
enddef

export def MoveItemDown(): string
  return IN.T("Move item down / up, and a scene into the next chapter")
enddef

export def MoveItemAnother(): string
  return IN.T("Move item to another folder")
enddef

export def IndentOutdentItem(): string
  return IN.T("Indent / outdent item")
enddef

export def ToggleChapterPart(): string
  return IN.T("Toggle Chapter:/Part: labels")
enddef

export def TakeSnap(): string
  return IN.T("Take snapshot")
enddef

export def ViewRestoreSnaps(): string
  return IN.T("View/restore snapshots")
enddef

export def OpenCorkboard(): string
  return IN.T("Open Corkboard")
enddef

export def OpenOutliner(): string
  return IN.T("Open Outliner")
enddef

export def SearchProj(): string
  return IN.T("Search project")
enddef

export def CloseBinder(): string
  return IN.T("Close Binder")
enddef

##############################################################################
# SECTION: binderitem.vim
##############################################################################

export def Part(): string
  return IN.T("Part: ")
enddef

export def Chapter(): string
  return IN.T("Chapter: ")
enddef

##############################################################################
# SECTION: project.vim
##############################################################################

export def Novel(): string
  return IN.T("Novel")
enddef

export def NovelParts(): string
  return IN.T("Novel with Parts")
enddef

export def ShortStory(): string
  return IN.T("Short Story")
enddef

export def ProjJsonNot(scriveDir: any): string
  return printf(IN.T("project.json not found in %s"), scriveDir)
enddef

export def HoldsNoList(path: any): string
  return printf(IN.T("%s holds no list of binder items. The scrive did not open, and nothing was changed."), path)
enddef

export def CannotReadScrive(path: any, err: any): string
  return printf(IN.T("%s cannot be read: %s. The scrive did not open, and nothing was changed."), path, err)
enddef

export def VersionBeforeLast(backup: any): string
  return printf(IN.T("The version before the last save is in %s."), backup)
enddef

export def NotSavedBecause(path: any): string
  return printf(IN.T("%s was not saved, because it did not load."), path)
enddef

export def Trash(): string
  return IN.T("Trash")
enddef

##############################################################################
# SECTION: scrive.vim
##############################################################################

export def ScriveAlreadyExists(name: any, dir: any): string
  return printf(IN.T("scrive \"%s\" already exists at %s"), name, dir)
enddef

##############################################################################
# SECTION: templates.vim
##############################################################################

export def Scene(): string
  return IN.T("Scene 1")
enddef

export def FrontMatter(): string
  return IN.T("Front Matter")
enddef

export def BackMatter(): string
  return IN.T("Back Matter")
enddef

export def Chars(): string
  return IN.T("Characters")
enddef

export def Research(): string
  return IN.T("Research")
enddef

export def Draft(): string
  return IN.T("Draft")
enddef

##############################################################################
# SECTION: links.vim
##############################################################################

export def PickLinked(title: any): string
  return printf(IN.T("Documents titled \"%s\""), title)
enddef

export def LinkInTrash(title: any): string
  return printf(IN.T("\"%s\" is in the Trash"), title)
enddef

export def NoLinked(title: any): string
  return printf(IN.T("No document is titled \"%s\""), title)
enddef

export def NoHeading(title: any, heading: any): string
  return printf(IN.T("\"%s\" has no heading \"%s\""), title, heading)
enddef

export def CreateLinked(title: any): string
  return printf(IN.T("No document is titled \"%s\". Create it next to this one?"), title)
enddef

export def UpdateLinks(count: number): string
  return printf(IN.N("Update %d link to the new title?", "Update %d links to the new title?", count), count)
enddef

export def LinksUpdated(count: number): string
  return printf(IN.N("%d link updated", "%d links updated", count), count)
enddef

##############################################################################
# SECTION: import.vim
##############################################################################

export def ImportedDoc(count: number): string
  return printf(IN.N("imported %d document", "imported %d documents", count), count)
enddef

export def SkippedFile(count: number, names: any): string
  return printf(IN.N("skipped %d file: %s", "skipped %d files: %s", count), count, names)
enddef

export def ImportDocFolder(docs: number, folders: any): string
  return printf(IN.N("Import %d document and %s?", "Import %d documents and %s?", docs), docs, folders)
enddef

export def FolderAdded(count: number): string
  return printf(IN.N("%d new folder", "%d new folders", count), count)
enddef

export def ReadAsProject(): string
  return IN.T("read the folder as a project export")
enddef

export def ExportAsText(): string
  return IN.T("export those again as Markdown, plain text, or Fountain")
enddef

# FUNCTION: The title of the Research folder that takes the notes of each
# document of a project export, which Bartleby has no field for.
export def DocNotes(): string
  return IN.T("Document Notes")
enddef

##############################################################################
# SECTION: doctemplates.vim
##############################################################################

export def DocTemplate(): string
  return IN.T("Template")
enddef

export def Blank(): string
  return IN.T("Blank")
enddef
