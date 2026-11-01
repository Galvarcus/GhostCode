vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# recover.vim: brings back documents that are on disk but not in the
# Binder. Recover adds them to a top level folder named Recovered, such as
# the files that dd removed from the Binder before the Trash existed.
#
# Rebuild is for a scrive whose project.json does not load. It sets the
# damaged file aside, takes the backup of project.json when that loads, or
# else the empty structural folders of the scrive type, and then recovers
# every document that the new Binder does not list.
#
# Only files with the document extension of the scrive count, under its
# binder folder. Hidden files and folders are left out, and so are the
# metadata files, which have another extension.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/templates.vim' as TE
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/locale/data.vim' as MD
import 'bartleby/variables/constants.vim' as CO

# The suffix that a project.json that does not load gets from Rebuild.
export const DAMAGED_SUFFIX: string = '.damaged'

# FUNCTION: Return the paths, relative to the binder folder and sorted, of
# the documents on disk that no item of the Binder lists, the Trash
# included.
export def UnlistedFiles(project: PO.Project): list<string>
  var root: string = project.BinderRoot()
  # Keyed by the one spelling of each path, because Rel answers with the
  # case that a name has on disk while a scrive stores the case it wrote,
  # and on a file system that folds case those two name one file.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/52
  var listed: dict<bool> = {}
  for row in T.Flatten(project)
    if row.item.IsDoc()
      listed[PA.Canon($'{root}/{row.item.relPath}')] = true
    endif
  endfor
  var found: list<string> = []
  for path in globpath(root, '**/*' .. project.DocExt(), true, true)
    var relPath: string = PA.Rel(root, path)
    # Names that start with a dot are hidden. globpath leaves them out on
    # Unix, but not on every system, so they are skipped here as well. An
    # empty answer means globpath gave a path outside the root, which is
    # nothing of this scrive.
    if relPath ==# '' || relPath =~# '\(^\|/\)\.'
        || has_key(listed, PA.Canon(path)) || !filereadable(path)
      continue
    endif
    found->add(relPath)
  endfor
  return sort(found)
enddef

# FUNCTION: Add the unlisted documents to the folder Recovered at the top
# level, made when it is missing. Each is titled with its path, without the
# extension, so that files of the same name in two folders differ. Returns
# how many it added.
export def Recover(project: PO.Project): number
  var files: list<string> = UnlistedFiles(project)
  if empty(files)
    return 0
  endif
  var folder: BI.BinderItem = RecoveredFolder(project)
  for relPath in files
    folder.AddChild(BI.BinderItem.NewDocument(fnamemodify(relPath, ':r'), relPath))
  endfor
  return len(files)
enddef

# FUNCTION: Return the folder Recovered at the top level, made, before the
# Trash, when there is none.
def RecoveredFolder(project: PO.Project): BI.BinderItem
  var title: string = MD.Recovered()
  for item in project.items
    if item.IsFolder() && item.structureRole ==# CO.ROLE_CUSTOM && item.title ==# title
      return item
    endif
  endfor
  var folder: BI.BinderItem = BI.BinderItem.NewFolder(title, CO.ROLE_CUSTOM)
  project.AddChild(folder)
  return folder
enddef

# FUNCTION: Give the scrive in scriveDir, whose project.json does not load,
# a new Binder, recover its documents into it, and save it. The damaged
# project.json is kept, with DAMAGED_SUFFIX. Returns the project, or
# null_object when the damaged file cannot be set aside.
export def Rebuild(scriveDir: string): PO.Project
  var project: PO.Project = PO.Project.new(scriveDir)
  var path: string = project.ProjFilePath()
  var backup: string = path .. PE.BACKUP_SUFFIX
  if filereadable(path) && rename(path, path .. DAMAGED_SUFFIX) != 0
    return null_object
  endif
  # The backup brings back the titles and the order, when it loads.
  var restored: bool = false
  if filereadable(backup)
    writefile(readfile(backup, 'b'), path, 'b')
    restored = project.Load()
    if !restored
      delete(path)
    endif
  endif
  if !restored
    var root: string = project.BinderRoot()
    var projectType: string = empty(globpath(root, '**/*.fountain', true, true))
      ? CO.TYPE_NOVEL : CO.TYPE_SCREENPLAY
    project.InitNew(fnamemodify(scriveDir, ':t:r'), projectType)
    # The structural folders only. Their starter documents may not exist.
    var folders: list<BI.BinderItem> = TE.DefaultTree(projectType, project.DocExt())
    for folder in folders
      folder.SetChildren([])
    endfor
    project.SeedTree(folders)
  endif
  Recover(project)
  project.Save()
  return project
enddef
