vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/test_frontend.vim: what the front end does with what the binary
# reports, and what it does when the binary cannot be run. The stub in
# tests/stub/ghostcode stands in for the binary, so that these tests need no
# release build.
# License: GNU GPL 3.0
##############################################################################

import autoload 'ghostcode.vim' as G
# Logger records every message it is given, whether or not it echoes
# one, and -es hides an echo besides. Its history is the only place a
# test can read the line the user is shown.
import 'Logger/messages.vim' as LM
import './skip.vim' as S

# The stub that stands in for the binary. On Windows it is a program
# compiled from the source beside it, because the front end starts the
# binary with the list form of systemlist(), which starts a program
# directly and cannot start a script.
const STUB: string = fnamemodify(resolve(expand('<script>')), ':h')
  .. (has('win32') ? '/stub/ghostcode.exe' : '/stub/ghostcode')
# The file name of the binary on the platform running the suite. The
# script under test derives this too, and a test that derived it from
# the same place would prove nothing.
const EXE: string = has('win32') || has('win32unix') ? 'ghostcode.exe' : 'ghostcode'
const BIN_DIR: string = 'bin'
const ARGS: string = tempname()

const REPORT: string = join([
  '{"schema": 1, "root": "/project",',
  '"summary": {"symbols": 7, "ghost": 2, "unplaced_names": 1},',
  '"findings": [',
  '{"class": "ghost", "kind": "method", "name": "Open",',
  '"file": "autoload/m.vim", "line": 12, "col": 1, "lang": "vim9"},',
  '{"class": "ghost", "kind": "function", "name": "Dead",',
  '"file": "autoload/a.vim", "line": 3, "col": 1, "lang": "vim9"}]}',
], "\n")

# FUNCTION: Run the front end against the stub, with the output, exit
# status, and settings the test wants, and clean up after it.
def Scan(
  out: string = REPORT,
  status: number = 0,
  path: string = '/project',
  api: any = null,
  locals: any = null,
): void

  g:ghostcode_bin = STUB
  $GHOSTCODE_STUB_OUT = out
  $GHOSTCODE_STUB_EXIT = string(status)
  $GHOSTCODE_STUB_ARGS = ARGS

  if api != null
    g:ghostcode_exports_are_api = api
  endif

  if locals != null
    g:ghostcode_locals = locals
  endif

  delete(ARGS)
  setqflist([], 'r')

  try
    G.Run(path)
  finally
    silent! cclose
    unlet! g:ghostcode_bin
    unlet! g:ghostcode_exports_are_api
    unlet! g:ghostcode_locals
  endtry
enddef

# FUNCTION: The arguments the stub was called with.
def Args(): list<string>
  return filereadable(ARGS) ? readfile(ARGS) : []
enddef

# FUNCTION: Every argument that carries the spaced name the two tests
# of a root with spaces pass, with the separator folded onto one so that
# the absolute form Windows builds is read the same way.
def SpacedArgs(): list<string>
  return Args()
    ->mapnew((_, a) => substitute(a, '\\', '/', 'g'))
    ->filter((_, a) => a =~# '/tmp/a folder/with space$')
enddef

# FUNCTION: Run the :GhostCode command itself against the stub,
# rather than the function behind it, so that the command's own
# argument handling is covered. A command that fails to parse raises
# an error, which the suite must read as a failed test rather than
# let abort the run.
def Command(args: string): void
  g:ghostcode_bin = STUB
  $GHOSTCODE_STUB_OUT = REPORT
  $GHOSTCODE_STUB_EXIT = '0'
  $GHOSTCODE_STUB_ARGS = ARGS

  delete(ARGS)
  setqflist([], 'r')

  try
    execute 'GhostCode' args
  catch
    assert_report(v:exception)
  finally
    silent! cclose
    unlet! g:ghostcode_bin
  endtry
enddef

def Test_the_quickfix_text_matches_the_old_format(): void
  Scan()

  var texts = getqflist()->mapnew((_, i) => i.text)
  assert_equal(['[ghost] method Open', '[ghost] function Dead'], texts)
enddef

def Test_the_column_is_one_and_the_line_is_the_reported_one(): void
  Scan()

  var list = getqflist()
  assert_equal(1, list[0].col)
  assert_equal(12, list[0].lnum)
enddef

def Test_a_path_is_joined_to_the_root_again(): void
  Scan()

  # Vim names a buffer with the separator of the platform, so the name is
  # folded onto one separator before it is read. What the quickfix list
  # carries is the name, and either separator reaches the same file.
  var name = bufname(getqflist()[0].bufnr)->substitute('\\', '/', 'g')

  assert_equal('/project/autoload/m.vim', name)
enddef

def Test_a_missing_binary_reports_and_does_not_throw(): void
  g:ghostcode_bin = '/nonexistent/ghostcode'
  setqflist([], 'r')

  try
    G.Run('/project')
  finally
    unlet! g:ghostcode_bin
  endtry

  assert_equal([], getqflist())
enddef

# FUNCTION: A user who is told that nothing was found has to know
# which file to go and get. On Windows that file is ghostcode.exe, in
# the directory beside the plugin as much as on $PATH.
def Test_a_missing_binary_message_names_the_file_it_wants(): void
  var bundled = fnamemodify(resolve(expand('<script>')), ':h:h') .. $'/{BIN_DIR}/{EXE}'

  # A developer who keeps a binary beside the plugin cannot run this
  # test: Bin() finds that one and the message under test never comes.
  # An assertion here aborted the run and wrote no results at all.
  if executable(bundled) == 1
    S.Skip('a_missing_binary_message_names_the_file_it_wants',
      $'a binary is bundled at {bundled}')
    return
  endif

  # $PATH is emptied, because a machine that develops Ghostcode has
  # the binary on it, and the message under test is the one for a
  # machine that has none.
  var path = $PATH

  LM.Clear()
  g:ghostcode_bin = '/nonexistent/ghostcode'
  $PATH = ''

  try
    G.Run('/project')
  finally
    $PATH = path
    unlet! g:ghostcode_bin
  endtry

  var said = LM.History()
    ->mapnew((_, m) => join(m.lines, ' '))
    ->filter((_, l) => l =~# 'Looked at')
    ->join(' ')

  assert_true(said =~# $'no {EXE} found\.', said)
  assert_true(said =~# $'/bin/{EXE}\.', said)
  LM.Clear()
enddef

def Test_a_non_zero_exit_leaves_the_list_alone(): void
  Scan('boom', 2)

  assert_equal([], getqflist())
enddef

def Test_output_that_is_not_json_does_not_throw(): void
  Scan('not json at all')

  assert_equal([], getqflist())
enddef

def Test_an_unknown_schema_stops_rather_than_guessing(): void
  Scan('{"schema": 99, "findings": []}')

  assert_equal([], getqflist())
enddef

def Test_a_root_with_spaces_is_passed_as_one_argument(): void
  Scan(REPORT, 0, '/tmp/a folder/with space')

  # The root is made absolute before it is passed, which on Windows names
  # the drive as well and turns the separators around. What is asked is
  # that the name holding spaces reached the binary whole, as one
  # argument, rather than split into three.
  assert_equal(1, len(SpacedArgs()), join(Args(), '|'))
enddef

# FUNCTION: A trailing separator is dropped from the root, so that
# the quickfix paths read as they always have. The separator of a root
# directory is the directory, and dropping it passed no path at all.
def Test_the_root_directory_is_passed_as_itself(): void
  Scan(REPORT, 0, '/')

  # A root directory is its own separator, and Windows names the drive
  # before it. Dropping that separator would pass no path at all, so what
  # is asked is that a root arrives as a root.
  var last = get(Args(), -1, '')

  assert_true(last =~# '^\%(\a:\)\=[\\/]$', last)
enddef

def Test_the_command_passes_an_escaped_space_as_one_argument(): void
  Command('/tmp/a\ folder/with\ space')

  assert_equal(1, len(SpacedArgs()), join(Args(), '|'))
enddef

def Test_the_command_scans_the_working_directory_with_no_argument(): void
  Command('')

  assert_equal(getcwd(), get(Args(), -1, ''))
enddef

def Test_the_logged_summary_carries_no_count_the_user_cannot_act_on(): void
  LM.Clear()
  Scan()

  assert_equal(
    ['Ghostcode - ghostcode.vim - Report: 7 symbols, 2 ghost'],
    LM.History()->mapnew((_, m) => join(m.lines, ' '))->filter((_, l) => l =~# 'symbols')
  )
enddef

def Test_a_report_from_an_older_binary_still_logs_its_two_counts(): void
  LM.Clear()
  Scan(substitute(REPORT, 'unplaced_names', 'unresolved', ''))

  assert_equal(
    ['Ghostcode - ghostcode.vim - Report: 7 symbols, 2 ghost'],
    LM.History()->mapnew((_, m) => join(m.lines, ' '))->filter((_, l) => l =~# 'symbols')
  )
enddef

def Test_the_setting_is_not_passed_when_the_user_did_not_set_it(): void
  Scan()

  assert_equal(-1, index(Args(), '--exports-are-api'))
enddef

def Test_the_setting_is_passed_when_the_user_set_it(): void
  Scan(REPORT, 0, '/project', false)

  var args = Args()
  var at = index(args, '--exports-are-api')
  assert_true(at >= 0, join(args, '|'))
  assert_equal('false', args[at + 1])
enddef

# FUNCTION: A :let on the command line gives a number, as the CI of a
# project does. 0 turns the mode on and 1 leaves it off.
def Test_the_setting_accepts_a_number(): void
  Scan(REPORT, 0, '/project', 0)

  var args = Args()
  assert_equal('false', args[index(args, '--exports-are-api') + 1])
enddef

# FUNCTION: A setting is whatever the user wrote, and Vim9 reads only
# 0 and 1 as a condition, so a value outside them once threw out of
# the scan instead of being passed on.
def Test_a_setting_outside_zero_and_one_does_not_throw(): void
  Scan(REPORT, 0, '/project', 2)

  var args = Args()
  var at = index(args, '--exports-are-api')
  assert_true(at >= 0, join(args, '|'))
  assert_equal('true', args[at + 1])
enddef

# FUNCTION: The schema is a number in every report the binary writes,
# and a report that carries anything else is a report this plugin
# cannot read, which is said rather than thrown.
def Test_a_schema_that_is_not_a_number_does_not_throw(): void
  Scan('{"schema": "1", "findings": []}')

  assert_equal([], getqflist())
enddef

def Test_a_skipped_file_does_not_reach_the_quickfix_list(): void
  Scan(join([
    '{"schema": 1, "root": "/project",',
    '"summary": {"symbols": 1, "ghost": 0, "unplaced_names": 0},',
    '"findings": [],',
    '"skipped": [{"file": "autoload/old.vim", "why": "not UTF-8"}]}',
  ], "\n"))

  assert_equal([], getqflist())
enddef

def Test_the_plugin_script_defines_no_default_for_the_setting(): void
  assert_false(exists('g:ghostcode_exports_are_api'))
enddef

def Test_the_locals_setting_is_not_passed_when_the_user_did_not_set_it(): void
  Scan()

  assert_equal(-1, index(Args(), '--locals'))
enddef

def Test_the_locals_setting_is_passed_when_the_user_set_it(): void
  Scan(REPORT, 0, '/project', null, true)

  var args = Args()
  var at = index(args, '--locals')
  assert_true(at >= 0, join(args, '|'))
  assert_equal('true', args[at + 1])
enddef

def Test_the_plugin_script_defines_no_default_for_the_locals_setting(): void
  assert_false(exists('g:ghostcode_locals'))
enddef

export def RunAll(): void
  Test_the_quickfix_text_matches_the_old_format()
  Test_the_column_is_one_and_the_line_is_the_reported_one()
  Test_a_path_is_joined_to_the_root_again()
  Test_a_missing_binary_reports_and_does_not_throw()
  Test_a_missing_binary_message_names_the_file_it_wants()
  Test_a_non_zero_exit_leaves_the_list_alone()
  Test_output_that_is_not_json_does_not_throw()
  Test_an_unknown_schema_stops_rather_than_guessing()
  Test_a_root_with_spaces_is_passed_as_one_argument()
  Test_the_root_directory_is_passed_as_itself()
  Test_the_command_passes_an_escaped_space_as_one_argument()
  Test_the_command_scans_the_working_directory_with_no_argument()
  Test_the_logged_summary_carries_no_count_the_user_cannot_act_on()
  Test_a_report_from_an_older_binary_still_logs_its_two_counts()
  Test_the_setting_is_not_passed_when_the_user_did_not_set_it()
  Test_the_setting_is_passed_when_the_user_set_it()
  Test_the_setting_accepts_a_number()
  Test_a_setting_outside_zero_and_one_does_not_throw()
  Test_a_schema_that_is_not_a_number_does_not_throw()
  Test_a_skipped_file_does_not_reach_the_quickfix_list()
  Test_the_plugin_script_defines_no_default_for_the_setting()
  Test_the_locals_setting_is_not_passed_when_the_user_did_not_set_it()
  Test_the_locals_setting_is_passed_when_the_user_set_it()
  Test_the_plugin_script_defines_no_default_for_the_locals_setting()
enddef
