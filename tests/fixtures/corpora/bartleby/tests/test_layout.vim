vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_layout.vim: the disk layout of layout.vim, with real files. A
# document lives in the folders of its place in the Binder, as in
# manuscript/part-1/chapter-2/arrival.md, for new scrives, new documents,
# and tidied files. Tidy moves files and their metadata, never writes over
# a file, lets two documents trade paths, moves nothing twice, stops for
# unsaved changes, and opens a moved document again at its new path.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/templates.vim' as TE
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the documents inside items, at any depth.
def Documents(items: list<any>): list<any>
  var found: list<any> = []
  for item in items
    found += item.IsDoc() ? [item] : Documents(item.children)
  endfor
  return found
enddef

# FUNCTION: Return the lines of path, or an empty list when it is missing,
# so that a missing file fails its assertion instead of stopping the tests.
def LinesOf(path: string): list<string>
  return filereadable(path) ? readfile(path) : []
enddef

# FUNCTION: Run Tidy, and report an error it throws instead of stopping
# the tests. Returns what Tidy returns, or the error.
def TidyAll(project: any): list<string>
  try
    return LY.Tidy(project, LY.Plan(project))
  catch
    assert_report('Tidy threw: ' .. v:exception)
    return [v:exception]
  endtry
enddef

# FUNCTION: Return the fixture project, saved, with its two scenes on disk
# at the old paths that the fixture gives them, chapter-1/scene-01.md and
# chapter-2/scene-01.md, each with its own text.
def OldLayoutProject(): dict<any>
  var project = FI.BuildProject()
  var scene1 = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(project, scene1, ['The first scene.'])
  FI.WriteDocContent(project, scene2, ['The second scene.'])
  project.Save()
  return {project: project, root: project.BinderRoot(), scene1: scene1, scene2: scene2}
enddef

# A role folder takes its role, not its title, because the titles come
# from the locale and the layout must read the same in every language.
def Test_a_role_folder_takes_its_role(): void
  assert_equal('front-matter',
    LY.FolderSlug(BI.BinderItem.NewFolder('Vorspann', CO.ROLE_FRONT_MATTER)))
  assert_equal('manuscript',
    LY.FolderSlug(BI.BinderItem.NewFolder('原稿', CO.ROLE_MANUSCRIPT)))
  assert_equal('characters',
    LY.FolderSlug(BI.BinderItem.NewFolder('Personen', CO.ROLE_CHARS)))
  assert_equal('research',
    LY.FolderSlug(BI.BinderItem.NewFolder('Recherche', CO.ROLE_RESEARCH)))
  assert_equal('back-matter',
    LY.FolderSlug(BI.BinderItem.NewFolder('Nachspann', CO.ROLE_BACK_MATTER)))
  assert_equal('trash',
    LY.FolderSlug(BI.BinderItem.NewFolder('Papierkorb', CO.ROLE_TRASH)))
enddef

def Test_a_folder_the_writer_named_takes_its_title(): void
  assert_equal('chapter-1', LY.FolderSlug(BI.BinderItem.NewFolder('1', CO.ROLE_CHAPTER)))
  assert_equal('part-2', LY.FolderSlug(BI.BinderItem.NewFolder('2', CO.ROLE_PART)))
  assert_equal('chapter-序章',
    LY.FolderSlug(BI.BinderItem.NewFolder('序章', CO.ROLE_CHAPTER)))
  assert_equal('Über', LY.FolderSlug(BI.BinderItem.NewFolder('Über', CO.ROLE_NONE)))
  assert_equal('untitled', LY.FolderSlug(BI.BinderItem.NewFolder('???', CO.ROLE_NONE)))
enddef

def Test_a_document_takes_the_title_the_writer_typed(): void
  var fx = OldLayoutProject()
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var scene = BI.BinderItem.NewDocument('Die Über-Szene', '')
  chapter2.AddChild(scene)
  LY.Place(fx.project, scene)
  assert_equal('manuscript/chapter-2/Die-Über-Szene.md', scene.relPath)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_new_scrives_use_the_full_binder_path(): void
  var novel = Documents(TE.DefaultTree(CO.TYPE_NOVEL, '.md'))->mapnew((_, d) => d.relPath)
  assert_equal(['manuscript/chapter-1/Scene-1.md'], novel)
  var parts = Documents(TE.DefaultTree(CO.TYPE_NOVEL_PARTS, '.md'))->mapnew((_, d) => d.relPath)
  assert_equal(['manuscript/part-1/chapter-1/Scene-1.md'], parts)
  var story = Documents(TE.DefaultTree(CO.TYPE_SHORT_STORY, '.md'))->mapnew((_, d) => d.relPath)
  assert_equal(['manuscript/Draft.md'], story)
  var play = Documents(TE.DefaultTree(CO.TYPE_SCREENPLAY, '.fountain'))->mapnew((_, d) => d.relPath)
  assert_equal(['manuscript/Scene-1.fountain'], play)
enddef

def Test_a_new_document_takes_the_path_of_its_place(): void
  var fx = OldLayoutProject()
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var arrival = BI.BinderItem.NewDocument('Arrival', '')
  chapter2.AddChild(arrival)
  LY.Place(fx.project, arrival)
  assert_equal('manuscript/chapter-2/Arrival.md', arrival.relPath)
  # A path taken on disk, or by a document of the tree, gets -2 and so on.
  mkdir(fx.root .. '/manuscript/chapter-2', 'p')
  writefile(['Someone else.'], fx.root .. '/manuscript/chapter-2/Departure.md')
  var departure = BI.BinderItem.NewDocument('Departure', '')
  chapter2.AddChild(departure)
  LY.Place(fx.project, departure)
  assert_equal('manuscript/chapter-2/Departure-2.md', departure.relPath)
  var again = BI.BinderItem.NewDocument('Arrival', '')
  chapter2.AddChild(again)
  LY.Place(fx.project, again)
  assert_equal('manuscript/chapter-2/Arrival-2.md', again.relPath)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_tidy_moves_the_files_and_their_metadata(): void
  var fx = OldLayoutProject()
  var meta = fx.scene1.LoadMeta(fx.root)
  meta.SetSynopsis('The synopsis goes along.')
  meta.Save(fx.scene1.MetaPath(fx.root))
  var moves = LY.Plan(fx.project)
  assert_equal([['chapter-1/scene-01.md', 'manuscript/chapter-1/Scene-1.md'],
    ['chapter-2/scene-01.md', 'manuscript/chapter-2/Scene-1.md']],
    moves->mapnew((_, m) => [m.from, m.to]))
  assert_equal([], LY.Tidy(fx.project, moves))
  assert_equal(['The first scene.'], LinesOf(fx.root .. '/manuscript/chapter-1/Scene-1.md'))
  assert_equal('The synopsis goes along.', fx.scene1.LoadMeta(fx.root).synopsis)
  # The old folders are gone, and project.json names the new paths.
  assert_false(isdirectory(fx.root .. '/chapter-1'))
  var loaded = PO.Project.new(fx.project.scriveDir)
  loaded.Load()
  assert_equal('manuscript/chapter-1/Scene-1.md', loaded.ChildAt(1).ChildAt(0).ChildAt(0).relPath)
  # Tidy again: nothing moves.
  assert_equal([], LY.Plan(fx.project))
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_two_documents_trade_paths_and_keep_their_texts(): void
  var fx = OldLayoutProject()
  assert_equal([], TidyAll(fx.project))
  # Trade the two chapters' scenes in the Binder.
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  chapter1.SetChildren([fx.scene2])
  chapter2.SetChildren([fx.scene1])
  var moves = LY.Plan(fx.project)
  assert_equal(2, len(moves))
  assert_equal([], LY.Tidy(fx.project, moves))
  assert_equal(['The second scene.'], LinesOf(fx.root .. '/manuscript/chapter-1/Scene-1.md'))
  assert_equal(['The first scene.'], LinesOf(fx.root .. '/manuscript/chapter-2/Scene-1.md'))
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_a_file_that_no_document_names_is_never_written_over(): void
  var fx = OldLayoutProject()
  mkdir(fx.root .. '/manuscript/chapter-1', 'p')
  writefile(['Not in the Binder.'], fx.root .. '/manuscript/chapter-1/Scene-1.md')
  assert_equal([], TidyAll(fx.project))
  assert_equal(['Not in the Binder.'], LinesOf(fx.root .. '/manuscript/chapter-1/Scene-1.md'))
  assert_equal('manuscript/chapter-1/Scene-1-2.md', fx.scene1.relPath)
  assert_equal(['The first scene.'], LinesOf(fx.root .. '/manuscript/chapter-1/Scene-1-2.md'))
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_the_trash_stays_as_it_is(): void
  var fx = OldLayoutProject()
  TR.MoveToTrash(fx.project, T.FindRowById(T.Flatten(fx.project), fx.scene2.id))
  var moves = LY.Plan(fx.project)
  assert_equal([fx.scene1.id], moves->mapnew((_, m) => m.item.id))
  LY.Tidy(fx.project, moves)
  assert_equal('chapter-2/scene-01.md', fx.scene2.relPath)
  assert_true(filereadable(fx.root .. '/chapter-2/scene-01.md'))
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_unsaved_changes_stop_the_tidy_before_any_move(): void
  var fx = OldLayoutProject()
  execute 'silent edit ' .. fnameescape(fx.scene1.AbsPath(fx.root))
  setline(1, 'Changed, not saved.')
  var failed = TidyAll(fx.project)
  assert_equal(1, len(failed))
  assert_equal('chapter-1/scene-01.md', fx.scene1.relPath)
  assert_equal('chapter-2/scene-01.md', fx.scene2.relPath)
  bwipe!
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: The document shows in a window beside another, as beside the
# Binder: its window stays, and shows the document at its new path.
def Test_an_open_document_opens_again_at_its_new_path(): void
  var fx = OldLayoutProject()
  writefile(['Line one.', 'Line two.', 'Line three.'], fx.scene1.AbsPath(fx.root))
  execute 'silent edit ' .. fnameescape(fx.scene1.AbsPath(fx.root))
  cursor(3, 6)
  var editor: number = win_getid()
  vnew
  var windows: number = winnr('$')
  assert_equal([], TidyAll(fx.project))
  assert_equal(windows, winnr('$'), 'a window closed')
  assert_true(win_gotoid(editor), 'the window of the document closed')
  assert_equal(PA.Canon(fx.root .. '/manuscript/chapter-1/Scene-1.md'), PA.Canon(expand('%:p')))
  assert_equal([3, 6], [line('.'), col('.')])
  silent! only
  silent! :%bwipe!
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: Return the paths that a tidy of project would move the
# document with id to. The fixture gives its scenes the paths of an older
# layout, so a plan of it always holds their moves too.
def MovesFor(project: any, id: string): list<string>
  return LY.Plan(project)
    ->filter((_, m) => m.item.id ==# id)
    ->mapnew((_, m) => m.to)
enddef

# Two titles that differ only in case are one file on Windows and on a
# default macOS volume, so the second must not take the name of the
# first, whatever this file system would allow.
def Test_two_titles_that_differ_only_in_case_take_two_paths(): void
  var fx = OldLayoutProject()
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var upper = BI.BinderItem.NewDocument('Über', '')
  chapter2.AddChild(upper)
  LY.Place(fx.project, upper)
  var lower = BI.BinderItem.NewDocument('über', '')
  chapter2.AddChild(lower)
  LY.Place(fx.project, lower)
  assert_equal('manuscript/chapter-2/Über.md', upper.relPath)
  assert_equal('manuscript/chapter-2/über-2.md', lower.relPath)
  FI.CleanupProjectFiles(fx.project)
enddef

# A title longer than the cap of a name truncates, so two titles can
# arrive at one name by truncation alone.
def Test_two_long_titles_that_truncate_alike_take_two_paths(): void
  var fx = OldLayoutProject()
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var first = BI.BinderItem.NewDocument(repeat('日', 90) .. 'A', '')
  var second = BI.BinderItem.NewDocument(repeat('日', 90) .. 'B', '')
  chapter2.AddChild(first)
  chapter2.AddChild(second)
  LY.Place(fx.project, first)
  LY.Place(fx.project, second)
  assert_notequal(first.relPath, second.relPath)
  assert_true(second.relPath =~# '-2\.md$', $'{second.relPath} has no suffix')
  FI.CleanupProjectFiles(fx.project)
enddef

# A path that differs from the layout only in case is already following
# it, so a tidy of a project written on another system moves nothing.
def Test_tidy_plans_no_move_for_a_difference_of_case(): void
  var fx = OldLayoutProject()
  var scene = fx.project.ChildAt(1).ChildAt(0).ChildAt(0)
  var want = MovesFor(fx.project, scene.id)[0]
  scene.SetRelPath(toupper(want))
  assert_equal([], MovesFor(fx.project, scene.id))
  FI.CleanupProjectFiles(fx.project)
enddef

# A file at the name the layout wants, that no document names, is still
# never written over: the document moves beside it instead. An existing
# project meets this as soon as a title gains its own letters back.
def Test_tidy_spares_a_stranger_at_the_name_it_wants(): void
  var fx = OldLayoutProject()
  var scene = fx.project.ChildAt(1).ChildAt(0).ChildAt(0)
  var want = MovesFor(fx.project, scene.id)[0]
  mkdir(fnamemodify($'{fx.root}/{want}', ':h'), 'p')
  writefile(['Someone else.'], $'{fx.root}/{want}')
  assert_equal([substitute(want, '\.md$', '-2.md', '')],
    MovesFor(fx.project, scene.id))
  assert_equal(['Someone else.'], LinesOf($'{fx.root}/{want}'))
  FI.CleanupProjectFiles(fx.project)
enddef

export def RunAll(): void
  Test_a_role_folder_takes_its_role()
  Test_a_folder_the_writer_named_takes_its_title()
  Test_a_document_takes_the_title_the_writer_typed()
  Test_two_titles_that_differ_only_in_case_take_two_paths()
  Test_two_long_titles_that_truncate_alike_take_two_paths()
  Test_tidy_plans_no_move_for_a_difference_of_case()
  Test_tidy_spares_a_stranger_at_the_name_it_wants()
  Test_new_scrives_use_the_full_binder_path()
  Test_a_new_document_takes_the_path_of_its_place()
  Test_tidy_moves_the_files_and_their_metadata()
  Test_two_documents_trade_paths_and_keep_their_texts()
  Test_a_file_that_no_document_names_is_never_written_over()
  Test_the_trash_stays_as_it_is()
  Test_unsaved_changes_stop_the_tidy_before_any_move()
  Test_an_open_document_opens_again_at_its_new_path()
enddef
