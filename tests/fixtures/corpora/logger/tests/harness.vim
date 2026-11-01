vim9script

##############################################################################
# Plugin_Name: Logger
# Runs the RunAll function of each test module, then reports the failures
# that the assert functions put in v:errors. Writes tests/results.txt
# because -es mode shows no messages.
#
# Usage from the root of the repository:
#   vim -es -u NONE -N -c 'set rtp+=.' -c 'source tests/harness.vim' \
#     -c 'quit'
#
# The exit code is 0 on success and 1 on any failed assertion.
# License: GNU GPL 3.0
##############################################################################

# Without a UTF-8 locale, Vim starts with encoding latin1.
set encoding=utf-8

# -u NONE skips plugin files, so load the plugin as Vim startup does.
execute $"source {expand('<sfile>:h:h')}/plugin/logger.vim"

import './test_config.vim' as TestConfig
import './test_logfile.vim' as TestLogFile
import './test_logger.vim' as TestLogger
import './test_messages.vim' as TestMessages

var suites: list<func(): void> = [
  TestConfig.RunAll,
  TestLogFile.RunAll,
  TestLogger.RunAll,
  TestMessages.RunAll,
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
