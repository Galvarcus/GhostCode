vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_texcheck_miktex.vim: the TeX check against a real MiKTeX,
# which the stand-in programs of tests/test_texcheck.vim cannot prove.
# They are shell scripts, and a program with no extension is not
# executable on Windows, so only an install shows that Bartleby finds
# initexmf, and so checks no class or package, because MiKTeX installs a
# missing one while it compiles. It also checks the engines that
# compile.vim looks for before a PDF.
#
# The test fails when MiKTeX is missing, instead of skipping, so that the
# miktex job of ci.yml cannot pass on a runner without it.
#
# Usage: the same command as tests/harness.vim, see its header, with
# MiKTeX on the PATH.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/texcheck.vim' as TX
import './report.vim' as RE

const LATEX: string = fnamemodify(expand('<script>'), ':p:h:h') .. '/tools/latex'
const RESULT: string = 'tests/miktex_results.txt'
const PASS: string = 'All MiKTeX tests passed'

# A program that only MiKTeX has, see texcheck.vim.
const MIKTEX_TOOL: string = 'initexmf'
# The engines of a Manuscript PDF and of a Book PDF, see compile.vim.
const ENGINES: list<string> = ['pdflatex', 'xelatex']
# A package that no distribution has, so that an empty answer can come
# only from the MiKTeX check, not from a lucky find.
const NO_PKG: list<string> = ['\usepackage{bartlebynosuchpkg}']
const NO_PKG_FILE: string = 'bartlebynosuchpkg.sty'

def Test_a_miktex_install_is_on_the_path(): void
  assert_true(executable(MIKTEX_TOOL), $'{MIKTEX_TOOL} is not executable')
  # The whole point of the job: the name has no extension, so Windows
  # finds the program only by its PATHEXT.
  if has('win32')
    assert_match('\c\.exe$', exepath(MIKTEX_TOOL))
  endif
enddef

def Test_the_engines_of_a_pdf_are_installed(): void
  for engine in ENGINES
    assert_true(executable(engine), $'{engine} is not executable')
  endfor
enddef

def Test_the_templates_name_what_they_need(): void
  # Without this, the empty results below would prove nothing: Missing
  # answers early when a template names no file at all.
  assert_true(len(TX.Needs(readfile(LATEX .. '/manuscript.tex'), {})) > 0)
  assert_true(len(TX.Needs(readfile(LATEX .. '/book.tex'), {})) > 0)
  assert_equal([NO_PKG_FILE], TX.Needs(NO_PKG, {}))
enddef

def Test_miktex_leaves_the_classes_and_packages_unchecked(): void
  assert_equal([], TX.Missing(readfile(LATEX .. '/manuscript.tex'), {}))
  assert_equal([], TX.Missing(readfile(LATEX .. '/book.tex'), {}))
  assert_equal([], TX.Missing(NO_PKG, {}))
enddef

export def RunAll(): void
  RE.RunTests([
    Test_a_miktex_install_is_on_the_path,
    Test_the_engines_of_a_pdf_are_installed,
    Test_the_templates_name_what_they_need,
    Test_miktex_leaves_the_classes_and_packages_unchecked,
  ])
enddef

RE.Run(RunAll, 'the MiKTeX suite')
if !RE.Report(RESULT, PASS)
  cquit 1
endif
