vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_compile.vim: the Concatenate functions of compile.vim, the
# exported entry points. WalkManuscript, WalkBook, WalkFrontOrBackMatter,
# JoinSiblingBlocks, and the other helpers are local to the script and
# reached through them. Needs real files on disk, because ReadDocLines
# reads them, so each test writes fixture text under the binder root of
# the project and removes it with FI.CleanupProjectFiles.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/slug.vim' as SU
import './fixtures.vim' as FI
import 'Logger/messages.vim' as LM
import './test_texcheck.vim' as TTX

# FUNCTION: Build the shared fixture project, add one document each to
# Front Matter and Back Matter, which the fixture leaves empty, and write
# real text for every document. The caller must call
# FI.CleanupProjectFiles on the project.
def BuildProjectWithContent(): dict<any>
  var project = FI.BuildProject()
  var frontMatter = project.ChildAt(0)
  var manuscript = project.ChildAt(1)
  var backMatter = project.ChildAt(2)

  var dedication = BI.BinderItem.NewDocument('Dedication', 'front-matter/dedication.md')
  frontMatter.AddChild(dedication)
  var acknowledgments = BI.BinderItem.NewDocument('Acknowledgments', 'back-matter/acknowledgments.md')
  backMatter.AddChild(acknowledgments)

  var chapter1 = manuscript.ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  var scene2 = chapter2.ChildAt(0)

  FI.WriteDocContent(project, dedication, ['For my family.'])
  FI.WriteDocContent(project, scene1, ['It was a dark and stormy night.'])
  FI.WriteDocContent(project, scene2, ['The end was near.'])
  FI.WriteDocContent(project, acknowledgments, ['Thanks to everyone.'])

  return {project: project, dedication: dedication, scene1: scene1,
    scene2: scene2, acknowledgments: acknowledgments}
enddef

def AllDocIds(fx: dict<any>): list<string>
  return [fx.dedication.id, fx.scene1.id, fx.scene2.id, fx.acknowledgments.id]
enddef

# The engines compile to a slug, because a TeX engine is unreliable with
# a path outside ASCII, and the artifact is renamed once the run has
# succeeded.
def Test_an_output_path_takes_the_name_of_its_target(): void
  assert_equal('/out/Über.pdf', C.FinalPath('/out/ber.pdf', 'Über', 'pdf'))
  assert_equal('/out/日本語.epub',
    C.FinalPath('/out/untitled.epub', '日本語', 'epub'))
  # The extension is given, never read back: the extension of /out/.pdf
  # is empty, and the name would end in the dot Windows forbids.
  assert_equal('/out/日本語.pdf', C.FinalPath('/out/.pdf', '日本語', 'pdf'))
  # A name the fold empties leaves the path as the engine wrote it.
  assert_equal('/out/untitled.pdf', C.FinalPath('/out/untitled.pdf', '***', 'pdf'))
  # A name that a file system reads as a device is guarded, as a
  # document's name is.
  assert_equal('/out/doc-Nul.pdf', C.FinalPath('/out/nul.pdf', 'Nul', 'pdf'))
enddef

# A target's identity is the name the writer gave it, and the file is
# only where that name's settings live. Two names that reduce to one
# slug once shared a file, so the second save destroyed the first.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/58
def Test_two_target_names_of_one_slug_are_two_targets(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: '日本語', kind: 'Book', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: '中文', kind: 'Manuscript', format: 'PDF'}))
  assert_equal(sort(['日本語', '中文']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, '日本語').format)
  assert_equal('PDF', C.LoadTarget(project, '中文').format)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_name_outside_ascii_does_not_take_the_file_of_another(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'Über', kind: 'Book', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'ber', kind: 'Manuscript', format: 'PDF'}))
  assert_equal(sort(['Über', 'ber']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, 'Über').format)
  assert_equal('PDF', C.LoadTarget(project, 'ber').format)
  FI.CleanupProjectFiles(project)
enddef

# Two names that differ only in case are two targets, because a name is
# the writer's own text and the picker shows both.
def Test_two_target_names_that_differ_only_in_case_are_two_targets(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'EPUB'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'draft', format: 'PDF'}))
  assert_equal(sort(['Draft', 'draft']), sort(C.ListTargets(project)))
  assert_equal('EPUB', C.LoadTarget(project, 'Draft').format)
  assert_equal('PDF', C.LoadTarget(project, 'draft').format)
  FI.CleanupProjectFiles(project)
enddef

# Saving a name that is already stored is an edit of that target, not a
# second one beside it.
def Test_saving_one_name_twice_edits_the_target(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', kind: 'Book'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', kind: 'Manuscript'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('Manuscript', C.LoadTarget(project, 'Draft').kind)
  FI.CleanupProjectFiles(project)
enddef

# The target deleted is the one saved second, which does not hold the
# plain slug path, so a delete that went by the slug would take the
# first target's file and leave the named one listed.
def Test_deleting_a_target_leaves_the_other_of_one_slug(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '日本語'}))
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '中文'}))
  C.DeleteTarget(project, '中文')
  assert_equal(['日本語'], C.ListTargets(project))
  assert_true(C.LoadTarget(project, '中文') is null_object)
  FI.CleanupProjectFiles(project)
enddef

# The working files of a compile carry the stem of the target's
# definition, which is unique per target, because every path built from
# the slug of the name was shared by two targets that reduce alike: the
# file the engine reads, the file it writes, and the prefix that the log
# retention trims by.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/60
def Test_two_targets_of_one_slug_work_under_different_names(): void
  var project = FI.BuildProject()
  var one = C.CompileTarget.FromDict({name: '日本語'})
  var two = C.CompileTarget.FromDict({name: '中文'})
  C.SaveTarget(project, one)
  C.SaveTarget(project, two)
  assert_notequal(C.WorkName(project, one), C.WorkName(project, two))
  assert_true(C.WorkName(project, one) !=# '', 'the first works under no name')
  FI.CleanupProjectFiles(project)
enddef

# A target whose name nothing else reduces to keeps working under its
# slug, so no path of an existing scrive moves.
def Test_a_target_of_its_own_slug_works_under_it(): void
  var project = FI.BuildProject()
  var target = C.CompileTarget.FromDict({name: 'Draft'})
  C.SaveTarget(project, target)
  assert_equal('draft', C.WorkName(project, target))
  FI.CleanupProjectFiles(project)
enddef

# A target that was never saved has no definition to take a stem from.
def Test_an_unsaved_target_works_under_its_slug(): void
  var project = FI.BuildProject()
  assert_equal('draft',
    C.WorkName(project, C.CompileTarget.FromDict({name: 'Draft'})))
  FI.CleanupProjectFiles(project)
enddef

# The slug of a very long name was longer than a path component holds,
# so the definition was never written, and the wizard compiled a target
# that had not been saved. The cap itself is pinned in test_slug.vim.
def Test_a_target_of_a_very_long_name_is_saved(): void
  var project = FI.BuildProject()
  var name: string = repeat('Chapter ', 40)
  var dir: string = project.scriveDir .. '/compile/targets'
  # With the measurements, because what fits is a question of where the
  # scrive sits, and a runner's answer is not this machine's.
  assert_true(C.SaveTarget(project, C.CompileTarget.FromDict({
    name: name, format: 'PDF'})),
    $'the folder is {strlen(dir)} bytes and leaves {C.PathRoom(dir)}')
  assert_equal([name], C.ListTargets(project))
  assert_equal('PDF', C.LoadTarget(project, name).format)
  FI.CleanupProjectFiles(project)
enddef

# The name of a definition is budgeted against the path that holds it,
# not only against the limit of one component: a name inside that limit,
# under a folder of ordinary depth, is still a path MS-Windows refuses,
# which is how the test above first failed there.
def Test_the_room_for_a_name_falls_as_its_folder_grows(): void
  var shallow: number = C.PathRoom('/s/compile/targets')
  var deep: number = C.PathRoom($'/s/{repeat("folder/", 20)}compile/targets')
  assert_true(deep < shallow, $'{deep} is no less than {shallow}')
  # It falls by exactly what the folder gained, its separator included.
  assert_equal(shallow - strlen($'{repeat("x", 40)}/'),
    C.PathRoom($'/s/{repeat("x", 40)}/compile/targets'))
enddef

# A compiled file is named after its target, so two names that reach one
# file shared one artifact: the compile of the second deleted the
# finished file of the first and renamed its own over it. Neither takes
# the name now, because nothing on disk says which target owns the file.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/64
def Test_two_targets_of_one_artifact_name_keep_the_engine_path(): void
  var project = FI.BuildProject()
  var outDir: string = project.scriveDir .. '/compile/output'
  var target = C.CompileTarget.FromDict({
    name: 'Draft:1', kind: 'Book', format: 'HTML'})
  C.SaveTarget(project, target)
  var outputPath: string = $'{outDir}/{C.WorkName(project, target)}.html'
  # Alone, it takes the name the writer typed.
  assert_equal($'{outDir}/Draft-1.html',
    C.ArtifactPath(project, target, outputPath, 'html'))
  # Draft/1 reaches the same file on every file system, because Safe
  # folds the separator and the colon alike.
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'Draft/1', kind: 'Book', format: 'HTML'}))
  var before: number = len(LM.History())
  assert_equal(outputPath, C.ArtifactPath(project, target, outputPath, 'html'))
  # The file both targets want, then the other target, then the file
  # kept, in that order, because the three read as one sentence. \C, so
  # that an ignorecase of the writer cannot level the two file names.
  var said: string = LM.History()[before :]
    ->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  assert_match('\CDraft-1\.html.*"Draft/1".*draft-1\.html', said)
  FI.CleanupProjectFiles(project)
enddef

# Two names of one Safe form compile to two files when the targets
# compile to different formats, so neither name is in question.
def Test_two_names_of_one_form_in_two_formats_keep_their_names(): void
  var project = FI.BuildProject()
  var outDir: string = project.scriveDir .. '/compile/output'
  var pdf = C.CompileTarget.FromDict({
    name: 'Novel (final)', kind: 'Book', format: 'PDF'})
  var epub = C.CompileTarget.FromDict({
    name: 'Novel final', kind: 'Book', format: 'EPUB'})
  C.SaveTarget(project, pdf)
  C.SaveTarget(project, epub)
  assert_equal($'{outDir}/Novel-final.pdf', C.ArtifactPath(project, pdf,
    $'{outDir}/{C.WorkName(project, pdf)}.pdf', 'pdf'))
  assert_equal($'{outDir}/Novel-final.epub', C.ArtifactPath(project, epub,
    $'{outDir}/{C.WorkName(project, epub)}.epub', 'epub'))
  FI.CleanupProjectFiles(project)
enddef

# A name that is a slug already reaches the file that the engine of
# another target writes, which is the stem of that target's definition.
# A rename onto it takes the output of a run that may still be writing.
def Test_the_working_file_of_another_target_is_not_taken(): void
  var project = FI.BuildProject()
  var outDir: string = project.scriveDir .. '/compile/output'
  var upper = C.CompileTarget.FromDict({
    name: 'Draft', kind: 'Book', format: 'HTML'})
  var lower = C.CompileTarget.FromDict({
    name: 'draft', kind: 'Book', format: 'HTML'})
  C.SaveTarget(project, upper)
  C.SaveTarget(project, lower)
  var outputPath: string = $'{outDir}/{C.WorkName(project, lower)}.html'
  var ignorecase: bool = &fileignorecase
  try
    # Where case folds, the two names are one file. Where it does not,
    # draft.html is still the file that the engine of Draft writes.
    &fileignorecase = false
    assert_equal(outputPath, C.ArtifactPath(project, lower, outputPath, 'html'))
  finally
    &fileignorecase = ignorecase
  endtry
  FI.CleanupProjectFiles(project)
enddef

# Whether two names of one case reach one file is a question of the file
# system, which fileignorecase answers, see Folded in path.vim.
def Test_two_names_of_one_case_share_a_file_where_case_folds(): void
  var project = FI.BuildProject()
  var outDir: string = project.scriveDir .. '/compile/output'
  var target = C.CompileTarget.FromDict({
    name: 'DRAFT', kind: 'Book', format: 'HTML'})
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'Draft', kind: 'Book', format: 'HTML'}))
  C.SaveTarget(project, target)
  var outputPath: string = $'{outDir}/{C.WorkName(project, target)}.html'
  var ignorecase: bool = &fileignorecase
  try
    &fileignorecase = true
    assert_equal(outputPath, C.ArtifactPath(project, target, outputPath, 'html'))
    &fileignorecase = false
    assert_equal($'{outDir}/DRAFT.html',
      C.ArtifactPath(project, target, outputPath, 'html'))
  finally
    &fileignorecase = ignorecase
  endtry
  FI.CleanupProjectFiles(project)
enddef

# Two names that differ only past what a name may hold reach one file
# once the cap has cut them, the route that saving a very long target
# opened.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/61
def Test_two_long_names_that_the_cap_levels_keep_the_engine_path(): void
  var project = FI.BuildProject()
  var outDir: string = project.scriveDir .. '/compile/output'
  var base: string = repeat('Chapter ', 40)
  var target = C.CompileTarget.FromDict({
    name: base .. 'Two', kind: 'Book', format: 'HTML'})
  C.SaveTarget(project, C.CompileTarget.FromDict({
    name: base .. 'One', kind: 'Book', format: 'HTML'}))
  C.SaveTarget(project, target)
  var outputPath: string = $'{outDir}/{C.WorkName(project, target)}.html'
  assert_equal(outputPath, C.ArtifactPath(project, target, outputPath, 'html'))
  FI.CleanupProjectFiles(project)
enddef

# The name of an artifact is budgeted against the path that holds it,
# not against the limit of one component alone, as the name of a
# definition is.
def Test_an_artifact_name_is_budgeted_against_its_folder(): void
  var dir: string = $'/s/{repeat("folder/", 120)}compile/output'
  var room: number = C.OutputRoom(dir, 'epub')
  var name: string = fnamemodify(
    C.FinalPath($'{dir}/draft.epub', repeat('Chapter ', 40), 'epub'), ':t:r')
  # With the measurements, because what fits is a question of where the
  # scrive sits, and a runner's answer is not this machine's.
  assert_true(strlen(name) <= max([room, 1]),
    $'the folder is {strlen(dir)} bytes and leaves {room}, '
      .. $'the name takes {strlen(name)}')
enddef

# The room an artifact leaves is passed to the name, never applied to
# the name afterwards: a cut after the edge strip and the device guard
# undoes them, and doc-Nul is four bytes over the room, which the
# margin of the path budget covers.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/67
def Test_an_artifact_name_cut_to_its_room_keeps_its_guards(): void
  var ext: string = 'pdf'
  # A folder that leaves three bytes, whichever limit the system has:
  # the room falls by every byte the folder gains.
  var dir: string = '/s' .. repeat('x', C.OutputRoom('/s', ext) - 3)
  assert_equal(3, C.OutputRoom(dir, ext))
  assert_equal('doc-Nul', fnamemodify(
    C.FinalPath($'{dir}/nullify.{ext}', 'Nullify', ext), ':t:r'))
  assert_equal('ab', fnamemodify(
    C.FinalPath($'{dir}/ab-cd.{ext}', 'ab-cd', ext), ':t:r'))
enddef

# The definition of a target is named through the same one cut, which
# is where the issue was reported: a target named Nullify under a
# folder that left three bytes took nul.json, the MS-Windows device.
# The room has to leave the prefix of the guard as well, or the write
# of the guarded name is the one that fails.
def Test_a_definition_cut_to_its_room_keeps_its_guard(): void
  # Resolved, because the temporary folder of macOS is a symlink and
  # the path the system measures is the one it points at, eight bytes
  # longer than the one a budget counts here.
  var root: string = resolve(tempname())
  var left: number = C.PathRoom($'{root}/compile/targets') - 3
  # A folder of that root leaves more than three bytes on any system
  # these tests run on, and asking the limit rather than the save keeps
  # a broken budget from skipping its own test.
  assert_true(left >= 2, $'{root} leaves {left} bytes to pad')
  var scriveDir: string = root
  while left > 101
    scriveDir ..= '/' .. repeat('x', 100)
    left -= 101
  endwhile
  scriveDir ..= '/' .. repeat('x', left - 1)
  var dir: string = $'{scriveDir}/compile/targets'
  mkdir(dir, 'p')
  assert_equal(3, C.PathRoom(dir))
  var project = PO.Project.new(scriveDir)
  # With the measurements, because what fits is a question of where the
  # scrive sits, and a runner's answer is not this machine's.
  assert_true(C.SaveTarget(project, C.CompileTarget.FromDict({
    name: 'Nullify', format: 'PDF'})),
    $'the folder is {strlen(dir)} bytes and leaves {C.PathRoom(dir)}')
  assert_equal(['doc-nul'], globpath(dir, '*.json', true, true)
    ->mapnew((_, f) => fnamemodify(f, ':t:r')))
  delete(root, 'rf')
enddef

# A save answers whether it wrote, so that nothing compiles a target
# that is not on disk.
def Test_a_save_answers_whether_it_wrote(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  var target = C.CompileTarget.FromDict({name: 'Draft'})
  assert_true(C.SaveTarget(project, target))
  mkdir(dir, 'p')
  # Through filewritable rather than a save, because a guard that asks
  # the function under test lets a broken one skip its own test.
  if setfperm(dir, 'r-xr-xr-x') == 0 || filewritable(dir) == 2
    setfperm(dir, 'rwxr-xr-x')
    FI.CleanupProjectFiles(project)
    return
  endif
  assert_false(C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Later'})))
  setfperm(dir, 'rwxr-xr-x')
  FI.CleanupProjectFiles(project)
enddef

# A log name holds the scrive and the target, and a path component
# holds 255 bytes. Unbudgeted, the two of them gave a name the system
# refused, so pandoc wrote no log and the compile failed with nothing
# from Bartleby to say why.
def Test_a_log_prefix_leaves_room_for_the_stamp(): void
  var prefix: string = C.LogPrefix($'/tmp/{repeat("Long ", 60)}.bartleby',
    repeat('x', 300))
  # The timestamp of a log name is 15 bytes, and the longest extension
  # written beside it, .json, is 5.
  assert_true(strlen(prefix) + 20 <= 255,
    $'{strlen(prefix)} bytes leaves no room for the stamp')
  # Neither name ends in the separator that a cut can land on, because
  # both are cut where the edges are stripped. Each title is one whose
  # cut lands on a fold.
  var work: string = C.LogPrefix('/tmp/one.bartleby', repeat('a-', 100))
  assert_notequal(SU.SEP, split(work, '_')[1][-1 : ])
  var folded: string = repeat('abc ', 100)
  var scrive: string = C.LogPrefix($'/tmp/{folded}.bartleby', 'x')
  assert_notequal(SU.SEP, split(scrive, '_')[0][-1 : ])
  # Both names still tell one scrive and one target from another.
  assert_notequal(C.LogPrefix('/tmp/one.bartleby', 'draft'),
    C.LogPrefix('/tmp/two.bartleby', 'draft'))
  assert_notequal(C.LogPrefix('/tmp/one.bartleby', 'draft'),
    C.LogPrefix('/tmp/one.bartleby', 'draft-2'))
enddef

# A save that failed must compile nothing, which is the complaint of
# the issue: the wizard ran the engine on a target that was not on disk.
def Test_a_failed_save_compiles_nothing(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir, 'p')
  # Through filewritable rather than a save, because a guard that asks
  # the function under test lets a broken one skip its own test.
  if setfperm(dir, 'r-xr-xr-x') == 0 || filewritable(dir) == 2
    setfperm(dir, 'rwxr-xr-x')
    FI.CleanupProjectFiles(project)
    return
  endif
  var before: number = len(LM.History())
  C.SaveAndRun(project, C.CompileTarget.FromDict({name: 'Doomed'}), null_object)
  var said: list<string> = LM.History()[before : ]->mapnew((_, m) => string(m))
  assert_equal(1, len(said->copy()->filter((_, l) => l =~# 'was not compiled')),
    'the writer was not told the target had not been saved')
  assert_equal([], said->copy()->filter((_, l) => l =~# 'compiling'),
    'an engine was started for a target that was not saved')
  setfperm(dir, 'rwxr-xr-x')
  FI.CleanupProjectFiles(project)
enddef

# Saving a name that another target carries replaces that target, and
# the wizard reads as additive when it renames one or makes a new one,
# so the writer is asked before the settings of the other are gone.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/59
def Test_a_new_target_of_a_name_in_use_replaces_it(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Keep'}))
  assert_true(C.Replaces(project, 'Keep', null_object))
  assert_false(C.Replaces(project, 'Fresh', null_object))
  FI.CleanupProjectFiles(project)
enddef

# The save that follows a yes: the renamed-from definition goes and the
# replaced target's own file takes the new settings, so one target of
# that name is left. Without the delete a rename would leave both.
def Test_a_save_over_another_target_leaves_one_of_the_name(): void
  var project = FI.BuildProject()
  var old = C.CompileTarget.FromDict({name: 'Old', format: 'EPUB'})
  C.SaveTarget(project, old)
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Keep', format: 'HTML'}))
  C.SaveOver(project, C.CompileTarget.FromDict({name: 'Keep', format: 'PDF'}), old)
  assert_equal(['Keep'], C.ListTargets(project))
  assert_equal('PDF', C.LoadTarget(project, 'Keep').format)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_target_saved_under_its_own_name_replaces_nothing(): void
  var project = FI.BuildProject()
  var keep = C.CompileTarget.FromDict({name: 'Keep'})
  C.SaveTarget(project, keep)
  assert_false(C.Replaces(project, 'Keep', keep))
  FI.CleanupProjectFiles(project)
enddef

def Test_a_rename_onto_the_name_of_another_target_replaces_it(): void
  var project = FI.BuildProject()
  var old = C.CompileTarget.FromDict({name: 'Old'})
  C.SaveTarget(project, old)
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Keep'}))
  assert_true(C.Replaces(project, 'Keep', old))
  assert_false(C.Replaces(project, 'Fresh', old))
  FI.CleanupProjectFiles(project)
enddef

# The order folds case, so a capital does not come before every small
# letter, as a comparison by byte would have it.
def Test_the_list_folds_case_in_its_order(): void
  var project = FI.BuildProject()
  for name in ['Zed', 'alpha']
    C.SaveTarget(project, C.CompileTarget.FromDict({name: name}))
  endfor
  assert_equal(['alpha', 'Zed'], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

# The order of the definition files is not the order of the names, and
# the list no longer follows it: the second of two names that reduce to
# one slug goes to a suffixed file, which a glob returns first.
def Test_the_list_does_not_follow_the_files(): void
  var project = FI.BuildProject()
  for name in ['中文', '日本語']
    C.SaveTarget(project, C.CompileTarget.FromDict({name: name}))
  endfor
  assert_equal(['中文', '日本語'], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

# Two names that differ only in case are two targets, and a folded
# comparison cannot tell them apart, so without an order of their own
# they would keep the order of their files, which is the fault itself.
def Test_two_names_of_one_folded_order_are_still_ordered(): void
  var project = FI.BuildProject()
  for name in ['Draft', 'draft']
    C.SaveTarget(project, C.CompileTarget.FromDict({name: name}))
  endfor
  assert_equal(['Draft', 'draft'], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Return how many warnings the log holds about two
# definitions of one name, so that a test counts its own.
def NameWarnings(): number
  return len(LM.History()
    ->mapnew((_, m) => string(m))
    ->filter((_, l) => l =~# 'two definitions'))
enddef

# Nothing in Bartleby writes a second definition of one name, but a sync
# conflict copy or a restored file does, and then the name no longer
# identifies one target: the list showed it twice and only the first was
# reachable.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/63
def Test_two_definitions_of_one_name_are_listed_once(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'EPUB'}))
  # As a sync client names a conflicted copy. Every separator one puts
  # before its suffix sorts below the dot of .json, so the copy is the
  # file the glob finds first and the writer acts on.
  writefile([json_encode({name: 'Draft', format: 'PDF'})],
    dir .. '/draft-copy.json')
  var before: number = NameWarnings()
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('PDF', C.LoadTarget(project, 'Draft').format)
  var said: list<string> = LM.History()->mapnew((_, m) => string(m))
    ->filter((_, l) => l =~# 'two files')
  assert_equal(before + 1, len(said), 'the copy was not reported')
  # The message names the file in use before the file left out, so that
  # moving one is not a surprise.
  assert_match('using draft-copy\.json, ignoring draft\.json', said[-1])
  FI.CleanupProjectFiles(project)
enddef

# A delete that removed nothing must not report that it did.
def Test_a_delete_answers_whether_it_removed_anything(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft'}))
  assert_true(C.DeleteTarget(project, 'Draft'))
  assert_false(C.DeleteTarget(project, 'Draft'))
  assert_false(C.DeleteTarget(project, 'Never saved'))
  FI.CleanupProjectFiles(project)
enddef

# The second file is reachable again once the first is gone, so nothing
# the writer holds is lost by leaving it out of the list.
def Test_the_second_definition_is_listed_once_the_first_goes(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'EPUB'}))
  writefile(readfile(dir .. '/draft.json'), dir .. '/draft-copy.json')
  delete(dir .. '/draft.json')
  var before: number = NameWarnings()
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('EPUB', C.LoadTarget(project, 'Draft').format)
  assert_equal(before, NameWarnings(), 'one file was still reported as two')
  FI.CleanupProjectFiles(project)
enddef

# A name that two files carry survives the deletion of the one in use,
# with the settings of the other, which is the fault the issue reports.
# The writer is told rather than left to find it.
def Test_deleting_one_of_two_files_of_a_name_says_it_is_still_in_use(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'EPUB'}))
  writefile([json_encode({name: 'Draft', format: 'PDF'})],
    dir .. '/draft-copy.json')
  var before: number = len(LM.History()
    ->mapnew((_, m) => string(m))->filter((_, l) => l =~# 'still carries'))
  assert_true(C.DeleteTarget(project, 'Draft'))
  assert_equal(before + 1, len(LM.History()
    ->mapnew((_, m) => string(m))->filter((_, l) => l =~# 'still carries')),
    'the surviving file was not reported')
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('EPUB', C.LoadTarget(project, 'Draft').format)
  FI.CleanupProjectFiles(project)
enddef

# A definition the writer cannot unlink is not a name nothing carried,
# and the writer was told the target was not there either way.
def Test_a_delete_that_cannot_remove_the_file_says_so(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Locked'}))
  if setfperm(dir, 'r-xr-xr-x') == 0 || delete(dir .. '/locked.json') == 0
    # A folder this writer can still write to, or one that cannot be
    # made read-only, proves nothing here.
    setfperm(dir, 'rwxr-xr-x')
    FI.CleanupProjectFiles(project)
    return
  endif
  var before: number = len(LM.History()
    ->mapnew((_, m) => string(m))->filter((_, l) => l =~# 'could not delete'))
  assert_false(C.DeleteTarget(project, 'Locked'))
  assert_equal(before + 1, len(LM.History()
    ->mapnew((_, m) => string(m))->filter((_, l) => l =~# 'could not delete')),
    'the file that stayed was not reported')
  setfperm(dir, 'rwxr-xr-x')
  FI.CleanupProjectFiles(project)
enddef

# A damaged definition decodes to nothing, so it carries no name. It
# must not reach the picker as a blank entry that Run would compile, as
# it did when a definition was found by the slug of the name asked for.
def Test_a_damaged_definition_is_no_target(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir, 'p')
  writefile(['{not json'], dir .. '/broken.json')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_true(C.LoadTarget(project, '') is null_object)
  FI.CleanupProjectFiles(project)
enddef

# A free path is one that nothing holds, not one that can be read: a
# folder of that name holds it too, and a save that called it free wrote
# nowhere.
def Test_a_path_that_a_folder_holds_is_not_free(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir .. '/draft.json', 'p')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft', format: 'PDF'}))
  assert_equal(['Draft'], C.ListTargets(project))
  assert_equal('PDF', C.LoadTarget(project, 'Draft').format)
  FI.CleanupProjectFiles(project)
enddef

# A scrive written before this change holds its definitions at the plain
# slug of each name, which is where a target of one name still goes.
def Test_a_definition_at_the_plain_slug_path_is_still_the_target(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  mkdir(dir, 'p')
  writefile([json_encode({name: 'Legacy', kind: 'Book', format: 'EPUB'})],
    dir .. '/legacy.json')
  assert_equal('EPUB', C.LoadTarget(project, 'Legacy').format)
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Legacy', format: 'PDF'}))
  assert_equal(['legacy.json'],
    glob(dir .. '/*.json', true, true)->mapnew((_, f) => fnamemodify(f, ':t')))
  assert_equal('PDF', C.LoadTarget(project, 'Legacy').format)
  C.DeleteTarget(project, 'Legacy')
  assert_equal([], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

# Renaming a target is a delete of the old name and a save of the new,
# see the submit of the wizard, which must leave one file.
def Test_renaming_a_target_leaves_no_file_at_the_old_name(): void
  var project = FI.BuildProject()
  var dir: string = project.scriveDir .. '/compile/targets'
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Old', format: 'EPUB'}))
  C.DeleteTarget(project, 'Old')
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'New', format: 'PDF'}))
  assert_equal(['New'], C.ListTargets(project))
  assert_equal(1, len(glob(dir .. '/*.json', true, true)))
  FI.CleanupProjectFiles(project)
enddef

# The slug of a name in a script of its own is empty, so the definition
# was saved as .json, which the *.json glob never returned, and the
# target vanished as soon as it was saved.
def Test_a_target_name_that_slugs_to_nothing_is_still_listed(): void
  var project = FI.BuildProject()
  C.SaveTarget(project, C.CompileTarget.FromDict({name: '日本語'}))
  assert_equal(['日本語'], C.ListTargets(project))
  FI.CleanupProjectFiles(project)
enddef

def Test_a_target_is_listed_while_wildignore_names_its_extension(): void
  var project = FI.BuildProject()
  # FromDict, as the other tests build one: a class member is not
  # writable from outside the class.
  C.SaveTarget(project, C.CompileTarget.FromDict({name: 'Draft'}))
  var saved: string = &wildignore
  set wildignore+=*.json
  try
    assert_equal(['Draft'], C.ListTargets(project))
  finally
    &wildignore = saved
  endtry
  FI.CleanupProjectFiles(project)
enddef

def Test_concatenate_manuscript_full_structure(): void
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: AllDocIds(fx)})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal([
    '# Dedication {-}', '', 'For my family.', '',
    '# 1', '', 'It was a dark and stormy night.', '',
    '# 2', '', 'The end was near.', '',
    '# Acknowledgments {-}', '', 'Thanks to everyone.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_respects_content_selection(): void
  var fx = BuildProjectWithContent()
  # Only the Dedication is included. Manuscript and Back Matter are not.
  var target = C.CompileTarget.FromDict({includedIds: [fx.dedication.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal(['# Dedication {-}', '', 'For my family.'], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter(): void
  var fx = BuildProjectWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  var scene1b = BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md')
  chapter1.AddChild(scene1b)
  FI.WriteDocContent(fx.project, scene1b, ['Morning came.'])

  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, scene1b.id]})
  var lines = C.ConcatenateManuscript(fx.project, target)
  # Neither scene has a heading, so the separator between them is the scene
  # break itself, not left out as it is before a chapter heading.
  assert_equal([
    '# 1', '', 'It was a dark and stormy night.', '', '* * *', '', 'Morning came.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_manuscript_with_nothing_included_is_empty(): void
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: []})
  var lines = C.ConcatenateManuscript(fx.project, target)
  assert_equal([], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter(): void
  # This exact match also guards against a real bug: the outer join of
  # ConcatenateBook once used target.separator between these three blocks,
  # which put a stray scene break around the frontmatter, mainmatter, and
  # backmatter commands. Those are LaTeX transitions, not scene breaks.
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({includedIds: AllDocIds(fx)})
  var lines = C.ConcatenateBook(fx.project, target)
  assert_equal([
    '```{=latex}', '\frontmatter', '```', '',
    '# Dedication {-}', '', 'For my family.', '',
    '```{=latex}', '\mainmatter', '```', '',
    '# 1', '', 'It was a dark and stormy night.', '',
    '# 2', '', 'The end was near.', '',
    '```{=latex}', '\backmatter', '```', '',
    '# Acknowledgments {-}', '', 'Thanks to everyone.',
  ], lines)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_concatenate_book_omits_mainmatter_when_front_matter_not_included(): void
  var fx = BuildProjectWithContent()
  # The Dedication is excluded, so Front Matter adds nothing.
  var target = C.CompileTarget.FromDict({includedIds: [fx.scene1.id, fx.scene2.id]})
  var lines = C.ConcatenateBook(fx.project, target)
  assert_equal(-1, index(lines, '\frontmatter'))
  assert_equal(-1, index(lines, '\mainmatter'))
  # The Manuscript text is still present, without a wrapper.
  assert_true(index(lines, '# 1') >= 0)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_a_cover_path_from_home_is_expanded(): void
  assert_equal($HOME .. '/covers/book.png', C.CoverPath('~/covers/book.png'))
  assert_equal('', C.CoverPath(''))
enddef

# FUNCTION: expand() would read cover[1].png as a pattern and return
# cover1.png, a different file, when both exist.
def Test_a_cover_path_is_never_read_as_a_pattern(): void
  var dir: string = FI.TempPath()
  mkdir(dir, 'p')
  writefile([], dir .. '/cover1.png')
  writefile([], dir .. '/cover[1].png')
  var cwd: string = getcwd()
  execute 'cd ' .. fnameescape(dir)
  var got: string = C.CoverPath('cover[1].png')
  execute 'cd ' .. fnameescape(cwd)
  delete(dir, 'rf')
  # Through Canon, because Vim answers with the separator and the long
  # name of its own system, and the name is what this test is about.
  assert_equal(PA.Canon(dir .. '/cover[1].png'), PA.Canon(got))
enddef

# FUNCTION: A Book with a cover image that does not exist stops with an
# error that names the path, before Pandoc runs.
def Test_a_missing_cover_image_stops_the_compile(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'NoCover', kind: 'Book', format: 'PDF',
    includedIds: [scene.id], coverImage: '/no/such/folder/cover.png'})
  var before: number = len(LM.History())
  C.Execute(project, target)
  var logged: string = LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  # CoverPath makes the path absolute, and on Windows that means a drive
  # and backslashes, so the pattern comes from the path itself.
  assert_match($'cover image not found: {escape(C.CoverPath("/no/such/folder/cover.png"), "\\.*$^~[]")}',
    logged)
  assert_notmatch('compiling "NoCover"', logged)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: HTML and Markdown leave the cover out, so a missing cover image
# does not stop them.
def Test_a_missing_cover_does_not_stop_a_format_without_one(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'HtmlNoCover', kind: 'Book', format: 'HTML',
    includedIds: [scene.id], coverImage: '/no/such/folder/cover.png'})
  var before: number = len(LM.History())
  C.Execute(project, target)
  var logged: string = LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  assert_notmatch('cover image not found', logged)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Compile a Manuscript PDF with stand-in programs, that kpsewhich
# finds only the files of found and that the programs of others exist, and
# return what was logged.
def CompileWithStubs(found: list<string>, others: list<string>): string
  var dir: string = TTX.Stubs(found, false, others)
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var target = C.CompileTarget.FromDict({name: 'TexCheck', kind: 'Manuscript', format: 'PDF',
    includedIds: [scene.id]})
  var before: number = len(LM.History())
  TTX.UsePath(dir)
  C.Execute(project, target)
  TTX.RestorePath()
  FI.CleanupProjectFiles(project)
  delete(dir, 'rf')
  return LM.History()[before :]->mapnew((_, m) => join(m.lines, ' '))->join(' ')
enddef

# FUNCTION: The point of the check: name the missing package before LaTeX
# runs, instead of a LaTeX error in the failure log.
def Test_a_missing_tex_package_stops_a_pdf_compile(): void
  var logged: string = CompileWithStubs(['sffms.cls', 'hyperref.sty'], ['pandoc', 'pdflatex'])
  assert_match('needs TeX files that are not installed: .*ulem\.sty', logged)
  assert_notmatch('compiling "TexCheck"', logged)
enddef

def Test_a_missing_tex_engine_stops_a_pdf_compile(): void
  var logged: string = CompileWithStubs([], ['pandoc'])
  assert_match('pdflatex not found', logged)
  assert_notmatch('compiling "TexCheck"', logged)
enddef

# FUNCTION: An unknown line style is single, an unknown header bold, and
# small caps bold in a Manuscript, whose typewriter font has none.
def Test_table_options_fall_back(): void
  assert_equal({border: 'none', vlines: 'single', header: 'italic'}, C.TableOpts('Book', 'none', 'single', 'italic'))
  assert_equal({border: 'single', vlines: 'single', header: 'bold'}, C.TableOpts('Book', 'double', 'dotted', 'shouting'))
  assert_equal('smallcaps', C.TableOpts('Book', 'none', 'none', 'smallcaps').header)
  assert_equal('bold', C.TableOpts('Manuscript', 'none', 'none', 'smallcaps').header)
  assert_equal('plain', C.TableOpts('Manuscript', 'none', 'none', 'plain').header)
enddef

def Test_table_css_draws_only_the_lines_asked_for(): void
  assert_equal([], C.TableCss({border: 'none', vlines: 'none', header: 'bold'}))
  var border: list<string> = C.TableCss({border: 'single', vlines: 'none', header: 'bold'})
  assert_equal(1, len(border))
  assert_match('^table {', border[0])
  var both: list<string> = C.TableCss({border: 'single', vlines: 'single', header: 'bold'})
  assert_equal(2, len(both))
  assert_match('border-left', both[1])
enddef

export def RunAll(): void
  Test_table_options_fall_back()
  Test_table_css_draws_only_the_lines_asked_for()
  Test_a_missing_tex_package_stops_a_pdf_compile()
  Test_a_missing_tex_engine_stops_a_pdf_compile()
  Test_a_cover_path_from_home_is_expanded()
  Test_a_cover_path_is_never_read_as_a_pattern()
  Test_a_missing_cover_image_stops_the_compile()
  Test_a_missing_cover_does_not_stop_a_format_without_one()
  Test_an_output_path_takes_the_name_of_its_target()
  Test_a_target_of_a_very_long_name_is_saved()
  Test_the_room_for_a_name_falls_as_its_folder_grows()
  Test_two_targets_of_one_artifact_name_keep_the_engine_path()
  Test_two_names_of_one_case_share_a_file_where_case_folds()
  Test_two_long_names_that_the_cap_levels_keep_the_engine_path()
  Test_an_artifact_name_is_budgeted_against_its_folder()
  Test_an_artifact_name_cut_to_its_room_keeps_its_guards()
  Test_two_names_of_one_form_in_two_formats_keep_their_names()
  Test_the_working_file_of_another_target_is_not_taken()
  Test_a_definition_cut_to_its_room_keeps_its_guard()
  Test_a_save_answers_whether_it_wrote()
  Test_a_log_prefix_leaves_room_for_the_stamp()
  Test_a_failed_save_compiles_nothing()
  Test_a_new_target_of_a_name_in_use_replaces_it()
  Test_a_save_over_another_target_leaves_one_of_the_name()
  Test_a_target_saved_under_its_own_name_replaces_nothing()
  Test_a_rename_onto_the_name_of_another_target_replaces_it()
  Test_the_list_folds_case_in_its_order()
  Test_the_list_does_not_follow_the_files()
  Test_two_names_of_one_folded_order_are_still_ordered()
  Test_two_definitions_of_one_name_are_listed_once()
  Test_a_delete_answers_whether_it_removed_anything()
  Test_the_second_definition_is_listed_once_the_first_goes()
  Test_deleting_one_of_two_files_of_a_name_says_it_is_still_in_use()
  Test_a_delete_that_cannot_remove_the_file_says_so()
  Test_two_target_names_of_one_slug_are_two_targets()
  Test_a_name_outside_ascii_does_not_take_the_file_of_another()
  Test_two_target_names_that_differ_only_in_case_are_two_targets()
  Test_saving_one_name_twice_edits_the_target()
  Test_deleting_a_target_leaves_the_other_of_one_slug()
  Test_two_targets_of_one_slug_work_under_different_names()
  Test_a_target_of_its_own_slug_works_under_it()
  Test_an_unsaved_target_works_under_its_slug()
  Test_a_damaged_definition_is_no_target()
  Test_a_path_that_a_folder_holds_is_not_free()
  Test_a_definition_at_the_plain_slug_path_is_still_the_target()
  Test_renaming_a_target_leaves_no_file_at_the_old_name()
  Test_a_target_name_that_slugs_to_nothing_is_still_listed()
  Test_a_target_is_listed_while_wildignore_names_its_extension()
  Test_concatenate_manuscript_full_structure()
  Test_concatenate_manuscript_respects_content_selection()
  Test_concatenate_manuscript_separator_appears_between_scenes_in_same_chapter()
  Test_concatenate_manuscript_with_nothing_included_is_empty()
  Test_concatenate_book_wraps_frontmatter_mainmatter_backmatter()
  Test_concatenate_book_omits_mainmatter_when_front_matter_not_included()
enddef
