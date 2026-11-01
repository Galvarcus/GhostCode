vim9script

##############################################################################
# Plugin_Name: Logger
# Tests logger.vim: prefixes, caller names, tags, echo and file levels,
# the order of option lookup, file lines, exceptions, Fmt, and Try.
#
# In -es mode v:vim_did_enter stays false, so each echoed message waits
# in the queue. The tests use the queue to see what Logger echoes.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log
import 'Logger/messages.vim' as M
import './fixtures.vim' as F
import './thrower.vim' as T

const STAMP: string = '^\d\{4}-\d\d-\d\d \d\d:\d\d:\d\d '

def FirstLines(entries: list<dict<any>>): list<string>
  return entries->mapnew((_, e) => e.lines[0])
enddef

class Probe
  var log: Log.Logger
  def new(this.log)
  enddef
  def Speak()
    this.log.Info('from a method')
  enddef
endclass

def Test_prefix_omits_empty_parts(): void
  assert_equal('P - s.vim - M: ', Log.Logger.new('P', 's.vim').Prefix('M'))
  assert_equal('P - s.vim: ', Log.Logger.new('P', 's.vim').Prefix(''))
  assert_equal('P: ', Log.Logger.new('P').Prefix(''))
enddef

def Test_caller_name_of_function_and_method(): void
  F.Reset()
  var log = Log.Logger.new('P', 't.vim')
  log.Info('from a function')
  Probe.new(log).Speak()
  log.Info('named', 'Custom')
  assert_equal([
    'P - t.vim - Test_caller_name_of_function_and_method: from a function',
    'P - t.vim - Probe.Speak: from a method',
    'P - t.vim - Custom: named',
  ], FirstLines(M.History()))
enddef

def Test_tags(): void
  F.Reset()
  var log = Log.Logger.new('P', 't.vim')
  log.Warn('w', 'X')
  log.Error('e', 'X')
  assert_equal(['P - t.vim - X: [WARN] w', 'P - t.vim - X: [ERROR] e'],
    FirstLines(M.History()))
enddef

def Test_level_limits_echo(): void
  F.Reset()
  g:logger_level = 1
  var log = Log.Logger.new('P')
  log.Info('i', 'X')
  log.Warn('w', 'X')
  assert_equal(['P - X: [WARN] w'], FirstLines(M.Pending()))
  g:logger_level = -1
  M.Clear()
  log.Error('e', 'X')
  assert_equal([], M.Pending())
  F.Reset()
enddef

def Test_level_lookup_order(): void
  F.Reset()
  g:logger_level = 2
  var log = Log.Logger.new('P', '', 0)
  log.Warn('hidden by the new argument', 'X')
  assert_equal([], M.Pending())
  g:logger_p_level = 1
  log.Warn('shown by the plugin option', 'X')
  assert_equal(1, len(M.Pending()))
  F.Reset()
enddef

def Test_echo_off_for_one_plugin(): void
  F.Reset()
  g:logger_a_echo = false
  Log.Logger.new('A').Info('quiet', 'X')
  Log.Logger.new('B').Info('loud', 'X')
  assert_equal(['B - X: loud'], FirstLines(M.Pending()))
  F.Reset()
enddef

def Test_file_is_off_by_default(): void
  var dir: string = F.Reset()
  Log.Logger.new('P').Error('e', 'X')
  assert_false(isdirectory(dir))
enddef

def Test_file_line_format(): void
  var dir: string = F.Reset()
  g:logger_log_file = true
  Log.Logger.new('P', 't.vim').Warn('text', 'X')
  var lines: list<string> = F.LogLines(dir)
  assert_equal(1, len(lines))
  assert_match($'{STAMP}WARN P - t.vim - X: text$', lines[0])
  delete(dir, 'rf')
  F.Reset()
enddef

def Test_log_level_limits_file(): void
  var dir: string = F.Reset()
  g:logger_log_file = true
  g:logger_log_level = 0
  var log = Log.Logger.new('P')
  log.Warn('w', 'X')
  log.Error('e', 'X')
  var lines: list<string> = F.LogLines(dir)
  assert_equal(1, len(lines))
  assert_match('ERROR P - X: e$', lines[0])
  delete(dir, 'rf')
  F.Reset()
enddef

def Test_file_without_echo(): void
  var dir: string = F.Reset()
  g:logger_p_log_file = true
  g:logger_p_echo = false
  Log.Logger.new('P').Info('only in the file', 'X')
  assert_equal([], M.Pending())
  assert_equal(1, len(M.History()))
  assert_equal(1, len(F.LogLines(dir)))
  delete(dir, 'rf')
  F.Reset()
enddef

def Test_exception_has_throwpoint(): void
  var dir: string = F.Reset()
  g:logger_log_file = true
  var log = Log.Logger.new('P')
  try
    throw 'boom'
  catch
    log.Exception()
  endtry
  var lines: list<string> = M.History()[0].lines
  assert_equal('P - Test_exception_has_throwpoint: [EXCEPTION] boom', lines[0])
  assert_match('^  at .*Test_exception_has_throwpoint', lines[1])
  var logged: list<string> = F.LogLines(dir)
  assert_equal(2, len(logged))
  assert_match('EXCEPTION P - Test_exception_has_throwpoint: boom$', logged[0])
  delete(dir, 'rf')
  F.Reset()
enddef

def Test_fmt_is_recorded_and_logged_once(): void
  var dir: string = F.Reset()
  g:logger_log_file = true
  var log = Log.Logger.new('P')
  try
    throw log.Fmt('bad', 'X')
  catch
    log.Exception()
  endtry
  assert_equal(['P - X: [EXCEPTION] bad'], FirstLines(M.History()))
  assert_equal(['P - X: [EXCEPTION] bad'], FirstLines(M.Pending()))
  assert_equal(1, len(F.LogLines(dir)))
  delete(dir, 'rf')
  F.Reset()
enddef

def Test_fmt_is_caught_in_another_script(): void
  F.Reset()
  var caught: string = ''
  assert_equal('this', T.GetThat('this'))
  try
    T.GetThat('that')
  catch
    caught = v:exception
  endtry
  assert_equal('Test - thrower.vim - GetThat: [EXCEPTION] dangit', caught)
  F.Reset()
enddef

def Test_try_returns_result_or_none(): void
  F.Reset()
  var log = Log.Logger.new('P')
  assert_equal(7, log.Try(() => 7))
  var Fails = (): any => {
    throw 'nope'
  }
  assert_equal(v:none, log.Try(Fails, 'X'))
  assert_equal(['P - X: [EXCEPTION] nope'], FirstLines(M.History()))
  F.Reset()
enddef

def Test_write_failure_warns_once(): void
  F.Reset()
  var blocker: string = tempname()
  writefile(['file'], blocker)
  g:logger_log_dir = $'{blocker}/logs'
  g:logger_log_file = true
  var log = Log.Logger.new('P')
  log.Info('first', 'X')
  log.Info('second', 'X')
  var warnings: list<dict<any>> = M.History()
    ->filter((_, e) => e.kind ==# 'warn')
  assert_equal(1, len(warnings))
  assert_match('^Logger: cannot write the log file of P: ', warnings[0].lines[0])
  delete(blocker)
  F.Reset()
enddef

export def RunAll(): void
  Test_prefix_omits_empty_parts()
  Test_caller_name_of_function_and_method()
  Test_tags()
  Test_level_limits_echo()
  Test_level_lookup_order()
  Test_echo_off_for_one_plugin()
  Test_file_is_off_by_default()
  Test_file_line_format()
  Test_log_level_limits_file()
  Test_file_without_echo()
  Test_exception_has_throwpoint()
  Test_fmt_is_recorded_and_logged_once()
  Test_fmt_is_caught_in_another_script()
  Test_try_returns_result_or_none()
  Test_write_failure_warns_once()
enddef
