vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/test_truth.vim: proof that Vim accepts each file of the truth
# families. A family states which symbols are ghosts, and that statement
# is worth nothing for a form that no Vim runs. Each family is copied,
# every file of the copy gets a :defcompile so that Vim also compiles the
# bodies that nothing calls, and Vim sources the copy.
# REFERENCE: https://github.com/Galvarcus/GhostCode/issues/80
# License: GNU GPL 3.0
##############################################################################

const TRUTH: string = 'tests/fixtures/truth'
const SCRIPTS: string = '**/*.vim'
const ENTRIES: string = 'plugin/*.vim'
const COMPILE: string = 'defcompile'

# FUNCTION: A copy of one family with every body compiled when its file
# loads. The fixture itself stays as a project would write it.
def Copy(family: string): string
  var dir = tempname()

  for src in globpath(family, SCRIPTS, false, true)
    var dest = dir .. src[len(family) :]
    mkdir(fnamemodify(dest, ':h'), 'p')
    writefile(readfile(src) + [COMPILE], dest)
  endfor

  return dir
enddef

# FUNCTION: The fault Vim reports for one family, or an empty string.
# The entry points load first, as Vim loads a plugin, and then each file
# that no entry point reached.
def Fault(family: string): string
  var dir = Copy(family)
  var rtp = &runtimepath
  var entries = globpath(dir, ENTRIES, false, true)
  var fault = ''

  execute $'set runtimepath+={fnameescape(dir)}'

  try
    for file in entries + globpath(dir, SCRIPTS, false, true)
      if index(getscriptinfo()->mapnew((_, s) => s.name), resolve(file)) < 0
        execute $'silent source {fnameescape(file)}'
      endif
    endfor
  catch
    fault = $'{fnamemodify(family, ':t')}: {v:exception} at {v:throwpoint}'
  finally
    &runtimepath = rtp
  endtry

  return fault
enddef

def Test_the_truth_corpus_holds_a_family(): void
  assert_true(len(globpath(TRUTH, '*', false, true)) > 0,
    $'no family under {TRUTH}')
enddef

def Test_vim_accepts_each_file_of_each_family(): void
  for family in globpath(TRUTH, '*', false, true)
    assert_equal('', Fault(family))
  endfor
enddef

export def RunAll(): void
  Test_the_truth_corpus_holds_a_family()
  Test_vim_accepts_each_file_of_each_family()
enddef
