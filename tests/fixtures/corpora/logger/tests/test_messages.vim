vim9script

##############################################################################
# Plugin_Name: Logger
# Tests messages.vim: the history limit, the queue before VimEnter, and
# the :LoggerMessages window.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/messages.vim' as M
import './fixtures.vim' as F

def Test_history_keeps_last_200(): void
  F.Reset()
  for i in range(250)
    M.Record('info', [$'message {i}'])
  endfor
  var entries: list<dict<any>> = M.History()
  assert_equal(200, len(entries))
  assert_equal(['message 50'], entries[0].lines)
  F.Reset()
enddef

def Test_flush_echoes_queue_in_order(): void
  F.Reset()
  M.Echo('info', ['queued one'])
  M.Echo('warn', ['queued two', '  at here'])
  assert_equal(2, len(M.Pending()))
  messages clear
  M.Flush()
  assert_equal([], M.Pending())
  assert_equal(['queued one', 'queued two', '  at here'],
    execute('messages')->split("\n")[-3 : ])
  F.Reset()
enddef

def Test_command_shows_history(): void
  F.Reset()
  assert_equal(2, exists(':LoggerMessages'))
  M.Record('info', ['first'])
  M.Record('exception', ['second', '  at here'])
  LoggerMessages
  var lines: list<string> = getline(1, '$')
  assert_equal(3, len(lines))
  assert_match('^\[\d\d:\d\d:\d\d\] first$', lines[0])
  assert_match('^\[\d\d:\d\d:\d\d\] second$', lines[1])
  assert_equal('             at here', lines[2])
  assert_equal('nofile', &buftype)
  assert_false(&modifiable)
  close
  F.Reset()
enddef

export def RunAll(): void
  Test_history_keeps_last_200()
  Test_flush_echoes_queue_in_order()
  Test_command_shows_history()
enddef
