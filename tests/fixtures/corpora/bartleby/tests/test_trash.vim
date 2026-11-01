vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_trash.vim: the Trash of trash.vim and project.vim, with real
# files on disk. dd moves an item into the Trash and remembers its place,
# Restore puts it back, DeleteForever and EmptyTrash delete its files and
# nothing else, Prune drops what was deleted outside Bartleby, and the
# Trash stays the last folder and takes items only through dd. Search
# leaves the Trash out.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/search.vim' as SE
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the fixture project, with the files of its two scenes on
# disk.
def ProjectOnDisk(): any
  var project = FI.BuildProject()
  for chapter in [project.ChildAt(1).ChildAt(0), project.ChildAt(1).ChildAt(1)]
    FI.WriteDocContent(project, chapter.ChildAt(0), ['Text of chapter ' .. chapter.title])
  endfor
  return project
enddef

def RowOf(project: any, id: string): any
  return T.FindRowById(T.Flatten(project), id)
enddef

def TrashIds(project: any): list<string>
  return project.TrashFolder().children->mapnew((_, item) => item.id)
enddef

def LastRole(project: any): string
  return project.ChildAt(project.ChildCount() - 1).structureRole
enddef

def Test_every_project_ends_with_the_trash(): void
  var project = FI.BuildProject()
  assert_equal(CO.ROLE_TRASH, LastRole(project))
  # What is added at the top level goes before it.
  project.AddChild(BI.BinderItem.NewDocument('Late', 'late.md'))
  project.InsertChildAt(project.ChildCount(), BI.BinderItem.NewFolder('Notes', CO.ROLE_CUSTOM))
  assert_equal(CO.ROLE_TRASH, LastRole(project))
enddef

def Test_a_scrive_saved_before_the_trash_gets_one_on_load(): void
  var project = FI.BuildProject()
  var path: string = project.ProjFilePath()
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile([json_encode({name: 'Old', projectType: CO.TYPE_NOVEL, items: [
    {id: 'm1', title: 'Manuscript', kind: CO.KIND_FOLDER, structureRole: CO.ROLE_MANUSCRIPT, children: []}]})], path)
  var loaded = PO.Project.new(project.scriveDir)
  assert_true(loaded.Load())
  assert_equal(2, loaded.ChildCount())
  assert_equal(CO.ROLE_TRASH, LastRole(loaded))
  FI.CleanupProjectFiles(project)
enddef

def Test_dd_moves_an_item_to_the_top_of_the_trash_and_remembers_its_place(): void
  var project = ProjectOnDisk()
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene = chapter2.ChildAt(0)
  TR.MoveToTrash(project, RowOf(project, scene.id))
  assert_equal(0, chapter2.ChildCount())
  assert_equal([scene.id], TrashIds(project))
  assert_equal([chapter2.id, 0], [scene.trashOrigin, scene.trashIndex])
  # The place survives a save and a load.
  project.Save()
  var loaded = PO.Project.new(project.scriveDir)
  loaded.Load()
  var again = loaded.TrashFolder().ChildAt(0)
  assert_equal([scene.id, chapter2.id, 0], [again.id, again.trashOrigin, again.trashIndex])
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: The item removed last is first in the Trash.
def Test_the_latest_removal_is_first(): void
  var project = ProjectOnDisk()
  var scene1 = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  TR.MoveToTrash(project, RowOf(project, scene1.id))
  TR.MoveToTrash(project, RowOf(project, scene2.id))
  assert_equal([scene2.id, scene1.id], TrashIds(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_restore_puts_an_item_back_at_its_place(): void
  var project = ProjectOnDisk()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var scene = chapter1.ChildAt(0)
  chapter1.AddChild(BI.BinderItem.NewDocument('Later', 'chapter-1/later.md'))
  TR.MoveToTrash(project, RowOf(project, scene.id))
  assert_true(TR.Restore(project, RowOf(project, scene.id)))
  assert_equal(scene.id, chapter1.ChildAt(0).id)
  assert_equal([], TrashIds(project))
  assert_equal(-1, scene.trashIndex)
  FI.CleanupProjectFiles(project)
enddef

def Test_restore_at_the_top_level_keeps_the_trash_last(): void
  var project = ProjectOnDisk()
  var notes = BI.BinderItem.NewDocument('Notes', 'notes.md')
  project.AddChild(notes)
  FI.WriteDocContent(project, notes, ['A note.'])
  var place: number = project.IdxOfChild(notes.id)
  TR.MoveToTrash(project, RowOf(project, notes.id))
  assert_true(TR.Restore(project, RowOf(project, notes.id)))
  assert_equal(place, project.IdxOfChild(notes.id))
  assert_equal(CO.ROLE_TRASH, LastRole(project))
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: When the folder of an item is gone, Restore refuses and the
# item stays. m then moves it anywhere but into the Trash, and the item
# forgets its old place.
def Test_restore_refuses_when_the_folder_is_gone(): void
  var project = ProjectOnDisk()
  var manuscript = project.ChildAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var scene = chapter1.ChildAt(0)
  TR.MoveToTrash(project, RowOf(project, scene.id))
  MU.Remove(project, RowOf(project, chapter1.id))
  assert_false(TR.Restore(project, RowOf(project, scene.id)))
  assert_equal([scene.id], TrashIds(project))
  var targets = MU.MoveTargets(project, RowOf(project, scene.id))->mapnew((_, path) => path[-1].id)
  assert_equal(-1, index(targets, project.TrashFolder().id))
  MU.MoveInto(project, RowOf(project, scene.id), manuscript.ChildAt(0))
  assert_equal([[], -1], [TrashIds(project), scene.trashIndex])
  FI.CleanupProjectFiles(project)
enddef

def Test_delete_forever_removes_the_files_and_nothing_else(): void
  var project = ProjectOnDisk()
  var root: string = project.BinderRoot()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var other = project.ChildAt(1).ChildAt(1).ChildAt(0)
  writefile(['{}'], scene.MetaPath(root))
  var snapshots: string = SN.SnapDir(project, scene)
  mkdir(snapshots, 'p')
  writefile(['{}'], snapshots .. '/1.json')
  TR.MoveToTrash(project, RowOf(project, scene.id))
  assert_equal([], TR.DeleteForever(project, RowOf(project, scene.id)))
  assert_false(filereadable(scene.AbsPath(root)))
  assert_false(filereadable(scene.MetaPath(root)))
  assert_false(isdirectory(snapshots))
  # Its directory was left empty, so it went too. The other scene stays.
  assert_false(isdirectory(fnamemodify(scene.AbsPath(root), ':h')))
  assert_true(filereadable(other.AbsPath(root)))
  assert_equal([], TrashIds(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_delete_forever_never_leaves_the_scrive(): void
  var project = ProjectOnDisk()
  var outside: string = project.BinderRoot() .. '/../outside.md'
  writefile(['keep'], outside)
  var bad = BI.BinderItem.NewDocument('Bad', '../outside.md')
  project.TrashFolder().AddChild(bad)
  assert_equal(['../outside.md'], TR.DeleteForever(project, RowOf(project, bad.id)))
  assert_true(filereadable(outside))
  FI.CleanupProjectFiles(project)
enddef

def Test_empty_trash_deletes_everything_in_it(): void
  var project = ProjectOnDisk()
  var root: string = project.BinderRoot()
  var scenes = [project.ChildAt(1).ChildAt(0).ChildAt(0), project.ChildAt(1).ChildAt(1).ChildAt(0)]
  for scene in scenes
    TR.MoveToTrash(project, RowOf(project, scene.id))
  endfor
  assert_equal([], TR.EmptyTrash(project))
  assert_equal([], TrashIds(project))
  for scene in scenes
    assert_false(filereadable(scene.AbsPath(root)), scene.relPath)
  endfor
  FI.CleanupProjectFiles(project)
enddef

def Test_prune_drops_what_was_deleted_outside_bartleby(): void
  var project = ProjectOnDisk()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  TR.MoveToTrash(project, RowOf(project, chapter1.id))
  TR.MoveToTrash(project, RowOf(project, scene2.id))
  delete(scene2.AbsPath(project.BinderRoot()))
  assert_true(TR.Prune(project))
  assert_equal([chapter1.id], TrashIds(project))
  assert_false(TR.Prune(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_only_items_with_files_on_disk_count(): void
  var project = ProjectOnDisk()
  var empty = BI.BinderItem.NewFolder('3', CO.ROLE_CHAPTER)
  project.ChildAt(1).AddChild(empty)
  assert_false(TR.HasFilesOnDisk(project, empty))
  assert_true(TR.HasFilesOnDisk(project, project.ChildAt(1).ChildAt(0)))
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: dd on a structural folder moves its contents, in order, and
# each remembers its place.
def Test_move_all_to_trash_keeps_the_order_and_the_places(): void
  var project = ProjectOnDisk()
  var manuscript = project.ChildAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  TR.MoveAllToTrash(project, manuscript)
  assert_equal(0, manuscript.ChildCount())
  assert_equal([chapter1.id, chapter2.id], TrashIds(project))
  assert_equal([manuscript.id, 0, manuscript.id, 1],
    [chapter1.trashOrigin, chapter1.trashIndex, chapter2.trashOrigin, chapter2.trashIndex])
  FI.CleanupProjectFiles(project)
enddef

def Test_the_trash_takes_items_only_through_dd(): void
  var project = ProjectOnDisk()
  var trash = project.TrashFolder()
  assert_true(MU.IsImmutableFolder(trash))
  var notes = BI.BinderItem.NewDocument('Notes', 'notes.md')
  project.AddChild(notes)
  # J on the item just before the Trash does not swap them.
  assert_false(MU.MoveWithinSiblings(project, RowOf(project, notes.id), 1))
  assert_equal(CO.ROLE_TRASH, LastRole(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_search_skips_the_trash(): void
  var project = ProjectOnDisk()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var path: string = scene.AbsPath(project.BinderRoot())
  assert_true(index(SE.SearchFiles(project), path) >= 0)
  TR.MoveToTrash(project, RowOf(project, scene.id))
  assert_equal(-1, index(SE.SearchFiles(project), path))
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: A compile target keeps the ids it included. A scene moved to
# the Trash must still be left out. Manuscript and Book read only the
# folders that compile, and ConcatenateDocs, which a Screenplay and the
# other kinds use, must leave out the Trash as well.
def Test_compile_leaves_out_what_is_in_the_trash(): void
  var project = ProjectOnDisk()
  var scene1 = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'T', kind: 'Screenplay', format: 'PDF',
    includedIds: [scene1.id, scene2.id]})
  assert_match('Text of chapter 1', join(C.ConcatenateDocs(project, target, ''), "\n"))
  TR.MoveToTrash(project, RowOf(project, scene1.id))
  var after: string = join(C.ConcatenateDocs(project, target, ''), "\n")
  assert_notmatch('Text of chapter 1', after)
  assert_match('Text of chapter 2', after)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_row_knows_whether_it_is_in_the_trash(): void
  var project = ProjectOnDisk()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  TR.MoveToTrash(project, RowOf(project, chapter1.id))
  var rows = T.Flatten(project)
  assert_true(TR.RowInTrash(T.FindRowById(rows, project.TrashFolder().id)))
  assert_true(TR.RowInTrash(T.FindRowById(rows, chapter1.ChildAt(0).id)))
  assert_false(TR.RowInTrash(T.FindRowById(rows, project.ChildAt(1).ChildAt(0).id)))
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_every_project_ends_with_the_trash()
  Test_a_scrive_saved_before_the_trash_gets_one_on_load()
  Test_dd_moves_an_item_to_the_top_of_the_trash_and_remembers_its_place()
  Test_the_latest_removal_is_first()
  Test_restore_puts_an_item_back_at_its_place()
  Test_restore_at_the_top_level_keeps_the_trash_last()
  Test_restore_refuses_when_the_folder_is_gone()
  Test_delete_forever_removes_the_files_and_nothing_else()
  Test_delete_forever_never_leaves_the_scrive()
  Test_empty_trash_deletes_everything_in_it()
  Test_prune_drops_what_was_deleted_outside_bartleby()
  Test_only_items_with_files_on_disk_count()
  Test_move_all_to_trash_keeps_the_order_and_the_places()
  Test_the_trash_takes_items_only_through_dd()
  Test_search_skips_the_trash()
  Test_compile_leaves_out_what_is_in_the_trash()
  Test_a_row_knows_whether_it_is_in_the_trash()
enddef
