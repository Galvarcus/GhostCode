vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_texcheck.vim: what the LaTeX templates need, and finding what
# TeX lacks of it, with a stand-in kpsewhich so that the tests decide which
# files exist. A stand-in is a shell script, and a batch file on Windows,
# where a file with no extension is never executable. The TeX check against
# a real MiKTeX is in tests/test_texcheck_miktex.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/texcheck.vim' as TX

const LATEX: string = fnamemodify(expand('<script>'), ':p:h:h') .. '/tools/latex'

# FUNCTION: Make a folder of stand-in programs: a kpsewhich that finds only
# the files of found, and with miktex, the program that only MiKTeX has.
export def Stubs(found: list<string>, miktex: bool = false, others: list<string> = []): string
  var dir: string = tempname()
  mkdir(dir, 'p')
  var win: bool = has('win32')
  var ext: string = win ? '.cmd' : ''
  var kpse: list<string>
  if win
    # Each argument in turn, because a batch file has no case.
    kpse = ['@echo off', ':next', 'if "%~1"=="" exit /b 0']
      + found->mapnew((_, f) => $'if "%~1"=="{f}" echo /tex/{f}')
      + ['shift', 'goto next']
  else
    kpse = ['#!/bin/sh', 'for n in "$@"; do', '  case "$n" in']
      + found->mapnew((_, f) => $'    {f}) echo /tex/{f} ;;') + ['  esac', 'done']
  endif
  writefile(kpse, $'{dir}/kpsewhich{ext}')
  for name in others + (miktex ? ['initexmf'] : [])
    writefile([win ? '@echo off' : '#!/bin/sh'], $'{dir}/{name}{ext}')
  endfor
  if !win
    for name in readdir(dir)
      setfperm($'{dir}/{name}', 'rwxr-xr-x')
    endfor
  endif
  return dir
enddef

var saved: dict<string> = {}

# FUNCTION: Use only dir to find programs. The shell has a full path, so
# that system() still runs. The shell of Windows already has one, and it
# is the one that runs a batch file.
export def UsePath(dir: string): void
  saved = {path: $PATH, shell: &shell}
  if !has('win32')
    &shell = '/bin/sh'
  endif
  $PATH = dir
enddef

export def RestorePath(): void
  $PATH = saved.path
  &shell = saved.shell
enddef

def Test_what_the_manuscript_template_needs(): void
  var tmpl: list<string> = readfile(LATEX .. '/manuscript.tex')
  assert_equal(['fancyhdr.sty', 'geometry.sty', 'hyperref.sty', 'setspace.sty', 'sffms.cls',
    'sffsmart.sty', 'ulem.sty'], TX.Needs(tmpl, {}))
  var tables: list<string> = TX.Needs(tmpl, {tables: true})
  for f in ['array.sty', 'booktabs.sty', 'calc.sty', 'caption.sty', 'longtable.sty']
    assert_true(index(tables, f) >= 0, f)
  endfor
enddef

def Test_what_the_book_template_needs(): void
  var tmpl: list<string> = readfile(LATEX .. '/book.tex')
  assert_equal(['book.cls', 'fancyhdr.sty', 'fmtcount.sty', 'fontspec.sty', 'geometry.sty',
    'graphicx.sty', 'hyperref.sty', 'microtype.sty', 'titlesec.sty'], TX.Needs(tmpl, {}))
  assert_true(index(TX.Needs(tmpl, {lang: true}), 'babel.sty') >= 0)
enddef

def Test_needs_reads_lists_comments_and_conditions(): void
  var tmpl: list<string> = ['\documentclass[a]{c}', '\usepackage{p, q}', '% \usepackage{gone}',
    '\usepackage{r} % \usepackage{gone2}', '$if(x)$', '\usepackage{onx}', '$else$',
    '\usepackage{offx}', '$endif$', '\usepackage{$pkg$}', '% NEEDS: n.sty']
  assert_equal(['c.cls', 'n.sty', 'offx.sty', 'p.sty', 'q.sty', 'r.sty'], TX.Needs(tmpl, {}))
  assert_equal(['c.cls', 'n.sty', 'onx.sty', 'p.sty', 'q.sty', 'r.sty'], TX.Needs(tmpl, {x: true}))
enddef

def Test_missing_names_what_kpsewhich_cannot_find(): void
  var dir: string = Stubs(['a.sty', 'c.cls'])
  UsePath(dir)
  var missing: list<string> = TX.Missing(['\documentclass{c}', '\usepackage{a,b}'], {})
  RestorePath()
  delete(dir, 'rf')
  assert_equal(['b.sty'], missing)
enddef

def Test_nothing_is_checked_without_kpsewhich_or_with_miktex(): void
  var empty: string = tempname()
  mkdir(empty, 'p')
  UsePath(empty)
  assert_equal([], TX.Missing(['\usepackage{a}'], {}))
  RestorePath()
  var dir: string = Stubs([], true)
  UsePath(dir)
  assert_equal([], TX.Missing(['\usepackage{a}'], {}))
  RestorePath()
  delete(empty, 'rf')
  delete(dir, 'rf')
enddef

export def RunAll(): void
  Test_what_the_manuscript_template_needs()
  Test_what_the_book_template_needs()
  Test_needs_reads_lists_comments_and_conditions()
  Test_missing_names_what_kpsewhich_cannot_find()
  Test_nothing_is_checked_without_kpsewhich_or_with_miktex()
enddef
