vim9script

##############################################################################
# Plugin_Name: Bartleby
# .github/scripts/make-tex-closure.vim: compile the PDFs that the smoke
# tests compile, so that the tree of the cache entry gains every package
# the templates reach, and not only the ones they name. It writes the path
# of each PDF it produced, for make-tex-closure.sh to count.
#
# mpm documents no way to ask what a package requires, so the closure is
# earned by doing the work: this runs while the installer is on and the
# network is there, and the entry is saved after it. A compile of the leg
# then needs no install at all.
#
# The smoke suite cannot serve here. It allows each compile three minutes,
# which a first install of a package exceeds, and it holds a target of a
# font that does not exist, whose compile is meant to fail.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/68
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/project.vim' as PO
# The fixture of the tests, by a path relative to this script, because
# tests/ is not on the runtimepath.
import '../../tests/fixtures.vim' as FI

# The settings that compile.vim reads when it loads, such as the paths of
# the programs, come from the plugin file, which a script that imports an
# autoload file directly has to source itself.
execute 'source ' .. fnamemodify(expand('<script>'), ':p:h:h:h')
  .. '/plugin/bartleby.vim'

const REPORT: string = 'tests/closure_results.txt'
# What a compile may take here. It is not the budget of the smoke suite:
# the first compile of a run installs whatever the templates reach, and
# that is the work this script exists to do.
const WAIT_MS: number = 600000
const POLL_MS: number = 1000

# FUNCTION: Return the first file matching pattern in the output folder of
# project, with a size above 0, or an empty string after WAIT_MS.
def WaitForOutput(project: PO.Project, pattern: string): string
  var outDir: string = project.scriveDir .. '/compile/output'
  var waited: number = 0
  while waited < WAIT_MS
    var found: list<string> = glob($'{outDir}/{pattern}', false, true)
      ->filter((_, f) => getfsize(f) > 0)
    if !empty(found)
      return found[0]
    endif
    execute $'sleep {POLL_MS}m'
    waited += POLL_MS
  endwhile
  return ''
enddef

var fixture = FI.BuildProject()
var scene = fixture.ChildAt(1).ChildAt(0).ChildAt(0)
# The content of the smoke fixture, tables included, because the tables of
# a compile load packages of their own, see tools/pandoc/tables.lua.
FI.WriteDocContent(fixture, scene, ['It was a dark and stormy night.', '',
  '| Name | Age |', '| :--- | --: |', '| Mara |  34 |', '', 'Table: The crew'])

var made: list<string> = []
# One target for each engine: the Manuscript PDF runs pdflatex and the Book
# PDF runs xelatex, and the two templates name different packages.
for [name, kind, font] in [['ClosureManuscript', 'Manuscript', ''],
    ['ClosureBook', 'Book', FI.SMOKE_FONT]]
  var target = C.CompileTarget.FromDict({
    name: name, kind: kind, format: 'PDF', font: font,
    includedIds: [scene.id],
  })
  C.Execute(fixture, target)
  var path: string = WaitForOutput(fixture, $'{name}.pdf')
  if path ==# ''
    echom $'{name} produced no PDF within {WAIT_MS}ms'
  else
    made->add(path)
  endif
endfor

writefile(made, REPORT)
FI.CleanupProjectFiles(fixture)
