vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_tagger.vim: which program tagger.vim runs. The spacy tagger
# named python3 alone, which Windows does not install: that system has
# python.exe and the py launcher, and python3.exe only as the alias of a
# Microsoft Store install. So the tagger switched itself off there, and
# IsReady answered false for the session.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/54
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/tagger.vim' as TG

# The Vim that runs these tests, as a program that certainly exists, and a
# name that certainly does not. Neither depends on what else this system
# holds, so the tests answer the same everywhere.
const RUNNABLE: string = v:progpath
const MISSING: string = 'bartleby-no-such-program'

def Test_the_first_program_that_exists_is_the_one_chosen(): void
  assert_equal([RUNNABLE], TG.FirstRunnable([[MISSING], [RUNNABLE]]))
enddef

def Test_the_flags_travel_with_the_program(): void
  assert_equal([RUNNABLE, '-3'], TG.FirstRunnable([[MISSING, '-9'], [RUNNABLE, '-3']]))
enddef

def Test_no_program_that_exists_gives_no_command(): void
  assert_equal([], TG.FirstRunnable([[MISSING], [MISSING .. '-either']]))
  assert_equal([], TG.FirstRunnable([]))
  assert_equal([], TG.FirstRunnable([[]]))
enddef

def Test_the_spacy_command_names_a_program_of_this_system(): void
  var savedTagger: any = g:bartleby_spotlight_tagger
  var savedModel: string = g:bartleby_spotlight_spacy_model
  g:bartleby_spotlight_tagger = 'spacy'
  g:bartleby_spotlight_spacy_model = 'en_core_web_sm'
  try
    var cmd: list<string> = TG.Command()
    # An empty answer is right where no Python is installed. What must
    # never happen is a command naming a program that cannot run, which
    # is what IsReady checks and what left the tagger silent on Windows.
    assert_true(empty(cmd) || executable(cmd[0]),
      'the command names a program that does not exist')
    if !empty(cmd)
      assert_true(cmd[-2] =~# 'spacy_tagger\.py$', 'the script is missing')
      assert_equal('en_core_web_sm', cmd[-1])
    endif
  finally
    g:bartleby_spotlight_tagger = savedTagger
    g:bartleby_spotlight_spacy_model = savedModel
  endtry
enddef

export def RunAll(): void
  Test_the_first_program_that_exists_is_the_one_chosen()
  Test_the_flags_travel_with_the_program()
  Test_no_program_that_exists_gives_no_command()
  Test_the_spacy_command_names_a_program_of_this_system()
enddef
