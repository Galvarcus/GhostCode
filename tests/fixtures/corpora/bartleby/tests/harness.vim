vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/harness.vim: runs the RunAll function of every test module, then
# reports the failures in v:errors, which every failed assert function
# fills, see :help testing.txt. Each test_*.vim file exports one RunAll
# that calls its own Test functions. Simpler and clearer than finding
# tests by reflection, for the cost of one line here per test file.
#
# Usage: vim -es -u NONE -N -c 'set rtp+=/path/to/bartleby,/path/to/Logger' \
#          -c 'source tests/harness.vim' -c 'quit'
#
# -u NONE skips Vim's normal startup, including the automatic
# :packloadall that adds a pack/*/start install, such as
# ~/.vim/pack/vendor/start/bartleby, to runtimepath. When Bartleby and
# Logger are installed that way, run :packloadall first instead of rtp+=:
#   vim -es -u NONE -N -c 'packloadall' \
#     -c 'source tests/harness.vim' -c 'quit'
# Run it from the root of the Bartleby repository, because it writes
# tests/results.txt relative to the current folder.
#
# The exit code is 0 on success and not 0 on any failed assertion, with
# cquit. A workflow reads tests/results.txt rather than the code, because
# Vim answers 2 for a run that reported failures of its own.
# License: GNU GPL 3.0
##############################################################################
# Tests contain UTF-8 text such as curly apostrophes. Without a UTF-8
# locale, with LANG unset, Vim starts with encoding latin1 and reads each
# such character as several bytes. Set it here, before any script or
# buffer loads, so results do not depend on the environment.
set encoding=utf-8

# The tests need Vim 9.2.1172 or later. Before it, a lambda that assigns to
# a member of a captured function argument, as test_compile_select.vim
# does, crashes Vim with a segmentation fault once the function has
# returned, and the run ends without a result. So fail first, with the
# reason. Only the tests rely on the fix. The plugin does not, so that it
# still runs on an older Vim.
# REFERENCE: https://github.com/vim/vim/issues/21460
# REFERENCE: https://github.com/vim/vim/commit/b2b47bdf9
if !has('patch-9.2.1172')
  var running: string = printf('%d.%d.%d', v:versionlong / 1000000,
    v:versionlong / 10000 % 100, v:versionlong % 10000)
  writefile([$'The tests need Vim 9.2.1172 or later, and this is Vim {running}. '
    .. 'Use the latest vim-appimage, or vim-win32-installer on Windows, as '
    .. '.github/actions/install-vim does.'],
    'tests/results.txt')
  cquit 1
endif

# Source plugin/bartleby.vim before any autoload file that reads a
# g:bartleby setting when it loads, as compile.vim does for the paths of
# Pandoc and screenplain. In a Vim session, plugin files load at startup
# and autoload files later, on first use. A harness that imports autoload
# files directly must do this itself.
execute 'source ' .. expand('<sfile>:h:h') .. '/plugin/bartleby.vim'

import './fixtures.vim' as FI
import './report.vim' as RE
import './test_tree.vim' as TT
import './test_mutate.vim' as TM
import './test_document.vim' as TD
import './test_compile.vim' as TC
import './test_compile_select.vim' as TCS
import './test_binder.vim' as TB
import './test_syntax.vim' as TSY
import './test_pos.vim' as TP
import './test_lang.vim' as TLA
import './test_i18n.vim' as TIN
import './test_profile.vim' as TPR
import './test_spotlight_pos.vim' as TSP
import './test_tty.vim' as TTY
import './test_trash.vim' as TTR
import './test_slug.vim' as TSG
import './test_snapshot.vim' as TSN
import './test_persist.vim' as TPE
import './test_tagger.vim' as TG
import './test_path.vim' as TPA
import './test_project.vim' as TPJ
import './test_recover.vim' as TRC
import './test_import.vim' as TIM
import './test_import_map.vim' as TIMM
import './test_wordcount.vim' as TWC
import './test_session.vim' as TSE
import './test_inspector.vim' as TIS
import './test_templates.vim' as TTE
import './test_restore.vim' as TRE
import './test_corkboard.vim' as TCB
import './test_focus.vim' as TFO
import './test_layout.vim' as TLY
import './test_scrivenings.vim' as TSV
import './test_progress.vim' as TPG
import './test_panes.vim' as TPN
import './test_closeall.vim' as TCL
import './test_menu.vim' as TME
import './test_lexiconpopup.vim' as TLP
import './test_inputpopup.vim' as TI
import './test_dialog_popup.vim' as TDP
import './test_outliner.vim' as TO
import './test_scrivelist.vim' as TSL
import './test_scrive.vim' as TSC
import './test_plugin.vim' as TPL
import './test_links.vim' as TLK
import './test_table.vim' as TTB
import './test_texcheck.vim' as TTX
import './test_doctemplates.vim' as TDT
import './test_lexicon.vim' as TL
import './test_binder_directory.vim' as TBD
import './test_autosave.vim' as TAU

const RESULT: string = 'tests/results.txt'
const PASS: string = 'All tests passed'

var suites: list<func(): void> = [
  TT.RunAll,
  TM.RunAll,
  TD.RunAll,
  TC.RunAll,
  TCS.RunAll,
  TB.RunAll,
  TSY.RunAll,
  TP.RunAll,
  TLA.RunAll,
  TIN.RunAll,
  TPR.RunAll,
  TSP.RunAll,
  TTY.RunAll,
  TTR.RunAll,
  TSG.RunAll,
  TSN.RunAll,
  TPE.RunAll,
  TG.RunAll,
  TPA.RunAll,
  TPJ.RunAll,
  TRC.RunAll,
  TIM.RunAll,
  TIMM.RunAll,
  TWC.RunAll,
  TSE.RunAll,
  TIS.RunAll,
  TTE.RunAll,
  TRE.RunAll,
  TCB.RunAll,
  TFO.RunAll,
  TLY.RunAll,
  TSV.RunAll,
  TPG.RunAll,
  TPN.RunAll,
  TCL.RunAll,
  TME.RunAll,
  TLP.RunAll,
  TI.RunAll,
  TDP.RunAll,
  TO.RunAll,
  TSL.RunAll,
  TSC.RunAll,
  TPL.RunAll,
  TLK.RunAll,
  TTB.RunAll,
  TTX.RunAll,
  TDT.RunAll,
  TL.RunAll,
  TBD.RunAll,
  TAU.RunAll,
]

# The number of each suite as it starts, in the order of the imports
# above, see Step in fixtures.vim for why a file.
var at: number = 0
FI.Step('start')
for Suite in suites
  at += 1
  FI.Step($'suite {at} of {len(suites)}')
  RE.Run(Suite, $'suite {at}')
endfor

if !RE.Report(RESULT, PASS)
  cquit 1
endif
