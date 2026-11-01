vim9script

##############################################################################
# Plugin_Name: Bartleby
# .github/scripts/smoke-font.vim: write the font family that the Book
# compiles of the smoke suite ask fontspec for, for check-windows-tools.sh
# to assert before the suites run. It asks fixtures.vim, which the suite
# asks as well, so the family has one source.
# License: GNU GPL 3.0
##############################################################################

# The fixture of the tests, by a path relative to this script, because
# tests/ is not on the runtimepath.
import '../../tests/fixtures.vim' as FI

const REPORT: string = 'tests/font_results.txt'

writefile([FI.SMOKE_FONT], REPORT)
