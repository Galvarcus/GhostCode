vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_mutate.vim: the tree changes and structure rules of
# mutate.vim. RoleAllowedUnder, NextRoleNumber, and AddIntoContainer are
# local to the script. RoleAllowedUnder is tested through the results of
# Indent and Outdent, which use it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

def Test_is_immutable_folder_true_for_all_5_structural_roles(): void
  assert_true(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_FRONT_MATTER)))
  assert_true(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_MANUSCRIPT)))
  assert_true(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_BACK_MATTER)))
  assert_true(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_CHARS)))
  assert_true(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_RESEARCH)))
enddef

def Test_is_immutable_folder_false_for_chapter_part_custom_and_documents(): void
  assert_false(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_CHAPTER)))
  assert_false(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_PART)))
  assert_false(MU.IsImmutableFolder(BI.BinderItem.NewFolder('x', CO.ROLE_CUSTOM)))
  assert_false(MU.IsImmutableFolder(BI.BinderItem.NewDocument('x', 'x.md')))
enddef

def Test_indent_refused_on_an_immutable_folder(): void
  # Back Matter, a protected folder, is right after Manuscript at the top
  # level. Indenting it would make it a child of Manuscript, which must be
  # refused.
  var project = FI.BuildProject()
  var rows = T.Flatten(project)
  var backMatterRow = T.FindRowById(rows, project.ChildAt(2).id)
  assert_false(MU.Indent(project, backMatterRow))
  # Confirm that nothing moved.
  assert_equal(6, project.ChildCount())
enddef

def Test_indent_allowed_for_a_chapter_into_a_preceding_chapter(): void
  # Only Part and Chapter must be under Manuscript or a Part, see
  # RoleAllowedUnder. The case worth checking is a Chapter that indents
  # into a Part, so build that tree directly.
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var part = BI.BinderItem.NewFolder('Part One', CO.ROLE_PART)
  # Take Chapter 1 out again.
  manuscript.RemoveChildAt(0)
  part.AddChild(BI.BinderItem.NewFolder('1', CO.ROLE_CHAPTER))
  manuscript.InsertChildAt(0, part)
  var rows = T.Flatten(project)
  # Chapter 2.
  var chapterRow = T.FindRowById(rows, manuscript.ChildAt(1).id)
  # Chapter 2 is after the Part, as a child of Manuscript. Indenting it
  # must succeed and make it a child of the Part.
  assert_true(MU.Indent(project, chapterRow))
  assert_equal(2, part.ChildCount())
enddef

def Test_outdent_refused_when_it_would_leave_manuscript_role_restriction(): void
  # The parent of a Chapter directly in Manuscript is at the top level: its
  # grandparent is the Project, null_object for RoleAllowedUnder. Outdenting
  # it would put it at the top level, which ROLE_CHAPTER never allows.
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  assert_false(MU.Outdent(project, rows, chapter1Row))
enddef

def Test_outdent_returns_false_for_an_already_root_level_item(): void
  var project = FI.BuildProject()
  var rows = T.Flatten(project)
  var frontMatterRow = T.FindRowById(rows, project.ChildAt(0).id)
  assert_false(MU.Outdent(project, rows, frontMatterRow))
enddef

def Test_remove_deletes_a_root_level_item(): void
  var project = FI.BuildProject()
  var rows = T.Flatten(project)
  var researchRow = T.FindRowById(rows, project.ChildAt(4).id)
  MU.Remove(project, researchRow)
  assert_equal(5, project.ChildCount())
enddef

def Test_remove_deletes_a_nested_item_from_its_owner(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  MU.Remove(project, chapter1Row)
  assert_equal(1, manuscript.ChildCount())
  assert_equal('2', manuscript.ChildAt(0).title)
enddef

def Test_clear_children_empties_a_folder_without_removing_it(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  assert_equal(2, manuscript.ChildCount())
  MU.ClearChildren(manuscript)
  assert_equal(0, manuscript.ChildCount())
  # The folder itself is not touched: still there, the same object.
  assert_equal(6, project.ChildCount())
  assert_equal(manuscript.id, project.ChildAt(1).id)
enddef

def Test_move_within_siblings_swaps_two_chapters(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  assert_true(MU.MoveWithinSiblings(project, chapter1Row, 1))
  assert_equal('2', manuscript.ChildAt(0).title)
  assert_equal('1', manuscript.ChildAt(1).title)
enddef

def Test_move_within_siblings_false_at_a_list_edge(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  # Chapter 1 is already first, so moving it up does nothing.
  assert_false(MU.MoveWithinSiblings(project, chapter1Row, -1))
enddef

def Test_move_within_siblings_refuses_non_chapter_non_part_folders(): void
  var project = FI.BuildProject()
  var rows = T.Flatten(project)
  # Back Matter is a structural folder, but neither a Chapter nor a Part.
  var backMatterRow = T.FindRowById(rows, project.ChildAt(2).id)
  assert_false(MU.MoveWithinSiblings(project, backMatterRow, 1))
enddef

def Test_find_manuscript_locates_the_manuscript_folder(): void
  var project = FI.BuildProject()
  var manuscript = MU.FindManuscript(project)
  assert_false(manuscript is null_object)
  assert_equal(CO.ROLE_MANUSCRIPT, manuscript.structureRole)
enddef

def Test_find_ancestor_with_role_finds_manuscript_from_a_scene(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var rows = T.Flatten(project)
  var sceneRow = T.FindRowById(rows, chapter1.ChildAt(0).id)
  var found = MU.FindAncestorWithRole(rows, sceneRow, CO.ROLE_MANUSCRIPT)
  assert_false(found is null_object)
  assert_equal(manuscript.id, found.id)
enddef

def Test_find_ancestor_with_role_returns_null_when_absent(): void
  var project = FI.BuildProject()
  var rows = T.Flatten(project)
  var frontMatterRow = T.FindRowById(rows, project.ChildAt(0).id)
  assert_true(MU.FindAncestorWithRole(rows, frontMatterRow, CO.ROLE_PART) is null_object)
enddef

def Test_add_chapter_creates_a_folder_with_a_starter_scene(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var chapter = MU.AddChapter(manuscript, null_object, 'New Chapter')
  assert_equal('New Chapter', chapter.title)
  assert_equal(CO.ROLE_CHAPTER, chapter.structureRole)
  assert_equal(1, chapter.ChildCount())
  assert_equal('Scene 1', chapter.ChildAt(0).title)
  # Added at the end, because row is null_object.
  assert_equal(3, manuscript.ChildCount())
enddef

def Test_add_chapter_blank_title_auto_numbers(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var chapter = MU.AddChapter(manuscript, null_object, '')
  # The 2 chapters are 1 and 2, so the next number is 3.
  assert_equal('3', chapter.title)
enddef

def Test_add_part_creates_an_empty_folder(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var part = MU.AddPart(manuscript, null_object, 'Part One')
  assert_equal('Part One', part.title)
  assert_equal(CO.ROLE_PART, part.structureRole)
  assert_equal(0, part.ChildCount())
enddef

def Test_rename_changes_the_items_title(): void
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var rows = T.Flatten(project)
  var chapter1Row = T.FindRowById(rows, manuscript.ChildAt(0).id)
  MU.Rename(chapter1Row, 'Prologue')
  assert_equal('Prologue', manuscript.ChildAt(0).title)
enddef

# FUNCTION: Return the row of the item with id, from a fresh Flatten.
def RowOf(project: any, id: string): T.Row
  return T.Flatten(project)->filter((_, r) => r.item.id ==# id)[0]
enddef

# FUNCTION: Run the same moves on two documents at the top level, owned
# by the Project, and on two in a folder, owned by that folder. Both
# owners implement ItemContainer, so the moves share one code path.
def Test_same_operations_at_top_level_and_in_a_folder(): void
  var project = FI.BuildProject()
  var research = project.ChildAt(4)
  var topA = BI.BinderItem.NewDocument('Top A', 'top-a.md')
  var topB = BI.BinderItem.NewDocument('Top B', 'top-b.md')
  project.AddChild(topA)
  project.AddChild(topB)
  var subFolder = BI.BinderItem.NewFolder('Places')
  var inA = BI.BinderItem.NewDocument('In A', 'in-a.md')
  var inB = BI.BinderItem.NewDocument('In B', 'in-b.md')
  research.AddChild(subFolder)
  research.AddChild(inA)
  research.AddChild(inB)

  for [owner, a, b] in [[project, topA, topB], [research, inA, inB]]
    var name: string = owner is project ? 'top level' : 'folder'
    # Move A down: B comes first.
    assert_true(MU.MoveWithinSiblings(project, RowOf(project, a.id), 1), name)
    assert_true(owner.IdxOfChild(b.id) < owner.IdxOfChild(a.id), name)
    # Remove B.
    var before: number = owner.ChildCount()
    MU.Remove(project, RowOf(project, b.id))
    assert_equal(before - 1, owner.ChildCount(), name)
    assert_equal(-1, owner.IdxOfChild(b.id), name)
  endfor

  # Indent: at the top level, Top A moves into Research, the folder just
  # before it. In the folder, In A moves into Places.
  assert_true(MU.Indent(project, RowOf(project, topA.id)))
  assert_true(research.IdxOfChild(topA.id) >= 0)
  assert_equal(-1, project.IdxOfChild(topA.id))
  assert_true(MU.Indent(project, RowOf(project, inA.id)))
  assert_true(subFolder.IdxOfChild(inA.id) >= 0)
  assert_equal(-1, research.IdxOfChild(inA.id))
enddef

# FUNCTION: Return the id of item, or an empty string for null_object, so
# that a failed move fails its assertion instead of stopping the tests.
def IdOf(item: any): string
  return item is null_object ? '' : item.id
enddef

# FUNCTION: Return a project whose Manuscript has two Parts with one
# chapter each, and one scene in each chapter.
def ProjectWithParts(): any
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  manuscript.SetChildren([])
  for number in ['1', '2']
    var part = BI.BinderItem.NewFolder(number, CO.ROLE_PART)
    var chapter = BI.BinderItem.NewFolder(number, CO.ROLE_CHAPTER)
    chapter.AddChild(BI.BinderItem.NewDocument('Scene ' .. number, $'chapter-{number}/scene-01.md'))
    part.AddChild(chapter)
    manuscript.AddChild(part)
  endfor
  return project
enddef

def Test_scene_at_the_end_moves_to_the_top_of_the_next_chapter(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene = chapter1.ChildAt(0)
  var target = MU.MoveAcrossFolders(project, T.FindRowById(T.Flatten(project), scene.id), 1)
  assert_equal(chapter2.id, IdOf(target))
  assert_equal(0, chapter1.ChildCount())
  assert_equal([scene.id, chapter2.ChildAt(1).id], [chapter2.ChildAt(0).id, chapter2.ChildAt(1).id])
enddef

def Test_scene_at_the_top_moves_to_the_end_of_the_previous_chapter(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene = chapter2.ChildAt(0)
  var target = MU.MoveAcrossFolders(project, T.FindRowById(T.Flatten(project), scene.id), -1)
  assert_equal(chapter1.id, IdOf(target))
  assert_equal(2, chapter1.ChildCount())
  assert_equal(scene.id, chapter1.ChildAt(1).id)
enddef

def Test_scene_moves_on_into_the_chapter_of_the_next_part(): void
  var project = ProjectWithParts()
  var manuscript = project.ChildAt(1)
  var chapterInPart1 = manuscript.ChildAt(0).ChildAt(0)
  var chapterInPart2 = manuscript.ChildAt(1).ChildAt(0)
  var scene = chapterInPart1.ChildAt(0)
  var target = MU.MoveAcrossFolders(project, T.FindRowById(T.Flatten(project), scene.id), 1)
  assert_equal(chapterInPart2.id, IdOf(target))
  assert_equal(scene.id, chapterInPart2.ChildAt(0).id)
enddef

def Test_no_move_past_the_first_or_last_chapter(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var rows = T.Flatten(project)
  assert_true(MU.MoveAcrossFolders(project, T.FindRowById(rows, chapter2.ChildAt(0).id), 1) is null_object)
  assert_true(MU.MoveAcrossFolders(project, T.FindRowById(rows, chapter1.ChildAt(0).id), -1) is null_object)
  assert_equal([1, 1], [chapter1.ChildCount(), chapter2.ChildCount()])
enddef

# FUNCTION: Only a scene crosses, and only into a folder with the role of
# its own: a scene in Characters has no other Characters folder to go to.
def Test_folders_and_scenes_outside_chapters_do_not_cross(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var characters = project.ChildAt(3)
  characters.AddChild(BI.BinderItem.NewDocument('Mara', 'characters/mara.md'))
  var rows = T.Flatten(project)
  assert_true(MU.MoveAcrossFolders(project, T.FindRowById(rows, chapter1.id), 1) is null_object)
  assert_true(MU.MoveAcrossFolders(project, T.FindRowById(rows, characters.ChildAt(0).id), 1) is null_object)
  assert_equal(1, characters.ChildCount())
enddef

# FUNCTION: Only a scene crosses. A chapter at the end of its Part stays,
# though the next Part would take it, and m moves it there instead.
def Test_a_chapter_does_not_cross_into_the_next_part(): void
  var project = ProjectWithParts()
  var manuscript = project.ChildAt(1)
  var chapter = manuscript.ChildAt(0).ChildAt(0)
  assert_true(MU.MoveAcrossFolders(project, T.FindRowById(T.Flatten(project), chapter.id), 1) is null_object)
  assert_equal([1, 1], [manuscript.ChildAt(0).ChildCount(), manuscript.ChildAt(1).ChildCount()])
enddef

def TargetIds(project: any, id: string): list<string>
  return MU.MoveTargets(project, T.FindRowById(T.Flatten(project), id))->mapnew((_, path) => path[-1].id)
enddef

def Test_move_targets_of_a_scene_leave_out_its_own_folder(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var ids = TargetIds(project, chapter1.ChildAt(0).id)
  assert_equal(-1, index(ids, chapter1.id))
  assert_true(index(ids, chapter2.id) >= 0)
  assert_true(index(ids, project.ChildAt(4).id) >= 0)
enddef

# FUNCTION: A chapter may only go into Manuscript or a Part, and never into
# itself. The path of each target runs from the top level down.
def Test_move_targets_of_a_chapter_follow_the_role_rules(): void
  var project = ProjectWithParts()
  var manuscript = project.ChildAt(1)
  var chapter = manuscript.ChildAt(0).ChildAt(0)
  var targets = MU.MoveTargets(project, T.FindRowById(T.Flatten(project), chapter.id))
  assert_equal([manuscript.id, manuscript.ChildAt(1).id], targets->mapnew((_, path) => path[-1].id))
  assert_equal([manuscript.id, manuscript.ChildAt(1).id], targets[1]->mapnew((_, f) => f.id))
enddef

def Test_a_structural_folder_has_no_move_targets(): void
  var project = FI.BuildProject()
  assert_equal([], TargetIds(project, project.ChildAt(4).id))
enddef

def Test_move_into_appends_at_the_end_of_the_folder(): void
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene = chapter1.ChildAt(0)
  MU.MoveInto(project, T.FindRowById(T.Flatten(project), scene.id), chapter2)
  assert_equal(0, chapter1.ChildCount())
  assert_equal(scene.id, chapter2.ChildAt(1).id)
enddef

export def RunAll(): void
  Test_is_immutable_folder_true_for_all_5_structural_roles()
  Test_is_immutable_folder_false_for_chapter_part_custom_and_documents()
  Test_indent_refused_on_an_immutable_folder()
  Test_indent_allowed_for_a_chapter_into_a_preceding_chapter()
  Test_outdent_refused_when_it_would_leave_manuscript_role_restriction()
  Test_outdent_returns_false_for_an_already_root_level_item()
  Test_remove_deletes_a_root_level_item()
  Test_remove_deletes_a_nested_item_from_its_owner()
  Test_clear_children_empties_a_folder_without_removing_it()
  Test_move_within_siblings_swaps_two_chapters()
  Test_move_within_siblings_false_at_a_list_edge()
  Test_move_within_siblings_refuses_non_chapter_non_part_folders()
  Test_find_manuscript_locates_the_manuscript_folder()
  Test_find_ancestor_with_role_finds_manuscript_from_a_scene()
  Test_find_ancestor_with_role_returns_null_when_absent()
  Test_add_chapter_creates_a_folder_with_a_starter_scene()
  Test_add_chapter_blank_title_auto_numbers()
  Test_add_part_creates_an_empty_folder()
  Test_rename_changes_the_items_title()
  Test_same_operations_at_top_level_and_in_a_folder()
  Test_scene_at_the_end_moves_to_the_top_of_the_next_chapter()
  Test_scene_at_the_top_moves_to_the_end_of_the_previous_chapter()
  Test_scene_moves_on_into_the_chapter_of_the_next_part()
  Test_no_move_past_the_first_or_last_chapter()
  Test_folders_and_scenes_outside_chapters_do_not_cross()
  Test_a_chapter_does_not_cross_into_the_next_part()
  Test_move_targets_of_a_scene_leave_out_its_own_folder()
  Test_move_targets_of_a_chapter_follow_the_role_rules()
  Test_a_structural_folder_has_no_move_targets()
  Test_move_into_appends_at_the_end_of_the_folder()
enddef
