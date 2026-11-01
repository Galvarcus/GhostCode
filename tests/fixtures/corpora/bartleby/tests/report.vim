vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/report.vim: runs a test suite and writes what it found, for
# harness.vim and for each suite that runs as a script of its own. The
# result file is what the workflow reads, so a run that writes none
# tells a reader nothing at all.
# License: GNU GPL 3.0
##############################################################################

# The name of a test inside the funcref that string gives for it, which
# is function('<SNR>12_Test_a_thing').
const NAME_PAT: string = 'Test_\w\+'

# FUNCTION: Call Fn, and turn an exception into a failure of its own,
# named by label. A throw, rather than a failed assertion, would end the
# script before it wrote a result, leaving the result of the run before
# it on disk and nothing to say what threw. An assertion never throws,
# so a run with nothing to report is unchanged. A Vim9 function that
# fails to compile is not caught here, by Vim itself, and still ends the
# script: only what a run throws is.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/66
export def Run(Fn: func(): void, label: string): void
  try
    Fn()
  catch
    v:errors->add($'{label} threw {v:exception} at {v:throwpoint}')
  endtry
enddef

# FUNCTION: Call every test in tests, each inside its own try, and name
# each by the test it holds. A suite that runs as a script of its own
# needs this, where harness.vim catches a whole suite at a time: nothing
# else would run the tests after the one that threw.
export def RunTests(tests: list<func(): void>): void
  for Test in tests
    # The whole funcref when the name is not a test's, which string
    # gives as function('<lambda>1'), so that the line names something.
    var label: string = matchstr(string(Test), NAME_PAT)
    Run(Test, label ==# '' ? string(Test) : label)
  endfor
enddef

# FUNCTION: Write what v:errors holds to path, and return whether the run
# passed, so that a caller ends with cquit. pass is the line that the
# workflow greps for, so each suite gives its own.
export def Report(path: string, pass: string): bool
  if len(v:errors) > 0
    writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], path)
    return false
  endif
  writefile([pass], path)
  return true
enddef
