vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_scrive.vim: tab completion of scrive names for :BartlebyOpen,
# MatchNames and CompleteNames, and ResolveName of scrive.vim. MatchNames
# takes the names as an argument, so its tests need no files. The tests of
# CompleteNames and ResolveName create scrive folders in the binder root
# and remove them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as S
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/persist.vim' as PE
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

const NAMES: list<string> = ['Other', 'My Novel', 'My Screenplay']

# FUNCTION: Create a scrive folder for each name in the binder root, and
# return their paths for RemoveScrives.
def MakeScrives(names: list<string>): list<string>
  var paths: list<string> = names->mapnew((_, n) => S.ScrivePath(n))
  for path in paths
    mkdir(path, 'p')
  endfor
  return paths
enddef

def RemoveScrives(paths: list<string>): void
  for path in paths
    delete(path, 'rf')
  endfor
enddef

def Test_prefix_match_ignores_case_and_is_sorted(): void
  assert_equal(['My Novel', 'My Screenplay'], S.MatchNames(NAMES, 'my', 'my'))
  assert_equal(['Other'], S.MatchNames(NAMES, 'o', 'o'))
enddef

def Test_empty_argument_lists_every_name(): void
  assert_equal(['My Novel', 'My Screenplay', 'Other'], S.MatchNames(NAMES, '', ''))
enddef

def Test_name_with_a_space_returns_the_rest_after_the_last_word(): void
  # Typed: My N. Vim replaces only N, the last word.
  assert_equal(['Novel'], S.MatchNames(NAMES, 'My N', 'N'))
  # Typed: My and a space. The last word is empty.
  assert_equal(['Novel', 'Screenplay'], S.MatchNames(NAMES, 'My ', ''))
enddef

def Test_no_match_is_empty(): void
  assert_equal([], S.MatchNames(NAMES, 'xyz', 'xyz'))
enddef

def Test_fuzzy_when_wildoptions_has_fuzzy(): void
  var saved = &wildoptions
  set wildoptions=fuzzy
  assert_equal(['My Novel'], S.MatchNames(NAMES, 'nvl', 'nvl'))
  &wildoptions = saved
enddef

def Test_complete_names_reads_the_whole_argument(): void
  var paths = MakeScrives(NAMES)
  var line = 'BartlebyOpen My N'
  assert_equal(['Novel'], S.CompleteNames('N', line, strlen(line)))
  RemoveScrives(paths)
enddef

def Test_resolve_name(): void
  var paths = MakeScrives(['My Novel'])
  assert_equal('My Novel', S.ResolveName('My Novel'))
  assert_equal('My Novel', S.ResolveName('my novel'))
  assert_equal('Unknown', S.ResolveName('Unknown'))
  RemoveScrives(paths)
enddef

def Test_resolve_name_does_not_guess_between_two_matches(): void
  var paths = MakeScrives(['Draft', 'DRAFT'])
  # Only on a file system that tells the two folders apart.
  if len(S.ListScrives()->filter((_, n) => n ==? 'draft')) == 2
    assert_equal('draft', S.ResolveName('draft'))
  endif
  RemoveScrives(paths)
enddef

# Damaged project.json files, as a crash during a save or a bad edit
# leaves them: what each is, its text, and a part of the error it gets.
const DAMAGED: list<list<string>> = [
  ['truncated', '{"name": "Novel", "items": [{"id": "a", "ti', 'cannot be read'],
  ['empty', '', 'holds no list of binder items'],
  ['not an object', '[1, 2]', 'holds no list of binder items'],
  ['no items', '{"name": "Novel"}', 'holds no list of binder items'],
  ['items not a list', '{"name": "Novel", "items": {}}', 'holds no list of binder items'],
  ['an item not an object', '{"name": "Novel", "items": [1]}', 'holds no list of binder items'],
]

# FUNCTION: A damaged project.json does not open, and stays as it was, so
# that nothing can save an empty tree over it.
def Test_a_damaged_project_file_does_not_open(): void
  var paths = MakeScrives(['Damaged'])
  var file: string = paths[0] .. '/project.json'
  for [what, text, error] in DAMAGED
    writefile([text], file)
    assert_true(S.Open('Damaged') is null_object, what)
    assert_equal([text], readfile(file), what)
    # The error names the file and why.
    var project = PO.Project.new(paths[0])
    assert_false(project.Load(), what)
    assert_match(error, project.loadError, what)
    assert_match('project.json', project.loadError, what)
  endfor
  RemoveScrives(paths)
enddef

def Test_a_project_that_did_not_load_never_saves(): void
  var paths = MakeScrives(['Damaged'])
  var file: string = paths[0] .. '/project.json'
  writefile([DAMAGED[0][1]], file)
  var project = PO.Project.new(paths[0])
  assert_false(project.Load())
  project.Save()
  assert_equal([DAMAGED[0][1]], readfile(file))
  RemoveScrives(paths)
enddef

def Test_a_sound_project_file_opens_and_saves(): void
  var paths = MakeScrives(['Sound'])
  var file: string = paths[0] .. '/project.json'
  writefile([json_encode({name: 'Sound', projectType: CO.TYPE_NOVEL, items: [
    {id: 'm1', title: 'Manuscript', kind: CO.KIND_FOLDER, structureRole: CO.ROLE_MANUSCRIPT, children: []}]})], file)
  var project = S.Open('Sound')
  assert_true(project isnot null_object)
  assert_equal('', project is null_object ? 'no project' : project.loadError)
  if project isnot null_object
    project.Save()
    assert_equal('Manuscript', json_decode(join(readfile(file), "\n")).items[0].title)
  endif
  RemoveScrives(paths)
enddef

# FUNCTION: Each save keeps the version before as a backup, and a load
# that fails names the backup, so that the scrive can be brought back.
def Test_a_save_keeps_a_backup_that_a_failed_load_names(): void
  var paths = MakeScrives(['Backed'])
  var file: string = paths[0] .. '/project.json'
  var project = PO.Project.new(paths[0])
  project.InitNew('Backed', CO.TYPE_NOVEL)
  project.Save()
  project.Save()
  assert_true(filereadable(file .. PE.BACKUP_SUFFIX))
  writefile([DAMAGED[0][1]], file)
  var damaged = PO.Project.new(paths[0])
  assert_false(damaged.Load())
  assert_match('project.json' .. PE.BACKUP_SUFFIX, damaged.loadError)
  RemoveScrives(paths)
enddef

# FUNCTION: Run a real Vim with the plugin, and return whether Quill's
# hook on entering a buffer exists before any scrive opens, and after one
# opens. A plugin that loads at startup must not run it for every buffer.
def QuillHookBeforeAndAfter(): list<number>
  var root: string = FI.Slashed(tempname())
  var log: string = FI.Slashed(tempname())
  var script: string = FI.Slashed(tempname())
  var plugin: string = FI.Slashed(fnamemodify(expand('<script>'), ':p:h:h'))
  writefile([
    'vim9script',
    $'g:bartleby_binder_root = "{root}"',
    'runtime plugin/bartleby.vim',
    'var before: number = exists("#bartleby_quill_auto#BufEnter")',
    'bartleby#scrive#Create("Hooks", "novel")',
    'BartlebyOpen Hooks',
    $'writefile([string(before), string(exists("#bartleby_quill_auto#BufEnter"))], "{log}")',
    'qa!',
  ], script)
  FI.Spawn($'{v:progpath} -es -u NONE -N '
    .. $'--cmd "set rtp+={plugin},{FI.LoggerDir()}" -S {script}')
  var result: list<number> = filereadable(log) ? readfile(log)->mapnew((_, v) => str2nr(v)) : []
  delete(log)
  delete(script)
  delete(root, 'rf')
  return result
enddef

def Test_quills_hook_starts_when_a_scrive_opens(): void
  assert_equal([0, 1], QuillHookBeforeAndAfter())
enddef

# The facts of one spawned Vim, read once for the tests below.
var import_facts: dict<any> = {}

# FUNCTION: Run a real Vim with a temporary binder root, and report what
# Create without starters and CreateFrom leave behind: a scrive from a
# folder of one chapter and one note, a scrive from a folder with nothing
# to import, and a scrive with no starter documents. scrive.vim reads
# g:bartleby_binder_root when it loads, so a test cannot redirect it in
# this Vim, and a scrive of the user is never touched this way.
def ImportFacts(): dict<any>
  if !empty(import_facts)
    return import_facts
  endif
  var root: string = FI.Slashed(tempname())
  var src: string = FI.Slashed(tempname()) .. '/Novel'
  var bare: string = FI.Slashed(tempname()) .. '/Images'
  var log: string = FI.Slashed(tempname())
  var script: string = FI.Slashed(tempname())
  var plugin: string = FI.Slashed(fnamemodify(expand('<script>'), ':p:h:h'))
  mkdir(src .. '/Chapter 1', 'p')
  mkdir(bare, 'p')
  writefile(['Scene text.'], src .. '/Chapter 1/Arrival.md')
  writefile(['Notes.'], src .. '/Notes.md')
  writefile(['Not text.'], bare .. '/Cover.png')
  writefile([
    'vim9script',
    $'g:bartleby_binder_root = "{root}"',
    'runtime plugin/bartleby.vim',
    'import autoload "bartleby/scrive.vim" as S',
    'import autoload "bartleby/project.vim" as PO',
    'var facts: dict<any> = {}',
    $'var importer = S.CreateFrom("Imported", "novel", "{src}")',
    'facts.made = importer isnot null_object ? 1 : 0',
    'facts.report = importer isnot null_object ? importer.Report() : ""',
    'var loaded = PO.Project.new(S.ScrivePath("Imported"))',
    'facts.loads = loaded.Load() ? 1 : 0',
    'facts.tops = loaded.items->mapnew((_, i) => i.title)',
    'var manuscript = loaded.ChildAt(1)',
    'facts.manuscript = manuscript.children->mapnew((_, i) => i.title)',
    'facts.inner = manuscript.ChildAt(0).children->mapnew((_, i) => i.title)',
    'var binder = loaded.BinderRoot()',
    'facts.files = [',
    '  filereadable(binder .. "/manuscript/chapter-Novel/Chapter-1/Arrival.md"),',
    '  filereadable(binder .. "/manuscript/chapter-Novel/Notes.md")]',
    'facts.starterfile = filereadable(binder .. "/manuscript/chapter-1/Scene-1.md")',
    $'var nothing = S.CreateFrom("Nothing", "novel", "{bare}")',
    'facts.nothing_made = nothing isnot null_object ? 1 : 0',
    'facts.nothing_dir = isdirectory(S.ScrivePath("Nothing"))',
    'var starters = S.Create("Bare", "novel", false)',
    'facts.bare_tops = starters.items->mapnew((_, i) => i.title)',
    'facts.bare_manuscript = starters.ChildAt(1).ChildCount()',
    'facts.bare_file = filereadable(starters.BinderRoot() .. "/manuscript/chapter-1/Scene-1.md")',
    $'writefile([json_encode(facts)], "{log}")',
    'qa!',
  ], script)
  FI.Spawn($'{v:progpath} -es -u NONE -N '
    .. $'--cmd "set rtp+={plugin},{FI.LoggerDir()}" -S {script}')
  import_facts = filereadable(log) ? json_decode(join(readfile(log), '')) : {}
  delete(log)
  delete(script)
  delete(root, 'rf')
  delete(fnamemodify(src, ':h'), 'rf')
  delete(fnamemodify(bare, ':h'), 'rf')
  return import_facts
enddef

def Test_a_scrive_from_a_folder_holds_the_import(): void
  var facts: dict<any> = ImportFacts()
  assert_equal([1, 1], [get(facts, 'made', 0), get(facts, 'loads', 0)])
  assert_equal(['Front Matter', 'Manuscript', 'Back Matter', 'Characters', 'Research', 'Trash'],
    get(facts, 'tops', []))
  # The imported folder is the only item of the Manuscript, with its own
  # tree inside it. The paths that facts.files reads are spelled as the
  # layout writes them, capitals included: a file system that folds case
  # answers for a path in any case, so a wrong one passes on macOS and
  # fails on a Linux runner.
  assert_equal(['Novel'], get(facts, 'manuscript', []))
  assert_equal(['Chapter 1', 'Notes'], get(facts, 'inner', []))
  assert_equal([1, 1], get(facts, 'files', []))
  assert_equal('imported 2 documents, 2 new folders', get(facts, 'report', ''))
enddef

def Test_a_scrive_from_a_folder_has_no_starter_document(): void
  assert_equal(0, get(ImportFacts(), 'starterfile', 1))
enddef

def Test_a_source_with_nothing_to_import_leaves_no_scrive(): void
  var facts: dict<any> = ImportFacts()
  assert_equal([0, 0],
    [get(facts, 'nothing_made', 1), get(facts, 'nothing_dir', 1)])
enddef

def Test_create_without_starters_leaves_the_manuscript_empty(): void
  var facts: dict<any> = ImportFacts()
  # The structural folders are still there, and no starter file is on disk.
  assert_equal(['Front Matter', 'Manuscript', 'Back Matter', 'Characters', 'Research', 'Trash'],
    get(facts, 'bare_tops', []))
  assert_equal(0, get(facts, 'bare_manuscript', -1))
  assert_equal(0, get(facts, 'bare_file', 1))
enddef

export def RunAll(): void
  Test_prefix_match_ignores_case_and_is_sorted()
  Test_empty_argument_lists_every_name()
  Test_name_with_a_space_returns_the_rest_after_the_last_word()
  Test_no_match_is_empty()
  Test_fuzzy_when_wildoptions_has_fuzzy()
  Test_complete_names_reads_the_whole_argument()
  Test_resolve_name()
  Test_resolve_name_does_not_guess_between_two_matches()
  Test_a_damaged_project_file_does_not_open()
  Test_a_project_that_did_not_load_never_saves()
  Test_a_sound_project_file_opens_and_saves()
  Test_a_save_keeps_a_backup_that_a_failed_load_names()
  Test_quills_hook_starts_when_a_scrive_opens()
  Test_a_scrive_from_a_folder_holds_the_import()
  Test_a_scrive_from_a_folder_has_no_starter_document()
  Test_a_source_with_nothing_to_import_leaves_no_scrive()
  Test_create_without_starters_leaves_the_manuscript_empty()
enddef
