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

const STUB: string = fnamemodify(resolve(expand('<script>')), ':h') .. '/stub/ghostcode'
const ARGS: string = tempname()

const REPORT: string = join([
  '{"schema": 1, "root": "/project",',
  '"summary": {"symbols": 7, "ghost": 2, "unresolved": 1},',
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
): void

  g:ghostcode_bin = STUB
  $GHOSTCODE_STUB_OUT = out
  $GHOSTCODE_STUB_EXIT = string(status)
  $GHOSTCODE_STUB_ARGS = ARGS

  if api != null
    g:ghostcode_exports_are_api = api
  endif

  setqflist([], 'r')

  try
    G.Run(path)
  finally
    silent! cclose
    unlet! g:ghostcode_bin
    unlet! g:ghostcode_exports_are_api
  endtry
enddef

# FUNCTION: The arguments the stub was called with.
def Args(): list<string>
  return filereadable(ARGS) ? readfile(ARGS) : []
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

  assert_equal('/project/autoload/m.vim', bufname(getqflist()[0].bufnr))
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

  assert_true(index(Args(), '/tmp/a folder/with space') >= 0, join(Args(), '|'))
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

def Test_a_skipped_file_does_not_reach_the_quickfix_list(): void
  Scan(join([
    '{"schema": 1, "root": "/project",',
    '"summary": {"symbols": 1, "ghost": 0, "unresolved": 0},',
    '"findings": [],',
    '"skipped": [{"file": "autoload/old.vim", "why": "not UTF-8"}]}',
  ], "\n"))

  assert_equal([], getqflist())
enddef

def Test_the_plugin_script_defines_no_default_for_the_setting(): void
  assert_false(exists('g:ghostcode_exports_are_api'))
enddef

export def RunAll(): void
  Test_the_quickfix_text_matches_the_old_format()
  Test_the_column_is_one_and_the_line_is_the_reported_one()
  Test_a_path_is_joined_to_the_root_again()
  Test_a_missing_binary_reports_and_does_not_throw()
  Test_a_non_zero_exit_leaves_the_list_alone()
  Test_output_that_is_not_json_does_not_throw()
  Test_an_unknown_schema_stops_rather_than_guessing()
  Test_a_root_with_spaces_is_passed_as_one_argument()
  Test_the_setting_is_not_passed_when_the_user_did_not_set_it()
  Test_the_setting_is_passed_when_the_user_set_it()
  Test_the_setting_accepts_a_number()
  Test_a_skipped_file_does_not_reach_the_quickfix_list()
  Test_the_plugin_script_defines_no_default_for_the_setting()
enddef
