vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_import.vim: import.vim, with real files on disk. An import
# copies a file into the binder folder and adds a document for it, titled
# from the file name, with the path from the layout and the document
# extension of the scrive. It accepts Markdown and plain text in every
# scrive type, and Fountain in a screenplay. It skips a file that it does
# not accept, one that it cannot read, and one that is already in the
# scrive, and counts each skip in the report.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/import.vim' as IM
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# The folder of the sources of one test, under its own temporary name, so
# that two tests cannot see each other's files.
var sources: string = ''

# FUNCTION: Write lines to name in a new sources folder, and return its
# path. The caller removes the folder with CleanupSources.
def Source(name: string, lines: list<string> = ['Text.']): string
  if sources ==# ''
    sources = tempname() .. '/sources'
    mkdir(sources, 'p')
  endif
  var path: string = $'{sources}/{name}'
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
  return path
enddef

# FUNCTION: Write lines to name in binary, for a source whose bytes a
# text write would change.
def SourceRaw(name: string, lines: list<string>): string
  var path: string = Source(name)
  writefile(lines, path, 'b')
  return path
enddef

def CleanupSources(): void
  if sources !=# ''
    delete(fnamemodify(sources, ':h'), 'rf')
    sources = ''
  endif
enddef

# FUNCTION: Return the row of the item with id in project, for the target
# of an import.
def RowOf(project: any, id: string): T.Row
  return T.FindRowById(T.Flatten(project), id)
enddef

# FUNCTION: Return a Novel fixture whose folder is its own temporary one,
# so that a test writes no file of another test.
def NovelProject(): any
  var project = FI.BuildProject()
  var moved = PO.Project.new(tempname() .. '/Novel.bartleby')
  moved.InitNew('Novel', CO.TYPE_NOVEL)
  moved.SeedTree(project.items)
  return moved
enddef

# FUNCTION: Return a Screenplay with one Manuscript folder, named
# Screenplay as templates.vim names it.
def ScreenplayProject(): any
  var project = PO.Project.new(tempname() .. '/Play.bartleby')
  project.InitNew('Play', CO.TYPE_SCREENPLAY)
  project.SeedTree([BI.BinderItem.NewFolder('Screenplay', CO.ROLE_MANUSCRIPT)])
  return project
enddef

def Titles(folder: any): list<string>
  return folder.children->mapnew((_, item) => item.title)
enddef

def Test_import_titles_a_document_from_the_file_name(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var path: string = Source('Arrival.md', ['The train was late.'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [path])

  assert_equal(1, len(importer.added))
  assert_equal([], importer.skipped)
  assert_equal(['Scene 1', 'Arrival'], Titles(chapter))
  var doc = importer.added[0]
  assert_equal('manuscript/chapter-1/Arrival.md', doc.relPath)
  assert_equal(['The train was late.'], readfile(doc.AbsPath(project.BinderRoot())))
  # The source stays where it is.
  assert_true(filereadable(path))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_keeps_the_order_of_the_paths(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var paths: list<string> = ['One.md', 'Two.md', 'Three.md']->mapnew((_, n) => Source(n))
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), paths)

  assert_equal(['Scene 1', 'One', 'Two', 'Three'], Titles(chapter))
  assert_equal(['manuscript/chapter-1/One.md', 'manuscript/chapter-1/Two.md',
    'manuscript/chapter-1/Three.md'],
    importer.added->mapnew((_, d) => d.relPath))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_after_a_document_goes_next_to_it(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  chapter.AddChild(BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md'))
  var scene1 = chapter.ChildAt(0)
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, scene1.id), [Source('One.md'), Source('Two.md')])

  assert_equal(['Scene 1', 'One', 'Two', 'Scene 2'], Titles(chapter))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_at_the_top_level_stays_before_the_trash(): void
  var project = NovelProject()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [Source('Notes.md')])

  assert_equal('Notes', project.ChildAt(project.ChildCount() - 2).title)
  assert_equal(CO.ROLE_TRASH, project.ChildAt(project.ChildCount() - 1).structureRole)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_gives_the_copy_the_extension_of_the_scrive(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [Source('Plain.txt'), Source('Other.markdown')])
  assert_equal(['manuscript/chapter-1/Plain.md', 'manuscript/chapter-1/Other.md'],
    importer.added->mapnew((_, d) => d.relPath))
  FI.CleanupProjectFiles(project)

  var play = ScreenplayProject()
  var folder = play.ChildAt(0)
  var playImporter = IM.Importer.new(play)
  playImporter.Files(RowOf(play, folder.id), [Source('Scene.md'), Source('Open.fountain')])
  assert_equal(['manuscript/Scene.fountain', 'manuscript/Open.fountain'],
    playImporter.added->mapnew((_, d) => d.relPath))
  CleanupSources()
  FI.CleanupProjectFiles(play)
enddef

def Test_a_novel_refuses_fountain_and_a_screenplay_takes_it(): void
  var project = NovelProject()
  var path: string = Source('Open.fountain', ['INT. ROOM - DAY'])
  var importer = IM.Importer.new(project)
  assert_false(importer.Accepts(path))
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id), [path])
  assert_equal([], importer.added)
  assert_equal([path], importer.skipped)
  FI.CleanupProjectFiles(project)

  var play = ScreenplayProject()
  assert_true(IM.Importer.new(play).Accepts(path))
  CleanupSources()
  FI.CleanupProjectFiles(play)
enddef

def Test_import_skips_what_it_cannot_take(): void
  var project = NovelProject()
  var image: string = Source('Cover.png')
  var missing: string = $'{sources}/Gone.md'
  var noExt: string = Source('Readme')
  # A document of the scrive itself, which an import must not copy onto.
  var inside: string = project.BinderRoot() .. '/chapter-1/scene-01.md'
  mkdir(fnamemodify(inside, ':h'), 'p')
  writefile(['Text.'], inside)

  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id),
    [image, missing, noExt, inside])
  assert_equal([], importer.added)
  assert_equal([image, missing, noExt, inside], importer.skipped)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_import_keeps_the_bytes_of_the_source(): void
  var project = NovelProject()
  # No newline at the end, and a CR in the text, which a text copy would
  # change.
  var path: string = SourceRaw('Raw.md', ["One\r", 'Two'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).ChildAt(0).id), [path])

  assert_equal(readfile(path, 'b'),
    readfile(importer.added[0].AbsPath(project.BinderRoot()), 'b'))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_two_sources_of_one_name_get_their_own_files(): void
  var project = NovelProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var first: string = Source('a/Arrival.md', ['First.'])
  var second: string = Source('b/Arrival.md', ['Second.'])
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, chapter.id), [first, second])

  assert_equal(['manuscript/chapter-1/Arrival.md', 'manuscript/chapter-1/Arrival-2.md'],
    importer.added->mapnew((_, d) => d.relPath))
  assert_equal(['Second.'],
    readfile(importer.added[1].AbsPath(project.BinderRoot())))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_report_counts_what_came_in_and_what_was_skipped(): void
  var project = NovelProject()
  var row: T.Row = RowOf(project, project.ChildAt(1).ChildAt(0).id)
  var importer = IM.Importer.new(project)
  importer.Files(row, [Source('One.md')])
  assert_equal('imported 1 document', importer.Report())

  var second = IM.Importer.new(project)
  var image: string = Source('Cover.png')
  second.Files(row, [Source('Two.md'), Source('Three.md'), image])
  # The name, not the path: a report of a whole project export that was
  # skipped must stay readable.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/38
  assert_equal('imported 2 documents, skipped 1 file: Cover.png',
    second.Report())
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: The paths by the one spelling of path.vim, because a glob
# answers with the separator and the long name of its own system.
def Canons(paths: list<string>): list<string>
  return paths->mapnew((_, p) => PA.Canon(p))
enddef

def Test_expand_paths_takes_wildcards_and_keeps_an_unmatched_path(): void
  var first: string = Source('globbed/One.md')
  var second: string = Source('globbed/Two.md')
  var missing: string = $'{sources}/globbed/Gone.md'
  assert_equal(Canons([first, second]), Canons(IM.ExpandPaths([$'{sources}/globbed/*.md'])))
  assert_equal(Canons([missing]), Canons(IM.ExpandPaths([missing])))
  # A relative path becomes absolute, so that the import finds it from any
  # working directory.
  assert_equal([fnamemodify('rel.md', ':p')], IM.ExpandPaths(['rel.md']))
  CleanupSources()
enddef

# FUNCTION: Return a Novel with Parts whose Manuscript is its first item,
# for the role of a folder imported into it.
def PartsProject(): any
  var project = PO.Project.new(tempname() .. '/Parts.bartleby')
  project.InitNew('Parts', CO.TYPE_NOVEL_PARTS)
  project.SeedTree([BI.BinderItem.NewFolder('Manuscript', CO.ROLE_MANUSCRIPT)])
  return project
enddef

def StoryProject(): any
  var project = PO.Project.new(tempname() .. '/Story.bartleby')
  project.InitNew('Story', CO.TYPE_SHORT_STORY)
  project.SeedTree([BI.BinderItem.NewFolder('Manuscript', CO.ROLE_MANUSCRIPT)])
  return project
enddef

# FUNCTION: Return the last child of folder, the item that an import
# added at its end.
def LastChild(folder: any): any
  return folder.ChildAt(folder.ChildCount() - 1)
enddef

def Test_a_folder_import_keeps_its_tree(): void
  var project = NovelProject()
  var manuscript = project.ChildAt(1)
  Source('Novel/Notes.md')
  Source('Novel/Act One/Scene A.md', ['A.'])
  Source('Novel/Act One/Scene B.md')
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, manuscript.id), [$'{sources}/Novel'])

  var root = LastChild(manuscript)
  assert_equal('Novel', root.title)
  assert_equal(['Act One', 'Notes'], Titles(root))
  assert_equal(['Scene A', 'Scene B'], Titles(root.ChildAt(0)))
  assert_equal(['manuscript/chapter-Novel/Act-One/Scene-A.md',
    'manuscript/chapter-Novel/Act-One/Scene-B.md',
    'manuscript/chapter-Novel/Notes.md'],
    importer.added->mapnew((_, d) => d.relPath))
  assert_equal(['A.'], readfile(importer.added[0].AbsPath(project.BinderRoot())))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_folder_names_sort_naturally(): void
  var project = NovelProject()
  for name in ['Chapter 10.md', 'Chapter 2.md', 'Chapter 1.md']
    Source($'Book/{name}')
  endfor
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).id), [$'{sources}/Book'])

  assert_equal(['Chapter 1', 'Chapter 2', 'Chapter 10'],
    importer.added->mapnew((_, d) => d.title))
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_a_folder_leaves_out_what_it_cannot_take(): void
  var project = NovelProject()
  Source('Mixed/Keep.md')
  var image: string = Source('Mixed/Cover.png')
  Source('Mixed/.hidden.md')
  Source('Mixed/.cache/inside.md')
  Source('Other/Far.md')
  # A folder that is a symbolic link could lead back into the tree.
  var linked: string = $'{sources}/Mixed/elsewhere'
  FI.MakeLink($'{sources}/Other', linked)

  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).id), [$'{sources}/Mixed'])
  assert_equal(['Keep'], Titles(LastChild(project.ChildAt(1))))
  assert_true(index(importer.skipped, image) >= 0)
  if getftype(linked) ==# 'link'
    assert_true(index(importer.skipped, linked) >= 0)
  endif
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_an_imported_folder_takes_its_role_from_its_parent(): void
  Source('Tree/Inner/One.md')
  var dir: string = $'{sources}/Tree'

  # A novel: Chapter under the Manuscript, and a plain folder below it.
  var novel = NovelProject()
  var novelImporter = IM.Importer.new(novel)
  novelImporter.Files(RowOf(novel, novel.ChildAt(1).id), [dir])
  var root = LastChild(novel.ChildAt(1))
  assert_equal([CO.ROLE_CHAPTER, CO.ROLE_NONE],
    [root.structureRole, root.ChildAt(0).structureRole])
  FI.CleanupProjectFiles(novel)

  # A novel with parts: Part under the Manuscript, Chapter inside it.
  var parts = PartsProject()
  var partsImporter = IM.Importer.new(parts)
  partsImporter.Files(RowOf(parts, parts.ChildAt(0).id), [dir])
  root = LastChild(parts.ChildAt(0))
  assert_equal([CO.ROLE_PART, CO.ROLE_CHAPTER],
    [root.structureRole, root.ChildAt(0).structureRole])
  FI.CleanupProjectFiles(parts)

  # A short story has no chapters, so its Manuscript takes plain folders.
  var story = StoryProject()
  var storyImporter = IM.Importer.new(story)
  storyImporter.Files(RowOf(story, story.ChildAt(0).id), [dir])
  assert_equal(CO.ROLE_NONE, LastChild(story.ChildAt(0)).structureRole)
  FI.CleanupProjectFiles(story)

  # At the top level, where only a Custom folder may go.
  var top = NovelProject()
  var topImporter = IM.Importer.new(top)
  topImporter.Files(null_object, [dir])
  assert_equal(CO.ROLE_CUSTOM, top.ChildAt(top.ChildCount() - 2).structureRole)
  CleanupSources()
  FI.CleanupProjectFiles(top)
enddef

def Test_a_folder_with_no_document_is_skipped(): void
  var project = NovelProject()
  var image: string = Source('Images/Cover.png')
  var importer = IM.Importer.new(project)
  var manuscript = project.ChildAt(1)
  var before: number = manuscript.ChildCount()
  importer.Files(RowOf(project, manuscript.id), [$'{sources}/Images'])

  assert_equal([], importer.added)
  assert_equal(0, importer.folders)
  assert_equal(before, manuscript.ChildCount())
  # The file and the folder that holds nothing are both named.
  assert_equal([image, $'{sources}/Images'], importer.skipped)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_a_trailing_slash_keeps_the_folder_name(): void
  var project = NovelProject()
  Source('Slash/One.md')
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, project.ChildAt(1).id), [$'{sources}/Slash/'])

  assert_equal('Slash', LastChild(project.ChildAt(1)).title)
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_plan_counts_before_anything_changes(): void
  var project = NovelProject()
  var manuscript = project.ChildAt(1)
  Source('Novel/Act One/Scene A.md')
  Source('Novel/Notes.md')
  var loose: string = Source('Loose.md')
  var before: number = manuscript.ChildCount()

  var importer = IM.Importer.new(project)
  importer.Plan([$'{sources}/Novel', loose])
  assert_equal([3, 2], [importer.docs, importer.folders])
  # Nothing is added until Apply.
  assert_equal(before, manuscript.ChildCount())
  assert_equal([], importer.added)

  importer.Apply(RowOf(project, manuscript.id))
  assert_equal(3, len(importer.added))
  assert_equal('imported 3 documents, 2 new folders', importer.Report())
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

def Test_a_file_and_a_folder_keep_their_order(): void
  var project = NovelProject()
  var manuscript = project.ChildAt(1)
  var loose: string = Source('Loose.md')
  Source('Novel/One.md')
  var importer = IM.Importer.new(project)
  importer.Files(RowOf(project, manuscript.id), [loose, $'{sources}/Novel'])

  assert_equal(['Loose', 'Novel'], Titles(manuscript)[-2 : ])
  CleanupSources()
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_import_titles_a_document_from_the_file_name()
  Test_import_keeps_the_order_of_the_paths()
  Test_import_after_a_document_goes_next_to_it()
  Test_import_at_the_top_level_stays_before_the_trash()
  Test_import_gives_the_copy_the_extension_of_the_scrive()
  Test_a_novel_refuses_fountain_and_a_screenplay_takes_it()
  Test_import_skips_what_it_cannot_take()
  Test_import_keeps_the_bytes_of_the_source()
  Test_two_sources_of_one_name_get_their_own_files()
  Test_the_report_counts_what_came_in_and_what_was_skipped()
  Test_expand_paths_takes_wildcards_and_keeps_an_unmatched_path()
  Test_a_folder_import_keeps_its_tree()
  Test_folder_names_sort_naturally()
  Test_a_folder_leaves_out_what_it_cannot_take()
  Test_an_imported_folder_takes_its_role_from_its_parent()
  Test_a_folder_with_no_document_is_skipped()
  Test_a_trailing_slash_keeps_the_folder_name()
  Test_the_plan_counts_before_anything_changes()
  Test_a_file_and_a_folder_keep_their_order()
enddef
