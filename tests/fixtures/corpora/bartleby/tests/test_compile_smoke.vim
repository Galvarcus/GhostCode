vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_compile_smoke.vim: a gated smoke test of the real compile
# pipeline. Checks that Pandoc, pdflatex, and xelatex run to the end and
# write a real, nonempty file. It does not check how the output looks,
# which is left to manual checks, see testing_feasibility_report.md. When
# a program is not installed, the test is skipped with exit code 0
# instead of failing for an unrelated reason. The compile-smoke job of
# ci.yml installs the programs.
#
# job_start is asynchronous, so the test polls for the output file
# instead of waiting for a return value. On success RunJob asks whether
# to open the result, in a popup from dialog_popup.vim. The popup does
# not wait for an answer, so the test never hangs.
#
# Usage: the same command as tests/harness.vim, see its header.
# License: GNU GPL 3.0
##############################################################################
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/project.vim' as PO
import './fixtures.vim' as FI
import './report.vim' as RE
import 'Logger/messages.vim' as LM

# The table filter, for the tests that run it by itself.
const TABLES_FILTER: string = expand('<sfile>:p:h:h') .. '/tools/pandoc/tables.lua'
# This file, read by the test of the one definition of the font. A Vim9
# function cannot expand <sfile>, see E1245.
const SUITE: string = expand('<sfile>:p')

# How long a test waits for a compile. A minute was not enough on a
# Windows runner: the Manuscript PDF timed out in runs 40784691668 and
# 40810002585 while the Book PDF compiled, no log of the run was written,
# which Bartleby does only once a compile ends, and no engine or pandoc
# message reported a fault. The same configuration passed both PDFs in
# other runs, so the compile is slow there rather than broken.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/45
const RESULT: string = 'tests/smoke_results.txt'
const PASS: string = 'All smoke tests passed'
const MAX_WAIT_MS: number = 180000

# The content that a recompile must replace, see the rename test.
const STALE: string = 'stale'
const POLL_INTERVAL_MS: number = 500

# FUNCTION: Wait for a file matching pattern in the output folder,
# project.scriveDir/compile/output, with a size above 0, up to
# MAX_WAIT_MS. Return its path, or an empty string after the wait.
def WaitForOutput(project: PO.Project, pattern: string): string
  var outDir: string = project.scriveDir .. '/compile/output'
  var waited: number = 0
  while waited < MAX_WAIT_MS
    var matches: list<string> = glob(outDir .. '/' .. pattern, false, true)
      ->filter((_, f) => getfsize(f) > 0)
    if !empty(matches)
      return matches[0]
    endif
    execute $'sleep {POLL_INTERVAL_MS}m'
    waited += POLL_INTERVAL_MS
  endwhile
  return ''
enddef

# FUNCTION: Remove the files of project, for a defer, which takes the
# name of a function and raises E129 on the imported name.
def Cleanup(project: PO.Project): void
  FI.CleanupProjectFiles(project)
enddef

def BuildProjectWithContent(): dict<any>
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  # A table with a caption and one without, so that every smoke compile
  # checks that the templates load what tables need, see tools/latex.
  FI.WriteDocContent(project, scene1, ['It was a dark and stormy night.', '',
    '| Name | Age |', '| :--- | --: |', '| Mara |  34 |', '', 'Table: The crew', '',
    '| Ship | Port |', '| ---- | ---- |', '| Wren | Hull |'])
  return {project: project, scene1: scene1}
enddef

def Test_manuscript_pdf_compiles_to_a_real_nonempty_file(): void
  if !executable('pandoc') || !executable('pdflatex')
    echom 'SKIP: pandoc/pdflatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'SmokeManuscript', kind: 'Manuscript', format: 'PDF',
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.pdf')
  assert_true(outputPath !=# '', 'Manuscript PDF did not appear within ' .. MAX_WAIT_MS .. 'ms')
enddef

# The family that the Book compiles with has one definition, in
# fixtures.vim, because the compile leg of CI reads it too: a check that
# names a font of its own would pass while the suite asked for another.
def Test_the_font_of_the_fixture_has_one_definition(): void
  assert_equal('DejaVu Serif', FI.SMOKE_FONT)
  # No target of this suite names the family itself, so the check of the
  # compile leg and the suite cannot ask for two different fonts.
  assert_equal([], readfile(SUITE)
    ->filter((_, l) => l =~# $"font: '{FI.SMOKE_FONT}'"))
enddef

def Test_book_pdf_compiles_to_a_real_nonempty_file(): void
  if !executable('pandoc') || !executable('xelatex')
    echom 'SKIP: pandoc/xelatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'SmokeBook', kind: 'Book', format: 'PDF', font: FI.SMOKE_FONT,
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.pdf')
  assert_true(outputPath !=# '', 'Book PDF did not appear within ' .. MAX_WAIT_MS .. 'ms')
enddef

# FUNCTION: Wait until logDir has a log whose name is not in before, and
# return it, or an empty string after MAX_WAIT_MS. Pandoc writes its log
# file when it ends, so a new name means that run is done.
def WaitForNewLog(logDir: string, before: list<string>): string
  var waited: number = 0
  while waited < MAX_WAIT_MS
    for path in glob(logDir .. '/*.json', false, true)
      if index(before, path) < 0
        return path
      endif
    endfor
    execute $'sleep {POLL_INTERVAL_MS}m'
    waited += POLL_INTERVAL_MS
  endwhile
  return ''
enddef

# FUNCTION: Run three Book compiles to HTML, with Pandoc only and no
# LaTeX, with g:bartleby_compile_log_retention set to 2 at the end of
# this file, before Bartleby loads. Each run must write a new timestamped
# JSON log, and only the 2 newest may remain.
def Test_pandoc_log_per_run_with_retention(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'Smoke Log', kind: 'Book', format: 'HTML', includedIds: [fx.scene1.id],
  })
  var logDir: string = expand('~/.bartleby/logs')
  for run in range(3)
    var before: list<string> = glob(logDir .. '/*.json', false, true)
    C.Execute(fx.project, target)
    var newLog: string = WaitForNewLog(logDir, before)
    assert_true(newLog !=# '', $'run {run + 1} wrote no log within {MAX_WAIT_MS}ms')
    if newLog !=# ''
      # Either separator, because the path of a Windows runner holds the
      # backslash and fnamemodify splits only the one of its own platform.
      assert_match('[\/]bartleby-test-fixture_smoke-log_\d\{8}-\d\{6}\.json$', newLog)
      assert_equal(v:t_list, type(json_decode(join(readfile(newLog), "\n"))))
    endif
    # Log names show the time to the second.
    sleep 1100m
  endfor
  # Only this target's logs: the other smoke tests write logs here too.
  assert_equal(2, len(glob(logDir .. '/bartleby-test-fixture_smoke-log_*.json', false, true)))
enddef

# FUNCTION: A Book PDF with a font that does not exist, so xelatex fails.
# Pandoc writes no log on failure, so Bartleby must write a .log file with
# the error output, and ask whether to open it.
def Test_failure_writes_a_log_and_asks_to_open_it(): void
  if !executable('pandoc') || !executable('xelatex')
    echom 'SKIP: pandoc/xelatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'Smoke Fail', kind: 'Book', format: 'PDF', font: 'No Such Font Xyzzy',
    includedIds: [fx.scene1.id],
  })
  var logDir: string = expand('~/.bartleby/logs')
  C.Execute(fx.project, target)
  var failLog: string = ''
  var waited: number = 0
  while failLog ==# '' && waited < MAX_WAIT_MS
    sleep 500m
    waited += 500
    failLog = get(glob(logDir .. '/bartleby-test-fixture_smoke-fail_*.log', false, true), 0, '')
  endwhile
  assert_true(failLog !=# '', 'no failure log within ' .. MAX_WAIT_MS .. 'ms')
  if failLog !=# ''
    var text: list<string> = readfile(failLog)
    assert_match('^Command: pandoc', text[0])
    assert_match('^Exit status: [1-9]', text[1])
    assert_true(len(text) > 3, 'the failure log has no error output')
  endif
  var questions = popup_list()->filter((_, id) => join(getbufline(winbufnr(id), 1, '$')) =~# 'failed')
  assert_equal(1, len(questions), 'no question to open the log')
  for id in popup_list()
    popup_close(id)
  endfor
enddef

# FUNCTION: Run tools/pandoc/tables.lua on md, to the format to, with the
# metadata meta, and return what Pandoc writes.
def Filter(md: list<string>, to: string, meta: list<string>): string
  var src: string = tempname()
  writefile(md, src)
  var out: string = system(join(['pandoc', shellescape(src), '-t', to,
    '--lua-filter=' .. shellescape(TABLES_FILTER)] + meta->mapnew((_, m) => '-M ' .. shellescape(m))))
  delete(src)
  return out
enddef

# FUNCTION: A real compile passes the table settings on: the header style
# through the filter, and the lines through the override CSS.
def Test_book_html_tables_get_the_settings(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'SmokeTables', kind: 'Book', format: 'HTML',
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.html')
  assert_true(outputPath !=# '', 'Book HTML did not appear within ' .. MAX_WAIT_MS .. 'ms')
  if outputPath !=# ''
    var html: string = join(readfile(outputPath), "\n")
    assert_match('<th[^>]*><em>Name</em></th>', html)
    var css: string = join(readfile(fnamemodify(outputPath, ':h') .. '/.override.css'), "\n")
    assert_match('table { border:', css)
    assert_match('border-left', css)
  endif
enddef

def Test_the_table_filter_draws_lines_only_when_asked(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var md: list<string> = ['| Name | Age |', '|:--|--:|', '| Mara | 34 |']
  var both: string = Filter(md, 'latex', ['table-border=single', 'table-vlines=single'])
  assert_match('\\begin{longtable}\[\]{|l|r|}', both)
  assert_notmatch('\\toprule', both)
  assert_match('{@{}l|r@{}}', Filter(md, 'latex', ['table-vlines=single']))
  var none: string = Filter(md, 'latex', [])
  assert_match('{@{}lr@{}}', none)
  assert_match('\\toprule', none)
enddef

def Test_the_table_filter_styles_the_header(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var md: list<string> = ['| Name | Age |', '|:--|--:|', '| Mara | 34 |']
  assert_match('\\textbf{Name}', Filter(md, 'latex', []))
  assert_match('\\emph{Name}', Filter(md, 'latex', ['table-header=italic']))
  assert_match('<span class="smallcaps">Name</span>', Filter(md, 'html', ['table-header=smallcaps']))
  assert_notmatch('<strong>', Filter(md, 'html', ['table-header=plain']))
enddef

# FUNCTION: The rules take their width from the columns, so that a table of
# long cells is no wider than the text.
def Test_the_table_filter_keeps_the_width_with_rules(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var long: string = repeat('a long note about the voyage north ', 6)
  var md: list<string> = ['| Name | Notes |', '|:--|:--|', $'| Mara | {long} |']
  var tex: string = Filter(md, 'latex', ['table-border=single', 'table-vlines=single'])
  assert_match('\\\%(line\|column\)width - 4\\tabcolsep - 3\\arrayrulewidth', tex)
enddef

# FUNCTION: Return how many compiles the log says were refused, so that
# a test can count its own rather than every suite's.
def Refusals(): number
  return len(LM.History()
    ->mapnew((_, m) => string(m))
    ->filter((_, l) => l =~# 'already compiling'))
enddef

# Two targets whose names reduce to one slug once shared every working
# path of a compile: the file the engine reads, the file it writes, and
# the prefix the log retention trims by. Each now works under the stem
# of its own definition. The two run at once, which is the state the
# issue reports.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/60
def Test_two_targets_of_one_slug_keep_their_own_working_files(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var outDir: string = fx.project.scriveDir .. '/compile/output'
  var names: list<string> = ['日本語', '中文']
  var before: number = Refusals()
  for name in names
    var target = C.CompileTarget.FromDict({
      name: name, kind: 'Book', format: 'HTML', includedIds: [fx.scene1.id],
    })
    C.SaveTarget(fx.project, target)
    C.Execute(fx.project, target)
  endfor
  for name in names
    assert_true(WaitForOutput(fx.project, name .. '.html') !=# '',
      $'no {name}.html within {MAX_WAIT_MS}ms')
  endfor
  # Neither run was refused, so the two held different keys.
  assert_equal(before, Refusals())
  # One intermediate source per target, and one artifact each.
  assert_equal(2, len(glob(outDir .. '/.*-src.md', true, true)),
    'the two targets shared an intermediate source')
  assert_equal(names->copy()->sort()->mapnew((_, n) => n .. '.html'),
    glob(outDir .. '/*.html', true, true)
      ->mapnew((_, f) => fnamemodify(f, ':t'))->sort())
enddef

# A second run of one target would rewrite the file its engine is still
# reading, so it is refused while the first runs, and allowed once that
# run has ended.
def Test_a_second_compile_of_one_target_waits_for_the_first(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'Twice', kind: 'Book', format: 'HTML', includedIds: [fx.scene1.id],
  })
  C.SaveTarget(fx.project, target)
  var before: number = Refusals()
  C.Execute(fx.project, target)
  C.Execute(fx.project, target)
  assert_equal(before + 1, Refusals(), 'the second run was not refused once')
  var outputPath: string = WaitForOutput(fx.project, 'Twice.html')
  assert_true(outputPath !=# '', $'no Twice.html within {MAX_WAIT_MS}ms')

  # The key is released when the job ends, or the target could never be
  # compiled again in this session.
  writefile([STALE], outputPath)
  C.Execute(fx.project, target)
  assert_equal(before + 1, Refusals(), 'the run after the first was refused')
  var waited: number = 0
  while waited < MAX_WAIT_MS && FirstLine(outputPath) ==# STALE
    execute $'sleep {POLL_INTERVAL_MS}m'
    waited += POLL_INTERVAL_MS
  endwhile
  assert_notequal(STALE, FirstLine(outputPath),
    $'the second run wrote nothing within {MAX_WAIT_MS}ms')
enddef

# A rename frees the stem of a target's definition, and the renamed
# target takes it back, so the key of a running compile cannot be the
# name of its target.
def Test_a_rename_during_a_compile_cannot_take_its_working_files(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var one = C.CompileTarget.FromDict({
    name: '日本語', kind: 'Book', format: 'HTML',
    includedIds: [fx.scene1.id],
  })
  C.SaveTarget(fx.project, one)
  var work: string = C.WorkName(fx.project, one)
  var before: number = Refusals()
  C.Execute(fx.project, one)
  # The rename of the wizard: the old definition goes, the new one takes
  # the path it freed.
  C.DeleteTarget(fx.project, '日本語')
  var two = C.CompileTarget.FromDict({
    name: '中文', kind: 'Book', format: 'HTML',
    includedIds: [fx.scene1.id],
  })
  C.SaveTarget(fx.project, two)
  assert_equal(work, C.WorkName(fx.project, two),
    'the renamed target did not take the stem back')
  C.Execute(fx.project, two)
  assert_equal(before + 1, Refusals(), 'the renamed target was not refused')
  assert_true(WaitForOutput(fx.project, '日本語.html') !=# '',
    $'the first run left no artifact within {MAX_WAIT_MS}ms')
enddef

# The Markdown format writes its output itself, with no engine and no
# job, so it is the one route to the rename that needs no program. It
# lives here rather than in test_compile.vim because the offer to open
# the output takes yes as its default, and the tab it opens would reach
# the next suite of the harness as the file the writer is in.
def Test_a_markdown_output_is_written_under_the_name_of_its_target(): void
  var project = FI.BuildProject()
  defer Cleanup(project)
  var target = C.CompileTarget.FromDict({
    name: 'Über Draft', kind: 'Book', format: 'Markdown', includedIds: [],
  })
  C.Execute(project, target)
  var outDir: string = project.scriveDir .. '/compile/output'
  assert_equal(['Über-Draft.md'],
    glob(outDir .. '/*.md', true, true)->mapnew((_, f) => fnamemodify(f, ':t')))
enddef

# FUNCTION: Return the first line of path, or an empty string when there
# is no file to read.
def FirstLine(path: string): string
  return filereadable(path) ? get(readfile(path), 0, '') : ''
enddef

# FUNCTION: Return the whole of path as one line, or an empty string
# when there is no file to read: the fault that this test guards takes
# the file away, and a read of it would throw E484 rather than fail the
# assertion the test means to make.
def Text(path: string): string
  return filereadable(path) ? join(readfile(path), ' ') : ''
enddef

# A compiled file takes the name of its target, so two targets whose
# names reach one file took one name: the compile of the second deleted
# the finished file of the first. Markdown, because it writes its own
# output with no engine, so each compile is done when Execute returns.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/64
def Test_two_targets_of_one_artifact_name_keep_their_own_files(): void
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var scene2 = fx.project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(fx.project, scene2, ['The end was near.'])
  var outDir: string = fx.project.scriveDir .. '/compile/output'
  for [name, id] in [['Draft:1', fx.scene1.id], ['Draft/1', scene2.id]]
    var target = C.CompileTarget.FromDict({
      name: name, kind: 'Book', format: 'Markdown', includedIds: [id],
    })
    C.SaveTarget(fx.project, target)
    C.Execute(fx.project, target)
  endfor
  # One file for each target: the first took the shared name while it was
  # the only target of it, and the second, which cannot tell that file
  # from one of its own, left it alone and kept the name of its
  # definition.
  assert_equal(['Draft-1.md', 'draft-1-2.md'],
    glob(outDir .. '/*.md', true, true)
      ->mapnew((_, f) => fnamemodify(f, ':t'))->sort())
  assert_match('dark and stormy', Text($'{outDir}/Draft-1.md'))
  assert_match('end was near', Text($'{outDir}/draft-1-2.md'))
enddef

# The writer reads the name of the target, not the slug the engine was
# given. Book HTML, because it needs pandoc alone and the rename is the
# same code for every format that runs a job.
def Test_a_compiled_file_takes_the_accented_name_of_its_target(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  defer Cleanup(fx.project)
  var target = C.CompileTarget.FromDict({
    name: 'Über Draft', kind: 'Book', format: 'HTML',
    includedIds: [fx.scene1.id],
  })
  var outDir: string = fx.project.scriveDir .. '/compile/output'
  C.Execute(fx.project, target)
  var outputPath: string = WaitForOutput(fx.project, 'Über-Draft.html')
  assert_true(outputPath !=# '',
    $'no Über-Draft.html within {MAX_WAIT_MS}ms')
  # One file, so the slug the engine was given is gone rather than left
  # beside the name the writer reads.
  assert_equal(['Über-Draft.html'],
    glob(outDir .. '/*.html', true, true)->mapnew((_, f) => fnamemodify(f, ':t')))

  # A recompile replaces its output, so the rename does too. The marker
  # says which file the second run wrote: the log of a run cannot,
  # because two HTML compiles in one second share its timestamp.
  if outputPath !=# ''
    writefile([STALE], outputPath)
    C.Execute(fx.project, target)
    var waited: number = 0
    # Through filereadable, because Finish deletes the file it is about
    # to rename onto, so a poll that lands in that window would report
    # E484 rather than fail the assertion this test makes.
    while waited < MAX_WAIT_MS && FirstLine(outputPath) ==# STALE
      execute $'sleep {POLL_INTERVAL_MS}m'
      waited += POLL_INTERVAL_MS
    endwhile
    assert_notequal(STALE, FirstLine(outputPath),
      $'the second run left the first output within {MAX_WAIT_MS}ms')
    assert_equal(['Über-Draft.html'],
      glob(outDir .. '/*.html', true, true)->mapnew((_, f) => fnamemodify(f, ':t')),
      'after the second run')
  endif
enddef

export def RunAll(): void
  RE.RunTests([
    Test_manuscript_pdf_compiles_to_a_real_nonempty_file,
    Test_the_font_of_the_fixture_has_one_definition,
    Test_book_pdf_compiles_to_a_real_nonempty_file,
    Test_pandoc_log_per_run_with_retention,
    Test_failure_writes_a_log_and_asks_to_open_it,
    Test_two_targets_of_one_slug_keep_their_own_working_files,
    Test_a_second_compile_of_one_target_waits_for_the_first,
    Test_a_rename_during_a_compile_cannot_take_its_working_files,
    Test_a_markdown_output_is_written_under_the_name_of_its_target,
    Test_two_targets_of_one_artifact_name_keep_their_own_files,
    Test_a_compiled_file_takes_the_accented_name_of_its_target,
    Test_book_html_tables_get_the_settings,
    Test_the_table_filter_draws_lines_only_when_asked,
    Test_the_table_filter_styles_the_header,
    Test_the_table_filter_keeps_the_width_with_rules,
  ])
enddef

# A private home folder, so that the log test counts only its own logs,
# and a small retention. Both are set before Bartleby loads, because
# compile.vim reads the retention setting once, when it loads.
$HOME = tempname()
mkdir($HOME, 'p')
g:bartleby_compile_log_retention = 2
# The table lines and an italic header, so that the PDFs of these tests go
# through tools/pandoc/tables.lua, the way with more to go wrong. The
# default way is in the filter tests.
g:bartleby_compile_table_border = 'single'
g:bartleby_compile_table_vlines = 'single'
g:bartleby_compile_table_header = 'italic'
execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
RE.Run(RunAll, 'the smoke suite')
if !RE.Report(RESULT, PASS)
  cquit 1
endif
