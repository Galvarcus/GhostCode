vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/harness.vim: runs every test of Ghostcode and writes the result to
# tests/results.txt. From the root of the repository run
#
#   vim -es -u NONE -N --cmd 'set rtp+=.,/path/to/Logger' \
#     -c 'runtime plugin/ghostcode.vim' \
#     -c 'source tests/harness.vim' -c 'quit'
#
# and read tests/results.txt. The mode -es hides every message, so when the
# file is missing, add -V20/tmp/vim.log after -N and read the log.
# License: GNU GPL 3.0
##############################################################################

import './test_ghostcode.vim' as TG

var suites: list<func> = [
  TG.RunAll,
]

for RunSuite in suites
  RunSuite()
endfor

if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/results.txt')
  cquit 1
else
  writefile(['All tests passed'], 'tests/results.txt')
endif
