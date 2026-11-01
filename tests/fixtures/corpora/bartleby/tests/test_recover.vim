vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_recover.vim: recover.vim, with real files on disk. Only the
# documents that no item lists count, the Trash included, without hidden
# files, metadata files, or other extensions. Recover adds them to the
# folder Recovered once. Rebuild gives a scrive whose project.json does not
# load a new Binder: from the backup when it loads, or else from the empty
# structural folders of its type, and recovers its documents.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/recover.vim' as RC
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Write lines to the file at relPath under the binder folder.
def WriteBinderFile(project: any, relPath: string, lines: list<string> = ['Text.']): void
  var path: string = project.BinderRoot() .. '/' .. relPath
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
enddef

# FUNCTION: Return the fixture project, with its two scenes on disk and
# files that the Binder does not list.
def ProjectWithStrays(): any
  var project = FI.BuildProject()
  for relPath in ['chapter-1/scene-01.md', 'chapter-2/scene-01.md',
      'old/lost.md', 'a-note.md', 'chapter-1/lost.meta.json', 'old/image.png',
      '.hidden.md', '.cache/inside.md']
    WriteBinderFile(project, relPath)
  endfor
  return project
enddef

def Titles(folder: any): list<string>
  return folder.children->mapnew((_, item) => item.title)
enddef

# FUNCTION: Return the lines of path, or an empty list when it is missing,
# so that a missing file fails its assertion instead of stopping the tests.
def LinesOf(path: string): list<string>
  return filereadable(path) ? readfile(path) : []
enddef

# FUNCTION: Return the title of the first scene of the first chapter, or an
# empty string when there is none.
def FirstSceneTitle(project: any): string
  var manuscript = project.ChildAt(1)
  if manuscript.ChildCount() == 0 || manuscript.ChildAt(0).ChildCount() == 0
    return ''
  endif
  return manuscript.ChildAt(0).ChildAt(0).title
enddef

def Test_only_unlisted_documents_count(): void
  var project = ProjectWithStrays()
  assert_equal(['a-note.md', 'old/lost.md'], RC.UnlistedFiles(project))
  # A document in the Trash is listed.
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  TR.MoveToTrash(project, T.FindRowById(T.Flatten(project), scene.id))
  assert_equal(['a-note.md', 'old/lost.md'], RC.UnlistedFiles(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_a_listed_document_stays_listed_when_its_file_changes_case(): void
  var project = ProjectWithStrays()
  var root: string = project.BinderRoot()
  assert_equal(0, rename($'{root}/chapter-1/scene-01.md',
    $'{root}/chapter-1/Scene-01.md'), 'the rename failed')
  if &fileignorecase
    assert_equal(['a-note.md', 'old/lost.md'], RC.UnlistedFiles(project))
  else
    # Another case names another file where Vim says nothing folds, so the
    # one the Binder lists is gone and the new name is a stray.
    assert_equal(['a-note.md', 'chapter-1/Scene-01.md', 'old/lost.md'],
      RC.UnlistedFiles(project))
  endif
  FI.CleanupProjectFiles(project)
enddef

def Test_recover_adds_them_once_to_a_folder_before_the_trash(): void
  var project = ProjectWithStrays()
  assert_equal(2, RC.Recover(project))
  var folder = project.ChildAt(project.ChildCount() - 2)
  assert_equal([CO.ROLE_CUSTOM, 'Recovered'], [folder.structureRole, folder.title])
  assert_equal(['a-note', 'old/lost'], Titles(folder))
  assert_equal(CO.ROLE_TRASH, project.ChildAt(project.ChildCount() - 1).structureRole)
  # A second run finds nothing, and a new stray joins the same folder.
  assert_equal(0, RC.Recover(project))
  WriteBinderFile(project, 'later.md')
  assert_equal(1, RC.Recover(project))
  assert_equal(['a-note', 'old/lost', 'later'], Titles(folder))
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Return a saved scrive in a new folder, its project.json then
# damaged, with the backup that its second save left, and one document
# that the backup does not list.
def DamagedScrive(): any
  var project = PO.Project.new(tempname() .. '/Damaged.bartleby')
  project.InitNew('Damaged', CO.TYPE_NOVEL)
  var fixture = FI.BuildProject()
  project.SeedTree(fixture.items)
  for relPath in ['chapter-1/scene-01.md', 'chapter-2/scene-01.md', 'added-later.md']
    WriteBinderFile(project, relPath)
  endfor
  project.Save()
  project.Save()
  writefile(['{"name": "Damaged", "ite'], project.ProjFilePath())
  return project
enddef

def Test_rebuild_takes_the_backup_and_recovers_the_rest(): void
  var damaged = DamagedScrive()
  var path: string = damaged.ProjFilePath()
  var project = RC.Rebuild(damaged.scriveDir)
  assert_true(project isnot null_object)
  assert_equal(['{"name": "Damaged", "ite'], LinesOf(path .. RC.DAMAGED_SUFFIX))
  # The titles of the backup came back, and the new document is recovered.
  var loaded = PO.Project.new(damaged.scriveDir)
  assert_true(loaded.Load())
  assert_equal('Manuscript', loaded.ChildAt(1).title)
  assert_equal('Scene 1', FirstSceneTitle(loaded))
  assert_equal(['added-later'], Titles(loaded.ChildAt(loaded.ChildCount() - 2)))
  delete(fnamemodify(damaged.scriveDir, ':h'), 'rf')
enddef

def Test_rebuild_without_a_backup_starts_from_the_structural_folders(): void
  var damaged = DamagedScrive()
  var path: string = damaged.ProjFilePath()
  delete(path .. PE.BACKUP_SUFFIX)
  var project = RC.Rebuild(damaged.scriveDir)
  assert_true(project isnot null_object)
  assert_equal(CO.TYPE_NOVEL, project.projectType)
  # Empty structural folders, then every document in Recovered.
  assert_equal(0, project.ChildAt(1).ChildCount())
  var recovered = project.ChildAt(project.ChildCount() - 2)
  assert_equal(['added-later', 'chapter-1/scene-01', 'chapter-2/scene-01'], Titles(recovered))
  assert_true(filereadable(path))
  delete(fnamemodify(damaged.scriveDir, ':h'), 'rf')
enddef

def Test_rebuild_finds_a_screenplay_by_its_files(): void
  var dir: string = tempname() .. '/Play.bartleby'
  var project = PO.Project.new(dir)
  WriteBinderFile(project, 'act-1/scene.fountain', ['INT. ROOM - DAY'])
  var rebuilt = RC.Rebuild(dir)
  assert_equal(CO.TYPE_SCREENPLAY, rebuilt.projectType)
  assert_equal(['act-1/scene'], Titles(rebuilt.ChildAt(rebuilt.ChildCount() - 2)))
  delete(fnamemodify(dir, ':h'), 'rf')
enddef

export def RunAll(): void
  Test_only_unlisted_documents_count()
  Test_a_listed_document_stays_listed_when_its_file_changes_case()
  Test_recover_adds_them_once_to_a_folder_before_the_trash()
  Test_rebuild_takes_the_backup_and_recovers_the_rest()
  Test_rebuild_without_a_backup_starts_from_the_structural_folders()
  Test_rebuild_finds_a_screenplay_by_its_files()
enddef
