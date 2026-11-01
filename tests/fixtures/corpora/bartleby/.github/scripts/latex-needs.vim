vim9script

##############################################################################
# Plugin_Name: Bartleby
# .github/scripts/latex-needs.vim: write every class and package that the
# compile templates name, one to a line, for warm-miktex.sh to fetch before
# the smoke tests run. It asks texcheck.vim, which already parses the
# templates for the TeX check, so the list has one source.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/texcheck.vim' as TX

const LATEX: string = fnamemodify(expand('<script>'), ':p:h:h:h') .. '/tools/latex'
const REPORT: string = 'tests/needs_results.txt'

var names: list<string> = []
for template in glob(LATEX .. '/*.tex', true, true)
  names += TX.Needs(readfile(template), {})
endfor
writefile(names->sort()->uniq(), REPORT)
