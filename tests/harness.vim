vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/harness.vim: runs every test of Ghostcode's front end and writes the
# result to tests/results.txt. The analysis itself is tested by `cargo test`.
# From the root of the repository run
#
#   vim -es -u NONE -N --cmd 'set rtp+=.,/path/to/Logger' \
#     -c 'runtime plugin/ghostcode.vim' \
#     -c 'source tests/harness.vim' -c 'quit'
#
# and read tests/results.txt. The mode -es hides every message, so when the
# file is missing, add -V20/tmp/vim.log after -N and read the log.
# License: GNU GPL 3.0
##############################################################################

# The results of the run before this one must not survive it: a suite that
# aborts writes nothing, and a stale file would read as a pass.
delete('tests/results.txt')

import './skip.vim' as S
import './test_frontend.vim' as TF
import './test_helptags.vim' as TH

var suites: list<func> = [
  TF.RunAll,
  TH.RunAll,
]

for RunSuite in suites
  RunSuite()
endfor

# A test that did not run is named above the verdict, so that a reader of
# the file, and the log of a job that prints it, sees the gap. The verdict
# keeps its own line, which is what every caller greps for.
var lines: list<string> = []
var skipped: list<string> = S.Skipped()

if len(skipped) > 0
  lines = [$'{len(skipped)} skipped:'] + skipped->mapnew((_, s) => $'  {s}')
endif

if len(v:errors) > 0
  writefile(lines + v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/results.txt')
  cquit 1
else
  writefile(lines + ['All tests passed'], 'tests/results.txt')
endif
