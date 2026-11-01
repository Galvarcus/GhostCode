vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_import_map.vim: import_map.vim, and the project import of
# import.vim that reads it, with real files on disk. The export that these
# tests build writes a metadata sidecar beside every item, a notes file
# beside a document that has notes, and a snapshots folder beside a
# document that has snapshots, as the export of the application does.
# Detection, the scrive type, the sidecars, and the metadata are tested on
# their own, and then a whole export is imported into a scrive.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/import_map.vim' as IMM
import autoload 'bartleby/import.vim' as IM
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# The export of one test, under its own temporary name.
var export_dir: string = ''

# FUNCTION: Return the metadata lines of an item, with the status field and
# the label field under the names that the writer of the export gave them,
# which Bartleby cannot know.
def MetaLines(status: string, label: string, keywords: string,
    synopsis: list<string> = []): list<string>
  return [
    'Created: October 24, 2026 at 4:11 PM',
    'Modified: October 24, 2026 at 4:57 PM',
    $'Not Done Yet: {status}',
    $'My custom label: {label}',
    $'Keywords: {keywords}',
    '',
    '',
  ] + synopsis
enddef

def NoMeta(): list<string>
  return MetaLines('No Status', 'No Label', '')
enddef

# FUNCTION: Start a new export under a temporary folder and return its
# path. The caller removes it with Cleanup.
def Root(): string
  export_dir = tempname() .. '/Project'
  mkdir(export_dir, 'p')
  return export_dir
enddef

# FUNCTION: Make a folder of the export at dir, with the metadata file that
# every folder of a project carries inside it, and return its path. The
# second folder of one title, Chapter-1, holds its metadata under the bare
# title, as the export writes it.
def Folder(dir: string, title: string): string
  var path: string = $'{dir}/{title}'
  mkdir(path, 'p')
  var bare: string = substitute(title, '-\d\+$', '', '')
  writefile(NoMeta(), $'{path}/{bare} MetaData.txt')
  return path
enddef

# FUNCTION: Make a built-in folder of the export at dir, such as its draft
# or its trash, which carries no metadata file of its own.
def BuiltIn(dir: string, title: string): string
  var path: string = $'{dir}/{title}'
  mkdir(path, 'p')
  return path
enddef

# FUNCTION: Make a document of the export in dir: its text file, its
# metadata file, and its notes file when notes is given. The metadata file
# of a second document of the same title carries the number at the end, as
# the export writes it.
def Doc(dir: string, name: string, text: list<string> = ['Text.'],
    meta: list<string> = [], notes: string = '', ext: string = '.md'): string
  var path: string = $'{dir}/{name}{ext}'
  writefile(text, path)
  var num: string = matchstr(name, '-\d\+$')
  var stem: string = strpart(name, 0, strlen(name) - strlen(num))
  writefile(empty(meta) ? NoMeta() : meta,
    $'{dir}/{stem} MetaData{num}.txt')
  if notes !=# ''
    writefile([notes], $'{dir}/{name} Notes{ext}')
  endif
  return path
enddef

# FUNCTION: Make the snapshots folder of the document named name, which the
# export writes beside it and no import reads.
def Snaps(dir: string, name: string): string
  var path: string = $'{dir}/{name} Snapshots'
  mkdir(path, 'p')
  writefile(['An older draft.'], $'{path}/Untitled (In Progress).md')
  return path
enddef

def Cleanup(): void
  if export_dir !=# ''
    delete(fnamemodify(export_dir, ':h'), 'rf')
    export_dir = ''
  endif
enddef

# FUNCTION: Return an export of a novel: a draft of one chapter of two
# scenes, one of them with notes, a snapshot, and metadata of its own,
# front matter, characters, research, a places folder that Bartleby has no
# role for, a document at the top level, and a trash.
def NovelExport(): string
  var root: string = Root()
  var draft: string = BuiltIn(root, 'Manuscript')
  var chapter: string = Folder(draft, 'Chapter')
  Doc(chapter, 'Scene', ['The train was late.'],
    MetaLines('In Progress', 'Red', 'Testing, Export',
    ['This is a new scene.']), 'A note for this scene.')
  Snaps(chapter, 'Scene')
  Doc(chapter, 'Scene-1', ['The train was early.'])
  var front: string = Folder(root, 'Front Matter')
  Doc(front, 'Title Page', ['A title.'], NoMeta(), 'A note for the title.')
  writefile(['The notes of the folder.'], $'{front}/Front Matter Notes.md')
  var chars: string = Folder(root, 'Characters')
  Doc(chars, 'Joe', ['A character.'])
  var research: string = BuiltIn(root, 'Research')
  Doc(research, 'Sample', ['A sample.'])
  writefile(['%PDF-1.4'], $'{research}/Output.pdf')
  writefile(NoMeta(), $'{research}/Output MetaData.txt')
  var places: string = Folder(root, 'Places')
  Doc(places, 'The Station', ['A place.'])
  Doc(root, 'Novel Format', ['How to use this template.'])
  var trash: string = BuiltIn(root, 'Trash')
  Doc(trash, 'Thrown Away', ['Gone.'])
  return root
enddef

# FUNCTION: Return a Novel scrive whose folder is its own temporary one, so
# that a test writes no file of another test.
def NovelScrive(): PO.Project
  var project: PO.Project = PO.Project.new(tempname() .. '/Novel.bartleby')
  project.InitNew('Novel', CO.TYPE_NOVEL)
  project.SeedTree(FI.BuildProject().items)
  return project
enddef

# FUNCTION: Return the titles of the children of folder.
def Titles(folder: any): list<string>
  return folder.children->mapnew((_, item) => item.title)
enddef

# FUNCTION: Return the top-level folder of project with role.
def TopWithRole(project: PO.Project, role: string): BI.BinderItem
  for i in range(project.ChildCount())
    if project.ChildAt(i).structureRole ==# role
      return project.ChildAt(i)
    endif
  endfor
  return null_object
enddef

def Test_an_export_is_known_by_its_draft_and_its_metadata_files(): void
  var root: string = NovelExport()
  assert_equal(IMM.LAYOUT_SIDECAR, IMM.Detect(root))
  Cleanup()
enddef

def Test_a_folder_of_plain_files_is_no_export(): void
  var root: string = Root()
  mkdir($'{root}/Manuscript', 'p')
  writefile(['Text.'], $'{root}/Manuscript/Scene.md')
  assert_equal('', IMM.Detect(root))
  Cleanup()
enddef

def Test_a_folder_without_a_draft_is_no_export(): void
  var root: string = Root()
  Folder(root, 'Places')
  assert_equal('', IMM.Detect(root))
  Cleanup()
enddef

def Test_the_type_follows_the_depth_of_the_draft(): void
  var root: string = Root()
  var draft: string = BuiltIn(root, 'Manuscript')
  Doc(draft, 'Scene')
  assert_equal(CO.TYPE_SHORT_STORY, IMM.ProjectType(root))

  var chapter: string = Folder(draft, 'Chapter')
  Doc(chapter, 'Scene')
  assert_equal(CO.TYPE_NOVEL, IMM.ProjectType(root))

  Doc(Folder(chapter, 'Inner'), 'Scene')
  assert_equal(CO.TYPE_NOVEL_PARTS, IMM.ProjectType(root))
  Cleanup()
enddef

def Test_fountain_text_makes_it_a_screenplay(): void
  var root: string = Root()
  var draft: string = BuiltIn(root, 'Screenplay')
  Doc(draft, 'Scene', ['INT. A TRAIN'], NoMeta(), '', CO.EXT_FOUNTAIN)
  assert_equal(CO.TYPE_SCREENPLAY, IMM.ProjectType(root))
  Cleanup()
enddef

# FUNCTION: A snapshots folder holds documents, so it would turn the type
# of a novel into a novel with parts if the scan took it for a folder.
def Test_a_snapshots_folder_does_not_change_the_type(): void
  var root: string = Root()
  var chapter: string = Folder(BuiltIn(root, 'Manuscript'), 'Chapter')
  Doc(chapter, 'Scene')
  Snaps(chapter, 'Scene')
  assert_equal(CO.TYPE_NOVEL, IMM.ProjectType(root))
  Cleanup()
enddef

# FUNCTION: The writer can rename the status field and the label field, so
# the import reads the third and the fourth field whatever they are called,
# and maps the three values that Bartleby names differently.
def Test_a_metadata_file_is_read_through_renamed_fields(): void
  var root: string = Root()
  var path: string = $'{root}/One MetaData.txt'
  writefile(MetaLines('In Progress', 'Red', 'Testing, Export',
    ['This is a new scene.', 'It is a good scene.']), path)
  var meta: IMM.Meta = IMM.MetaFrom(path)

  assert_equal(CO.STATUS_WORKING, meta.status)
  assert_equal('Red', meta.label)
  assert_equal(['Testing', 'Export'], meta.keywords)
  assert_equal("This is a new scene.\nIt is a good scene.", meta.synopsis)
  Cleanup()
enddef

def Test_the_statuses_of_the_export_map_onto_the_list(): void
  var root: string = Root()
  var want: dict<string> = {
    'No Status': CO.NONE,
    'To Do': CO.STATUS_TODO,
    'In Progress': CO.STATUS_WORKING,
    'First Draft': CO.STATUS_FIRST,
    'Revised Draft': CO.STATUS_REVISED,
    'Final Draft': CO.STATUS_FINAL,
    Done: CO.STATUS_DONE,
  }
  for [given, mapped] in items(want)
    var path: string = $'{root}/One MetaData.txt'
    writefile(MetaLines(given, 'No Label', ''), path)
    assert_equal(mapped, IMM.MetaFrom(path).status, given)
  endfor
  Cleanup()
enddef

def Test_a_status_and_a_label_of_its_own_become_none(): void
  var root: string = Root()
  var path: string = $'{root}/One MetaData.txt'
  writefile(MetaLines('Waiting On Beta', 'Teal', ''), path)
  var meta: IMM.Meta = IMM.MetaFrom(path)

  assert_equal(CO.NONE, meta.status)
  assert_equal(CO.NONE, meta.label)
  assert_equal('', meta.synopsis)
  Cleanup()
enddef

def Test_a_notes_file_is_a_sidecar_and_a_snapshot_folder_is_dropped(): void
  var root: string = Root()
  var chapter: string = Folder(BuiltIn(root, 'Manuscript'), 'Chapter')
  Doc(chapter, 'Scene', ['Text.'], NoMeta(), 'A note.')
  Snaps(chapter, 'Scene')
  var listing: IMM.Listing = IMM.Classify(chapter)

  assert_equal(['Scene'], listing.items->mapnew((_, i) => i.title))
  assert_equal('Scene Notes.md', fnamemodify(listing.items[0].notesPath, ':t'))
  assert_equal(['Scene Snapshots'],
    listing.dropped->mapnew((_, p) => fnamemodify(p, ':t')))
  Cleanup()
enddef

def Test_the_notes_of_a_folder_belong_to_the_folder(): void
  var root: string = Root()
  var front: string = Folder(root, 'Front Matter')
  writefile(['The notes of the folder.'], $'{front}/Front Matter Notes.md')
  var listing: IMM.Listing = IMM.Classify(front)

  assert_equal([], listing.dropped)
  assert_equal('Front Matter Notes.md', fnamemodify(listing.ownNotes, ':t'))
  Cleanup()
enddef

# FUNCTION: The export numbers the second item of a title, and the title
# that the writer gave it holds no number.
def Test_two_items_of_one_title_keep_that_title(): void
  var root: string = Root()
  var chapter: string = Folder(BuiltIn(root, 'Manuscript'), 'Chapter')
  Doc(chapter, 'Scene')
  Doc(chapter, 'Scene-1')
  var titles: list<string> = IMM.Classify(chapter).items
    ->mapnew((_, i) => i.title)

  assert_equal(['Scene', 'Scene'], titles)
  Cleanup()
enddef

def Test_a_number_that_no_sibling_explains_stays_in_the_title(): void
  var root: string = Root()
  var chapter: string = Folder(BuiltIn(root, 'Manuscript'), 'Chapter')
  Doc(chapter, 'Scene-2')
  assert_equal(['Scene-2'],
    IMM.Classify(chapter).items->mapnew((_, i) => i.title))
  Cleanup()
enddef

def Test_an_order_number_in_front_of_a_title_is_stripped(): void
  var root: string = Root()
  var draft: string = BuiltIn(root, 'Manuscript')
  Doc(Folder(draft, '01 - Chapter One'), '02-Arrival')
  var chapters: list<IMM.Item> = IMM.Classify(draft).items

  assert_equal(['Chapter One'], chapters->mapnew((_, i) => i.title))
  assert_equal(['Arrival'],
    IMM.Classify(chapters[0].path).items->mapnew((_, i) => i.title))
  Cleanup()
enddef

def Test_a_metadata_file_is_never_a_document(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  for doc in importer.added
    assert_true(doc.title !~# 'MetaData', doc.title)
  endfor
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Two chapters of one title would share a folder on disk, so the
# second takes the next free number among the chapters of the Manuscript,
# as a chapter added without a title does.
def Test_a_chapter_whose_title_repeats_takes_the_next_number(): void
  var root: string = Root()
  var draft: string = BuiltIn(root, 'Manuscript')
  Doc(Folder(draft, 'Chapter'), 'Scene', ['The first.'])
  Doc(Folder(draft, 'Chapter-1'), 'Scene', ['The second.'])
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  # The scrive holds the chapters 1 and 2 already, so the repeat is 3.
  var manuscript: BI.BinderItem = TopWithRole(project, CO.ROLE_MANUSCRIPT)
  assert_equal(['1', '2', 'Chapter', '3'], Titles(manuscript))
  assert_equal('manuscript/chapter-Chapter/Scene.md',
    manuscript.ChildAt(2).ChildAt(0).relPath)
  assert_equal('manuscript/chapter-3/Scene.md',
    manuscript.ChildAt(3).ChildAt(0).relPath)
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_export_fills_the_folder_of_each_role(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  assert_equal(IMM.LAYOUT_SIDECAR, importer.layout)
  # The chapter of the export comes after the two chapters of the scrive.
  var manuscript: BI.BinderItem = TopWithRole(project, CO.ROLE_MANUSCRIPT)
  assert_equal(['1', '2', 'Chapter'], Titles(manuscript))
  var chapter: BI.BinderItem = manuscript.ChildAt(2)
  assert_equal(CO.ROLE_CHAPTER, chapter.structureRole)
  assert_equal(['Scene', 'Scene'], Titles(chapter))
  assert_equal('manuscript/chapter-Chapter/Scene.md', chapter.ChildAt(0).relPath)
  assert_equal(['Title Page'], Titles(TopWithRole(project, CO.ROLE_FRONT_MATTER)))
  assert_equal(['Joe'], Titles(TopWithRole(project, CO.ROLE_CHARS)))
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Research takes the research of the export, every folder that
# the export gives no role, every document at its top level, and the notes
# of every document, each in one place.
def Test_research_takes_what_has_no_folder_of_its_own(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  # In the order of the export: its document at the top level, its folder
  # without a role, its own research, and the notes last.
  var research: BI.BinderItem = TopWithRole(project, CO.ROLE_RESEARCH)
  assert_equal(['Novel Format', 'Places', 'Sample', 'Document Notes'],
    Titles(research))
  var notes: BI.BinderItem = research.ChildAt(3)
  assert_equal(['Front Matter', 'Title Page', 'Scene'], Titles(notes))
  assert_equal(['A note for this scene.'],
    readfile(notes.ChildAt(2).AbsPath(project.BinderRoot())))
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_metadata_of_a_document_comes_with_it(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  var scene: BI.BinderItem = TopWithRole(project, CO.ROLE_MANUSCRIPT)
    .ChildAt(2).ChildAt(0)
  var meta = scene.LoadMeta(project.BinderRoot())
  assert_equal(CO.STATUS_WORKING, meta.status)
  assert_equal('Red', meta.label)
  assert_equal(['Testing', 'Export'], meta.keywords)
  assert_equal('This is a new scene.', meta.synopsis)
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

def Test_the_trash_of_the_export_is_left_behind(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  for doc in importer.added
    assert_true(doc.title !=# 'Thrown Away')
  endfor
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: A source of a format that Bartleby cannot read is counted and
# named, and the report asks for a new export, so that the writer knows
# what to do about it.
def Test_a_format_that_cannot_be_read_is_reported(): void
  var root: string = NovelExport()
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  assert_true(importer.Report() =~# 'read the folder as a project export')
  assert_true(importer.Report() =~# 'Output.pdf')
  assert_true(importer.Report() =~# 'export those again')
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: An export of only one format that Bartleby cannot read adds
# nothing, and still says what it left and why.
def Test_an_export_of_one_unreadable_format_adds_nothing(): void
  var root: string = Root()
  var chapter: string = Folder(BuiltIn(root, 'Manuscript'), 'Chapter')
  Doc(chapter, 'Scene', ['{\rtf1}'], NoMeta(), '', '.rtf')
  var project: PO.Project = NovelScrive()
  var importer = IM.Importer.new(project)
  importer.Files(null_object, [root])

  assert_equal([], importer.added)
  assert_true(importer.Report() =~# 'Scene.rtf')
  assert_true(importer.Report() =~# 'export those again')
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: A folder that is no export still imports as a plain tree, next
# to the row that the caller names, and says so with an empty layout.
def Test_a_folder_that_is_no_export_imports_as_a_plain_tree(): void
  var root: string = Root()
  mkdir($'{root}/Chapter', 'p')
  writefile(['Text.'], $'{root}/Chapter/Scene.md')
  var project: PO.Project = NovelScrive()
  var manuscript: BI.BinderItem = TopWithRole(project, CO.ROLE_MANUSCRIPT)
  var importer = IM.Importer.new(project)
  importer.Files(T.FindRowById(T.Flatten(project), manuscript.id), [root])

  assert_equal('', importer.layout)
  assert_equal(['1', '2', 'Project'], Titles(manuscript))
  Cleanup()
  FI.CleanupProjectFiles(project)
enddef

export def RunAll(): void
  Test_an_export_is_known_by_its_draft_and_its_metadata_files()
  Test_a_folder_of_plain_files_is_no_export()
  Test_a_folder_without_a_draft_is_no_export()
  Test_the_type_follows_the_depth_of_the_draft()
  Test_fountain_text_makes_it_a_screenplay()
  Test_a_snapshots_folder_does_not_change_the_type()
  Test_a_metadata_file_is_read_through_renamed_fields()
  Test_the_statuses_of_the_export_map_onto_the_list()
  Test_a_status_and_a_label_of_its_own_become_none()
  Test_a_notes_file_is_a_sidecar_and_a_snapshot_folder_is_dropped()
  Test_the_notes_of_a_folder_belong_to_the_folder()
  Test_two_items_of_one_title_keep_that_title()
  Test_a_number_that_no_sibling_explains_stays_in_the_title()
  Test_an_order_number_in_front_of_a_title_is_stripped()
  Test_a_metadata_file_is_never_a_document()
  Test_the_export_fills_the_folder_of_each_role()
  Test_a_chapter_whose_title_repeats_takes_the_next_number()
  Test_research_takes_what_has_no_folder_of_its_own()
  Test_the_metadata_of_a_document_comes_with_it()
  Test_the_trash_of_the_export_is_left_behind()
  Test_a_format_that_cannot_be_read_is_reported()
  Test_an_export_of_one_unreadable_format_adds_nothing()
  Test_a_folder_that_is_no_export_imports_as_a_plain_tree()
enddef
