vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartleby.vim: the plugin entry point, with the global settings, the
# commands, the mappings, and the autocommands. It only connects them to
# the work in autoload/bartleby.vim and autoload/bartleby/, and it calls
# nothing there while it loads, so that Vim starts as fast without
# Bartleby as with it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby.vim' as BA
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/commandpalette.vim' as CP
import autoload 'bartleby/bartlebymenu.vim' as BM
import autoload 'bartleby/scrivelist.vim' as SL
import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/lexiconpopup.vim' as LP
import autoload 'bartleby/autosave.vim' as A
import autoload 'bartleby/tty.vim' as TY
import autoload 'bartleby/closeall.vim' as CL
import autoload 'bartleby/progressview.vim' as PV
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/table.vim' as TB
import 'bartleby/variables/constants.vim' as CO

# Every g:bartleby setting, with its default. -1 and empty strings mean
# not set, for settings with no real default, such as the Focus margins
# and the Spotlight conceal colors.
g:bartleby_binder_root = get(g:, 'bartleby_binder_root', expand('~/Documents'))
g:bartleby_language = get(g:, 'bartleby_language', '')
g:bartleby_session_auto_restore = get(g:, 'bartleby_session_auto_restore', false)
g:bartleby_autosave = get(g:, 'bartleby_autosave', true)
g:bartleby_autosave_interval = get(g:, 'bartleby_autosave_interval', 30)
# The hour, 0 to 23, at which a writing day starts, for the daily goal.
g:bartleby_day_starts_at = get(g:, 'bartleby_day_starts_at', 0)
# Add the writing progress to the status line when it has no setting of
# its own. vim-airline shows it in the section g:bartleby_airline_section.
g:bartleby_statusline = get(g:, 'bartleby_statusline', true)
g:bartleby_airline_section = get(g:, 'bartleby_airline_section', 'y')
# No default keys, as for a user who maps the <Plug> mappings to keys of
# their own.
g:bartleby_no_mappings = get(g:, 'bartleby_no_mappings', false)
# Offer the titles of the documents after [[ in insert mode.
g:bartleby_link_complete = get(g:, 'bartleby_link_complete', true)
# Highlight the links, and the broken ones differently.
g:bartleby_link_highlight = get(g:, 'bartleby_link_highlight', true)
# Line up a table when you leave insert mode in it.
g:bartleby_table_autoformat = get(g:, 'bartleby_table_autoformat', true)
# Your templates for new documents, which add to those of Bartleby, see
# autoload/bartleby/doctemplates.vim.
g:bartleby_doc_templates_dir = get(g:, 'bartleby_doc_templates_dir', '')
g:bartleby_snapshot_retention = get(g:, 'bartleby_snapshot_retention', 5)
g:bartleby_binder_show_role_labels = get(g:, 'bartleby_binder_show_role_labels', true)
g:bartleby_focus_width = get(g:, 'bartleby_focus_width', 80)
g:bartleby_focus_height = get(g:, 'bartleby_focus_height', '85%')
g:bartleby_focus_margin_top = get(g:, 'bartleby_focus_margin_top', -1)
g:bartleby_focus_margin_bottom = get(g:, 'bartleby_focus_margin_bottom', -1)
g:bartleby_focus_linenr = get(g:, 'bartleby_focus_linenr', 0)
g:bartleby_focus_bg = get(g:, 'bartleby_focus_bg', 'black')
g:bartleby_focus_fullscreen = get(g:, 'bartleby_focus_fullscreen', false)
g:bartleby_focus_guifont = get(g:, 'bartleby_focus_guifont', '')
g:bartleby_tty_colors = get(g:, 'bartleby_tty_colors', true)
g:bartleby_spotlight_default_coefficient = get(g:, 'bartleby_spotlight_default_coefficient', 0.5)
g:bartleby_spotlight_conceal_guifg = get(g:, 'bartleby_spotlight_conceal_guifg', '')
g:bartleby_spotlight_conceal_ctermfg = get(g:, 'bartleby_spotlight_conceal_ctermfg', '')
g:bartleby_spotlight_bop = get(g:, 'bartleby_spotlight_bop', '^\s*$\n\zs')
g:bartleby_spotlight_eop = get(g:, 'bartleby_spotlight_eop', '^\s*$')
g:bartleby_spotlight_paragraph_span = get(g:, 'bartleby_spotlight_paragraph_span', 0)
g:bartleby_spotlight_priority = get(g:, 'bartleby_spotlight_priority', 10)
g:bartleby_spotlight_dialogue_pattern = get(g:, 'bartleby_spotlight_dialogue_pattern', '')
g:bartleby_spotlight_tagger = get(g:, 'bartleby_spotlight_tagger', '')
g:bartleby_spotlight_spacy_model = get(g:, 'bartleby_spotlight_spacy_model', '')
g:bartleby_spotlight_words_add = get(g:, 'bartleby_spotlight_words_add', {})
g:bartleby_spotlight_words_remove = get(g:, 'bartleby_spotlight_words_remove', {})
g:bartleby_quill_wrap_mode_default = get(g:, 'bartleby_quill_wrap_mode_default', 'hard')
g:bartleby_quill_textwidth = get(g:, 'bartleby_quill_textwidth', 74)
g:bartleby_quill_autoformat = get(g:, 'bartleby_quill_autoformat', true)
g:bartleby_quill_autoformat_config = get(g:, 'bartleby_quill_autoformat_config', {
  markdown: {
    black: [
      'htmlH[0-9]',
      'markdown(Code|H[0-9]|Url|IdDeclaration|Link|Rule|Highlight[A-Za-z0-9]+)',
      'markdown(FencedCodeBlock|InlineCode|YamlHead)',
    ],
    white: ['markdown(Code|Link)'],
  },
})
g:bartleby_quill_autoformat_aliases = get(g:, 'bartleby_quill_autoformat_aliases',
  {md: 'markdown', mkd: 'markdown', fountain: 'markdown'})
g:bartleby_quill_joinspaces = get(g:, 'bartleby_quill_joinspaces', false)
g:bartleby_quill_cursorwrap = get(g:, 'bartleby_quill_cursorwrap', true)
g:bartleby_quill_conceallevel = get(g:, 'bartleby_quill_conceallevel', 3)
g:bartleby_quill_concealcursor = get(g:, 'bartleby_quill_concealcursor', 'c')
g:bartleby_quill_soft_detect_sample = get(g:, 'bartleby_quill_soft_detect_sample', 20)
g:bartleby_quill_soft_detect_threshold = get(g:, 'bartleby_quill_soft_detect_threshold', 130)
g:bartleby_quill_auto = get(g:, 'bartleby_quill_auto', true)
g:bartleby_compile_pandoc_bin = get(g:, 'bartleby_compile_pandoc_bin', 'pandoc')
g:bartleby_compile_screenplain_bin = get(g:, 'bartleby_compile_screenplain_bin', 'screenplain')
g:bartleby_compile_toc = get(g:, 'bartleby_compile_toc', false)
g:bartleby_compile_standalone = get(g:, 'bartleby_compile_standalone', true)
g:bartleby_compile_manuscript_font = get(g:, 'bartleby_compile_manuscript_font', 'Courier New')
g:bartleby_compile_book_font = get(g:, 'bartleby_compile_book_font', 'Georgia')
g:bartleby_compile_screenplay_font = get(g:, 'bartleby_compile_screenplay_font', 'Courier Prime')
g:bartleby_compile_manuscript_double_spaced = get(g:, 'bartleby_compile_manuscript_double_spaced', true)
g:bartleby_compile_indent_paragraphs = get(g:, 'bartleby_compile_indent_paragraphs', true)
g:bartleby_compile_book_chapter_style = get(g:, 'bartleby_compile_book_chapter_style', 'numeral')
g:bartleby_compile_book_part_style = get(g:, 'bartleby_compile_book_part_style', 'numeral')
g:bartleby_compile_extra_args = get(g:, 'bartleby_compile_extra_args', [])
g:bartleby_compile_lang = get(g:, 'bartleby_compile_lang', '')
g:bartleby_compile_papersize = get(g:, 'bartleby_compile_papersize', '')
g:bartleby_compile_log_retention = get(g:, 'bartleby_compile_log_retention', 10)
# Tables: the frame, the lines between columns, none or single, and the
# style of the header: bold, italic, smallcaps, or plain.
g:bartleby_compile_table_border = get(g:, 'bartleby_compile_table_border', 'none')
g:bartleby_compile_table_vlines = get(g:, 'bartleby_compile_table_vlines', 'none')
g:bartleby_compile_table_header = get(g:, 'bartleby_compile_table_header', 'bold')
g:bartleby_dictionary_api_key = get(g:, 'bartleby_dictionary_api_key', '')
g:bartleby_thesaurus_api_key = get(g:, 'bartleby_thesaurus_api_key', '')
g:bartleby_dictionary_reference = get(g:, 'bartleby_dictionary_reference', '')
g:bartleby_thesaurus_reference = get(g:, 'bartleby_thesaurus_reference', '')
g:bartleby_lexicon_cache_max_entries = get(g:, 'bartleby_lexicon_cache_max_entries', 1000)
g:bartleby_lexicon_timeout = get(g:, 'bartleby_lexicon_timeout', 10)
g:bartleby_lexicon_base_url = get(g:, 'bartleby_lexicon_base_url',
  'https://www.dictionaryapi.com/api/v3/references')






command! -bar -nargs=? -complete=customlist,bartleby#scrive#CompleteNames
  \ BartlebyOpen BA.OpenScrive(<q-args>)
command! -bar -nargs=1 BartlebyNewScrive BA.NewScrive(<q-args>)
# The whole argument is the path, so a path with spaces needs no
# escaping. See NewScriveFrom in autoload/bartleby.vim.
command! -bar -nargs=1 -complete=file BartlebyNewScriveFrom BA.NewScriveFrom(<q-args>)
command! -bar BartlebyList SL.Show()
command! -bar BartlebyTable TB.Edit()
command! -bar BartlebyTableFormat TB.FormatCmd()
command! -bar BartlebyToggleBinder BA.ToggleBinder()
command! -bar BartlebySearch BA.RunSearch()
command! -bar BartlebyToggleInspector I.Toggle()
command! -bar -bang -nargs=? BartlebyFocus F.Execute('<bang>' ==# '!', <q-args>)
command! -bar -bang -nargs=? BartlebySpotlight SP.Execute('<bang>' ==# '!', <q-args>)




command! -bar -nargs=? BartlebyQuill Q.Init(<q-args> ==# '' ? 'detect' : <q-args>)
command! -bar BartlebySnapshot BA.SnapCurDoc()
command! -bar BartlebySnapshots BA.ViewSnapsForCurDoc()
command! -bar BartlebyProfile PR.EditGlobal()
command! -bar BartlebyProjectInfo BA.EditProjectInfo()


command! -bar BartlebyCompile BA.RunCompile()


command! -bar BartlebyEmptyTrash BA.EmptyTrash()


command! -bar -nargs=? -complete=customlist,bartleby#scrive#CompleteNames
  \ BartlebyRecover BA.Recover(<q-args>)


command! -bar BartlebyTidyFiles BA.TidyFiles()


# A path is a file or a folder. With no path, the command asks for one. A
# path may hold ~ and wildcards, which Vim does not expand in a command
# argument, so import.vim does.
command! -bar -nargs=* -complete=file BartlebyImport BA.Import([<f-args>])


command! -bar -bang BartlebyScrivenings BA.OpenScrivening('<bang>' ==# '!')
command! -bar -bang BartlebyClose CL.All('<bang>' ==# '!')
command! -bar BartlebyGoals PV.EditGoals()
command! -bar BartlebyProgress PV.Show()
command! -bar BartlebyCommands CP.Open()
command! -bar BartlebyMenu BM.Toggle()
command! -bar -nargs=? BartlebyDefine LP.LookupCmd(CO.KIND_DICT, <q-args>)
command! -bar -nargs=? BartlebyThesaurus LP.LookupCmd(CO.KIND_THESAURUS, <q-args>)
command! -bar BartlebyLexiconClearCache LE.ClearCache()

# The mappings: mode, default keys, <Plug> name, and action. A user can map
# the <Plug> name to keys of their own. The default keys are mapped unless
# the user has already mapped that <Plug> name in that mode, or has set
# g:bartleby_no_mappings. The lookup keys exist without an API key too: a
# lookup then says what is missing, as the commands do.
const MAPPINGS: list<list<string>> = [
  ['n', '<leader>bi', 'BartlebyInspector', '<ScriptCmd>I.Toggle()<CR>'],
  ['n', '<leader>bz', 'BartlebyFocus', '<ScriptCmd>F.Toggle()<CR>'],
  ['n', '<leader>bl', 'BartlebySpotlight', '<ScriptCmd>SP.Toggle()<CR>'],
  ['n', '<leader>bL', 'BartlebySpotlightMode', '<ScriptCmd>SP.PickMode()<CR>'],
  ['n', '<leader>bp', 'BartlebyQuill', '<ScriptCmd>Q.Toggle()<CR>'],
  ['n', '<leader>b<Space>', 'BartlebyCommands', '<ScriptCmd>CP.Open()<CR>'],
  ['n', '<leader>bm', 'BartlebyMenu', '<ScriptCmd>BM.Toggle()<CR>'],
  ['n', '<leader>bd', 'BartlebyDefine', '<ScriptCmd>LP.LookupAtCursor(CO.KIND_DICT)<CR>'],
  ['x', '<leader>bd', 'BartlebyDefine', '<Esc><ScriptCmd>LP.LookupVisual(CO.KIND_DICT)<CR>'],
  ['n', '<leader>bt', 'BartlebyThesaurus', '<ScriptCmd>LP.LookupAtCursor(CO.KIND_THESAURUS)<CR>'],
  ['x', '<leader>bt', 'BartlebyThesaurus', '<Esc><ScriptCmd>LP.LookupVisual(CO.KIND_THESAURUS)<CR>'],
  ['n', 'gf', 'BartlebyFollowLink', '<ScriptCmd>LK.Follow()<CR>'],
  ['n', '<leader>b<Bar>', 'BartlebyTable', '<ScriptCmd>TB.Edit()<CR>'],
]

for [m, lhs, name, rhs] in MAPPINGS
  execute $'{m}noremap <silent> <Plug>({name}) {rhs}'
  if !g:bartleby_no_mappings && !hasmapto($'<Plug>({name})', m)
    execute $'{m}map {lhs} <Plug>({name})'
  endif
endfor

# Colors for a console with 8 or 16 colors, after the vimrc has chosen a
# color scheme or not. A plugin that loads late has missed VimEnter.
if v:vim_did_enter
  TY.AutoApply()
else
  augroup bartleby_tty_colors
    autocmd!
    # nested, so that the ColorScheme event of the scheme still fires.
    autocmd VimEnter * ++once ++nested TY.AutoApply()
  augroup END
endif



# Auto-save for scrive documents, see autoload/bartleby/autosave.vim.
# Tables line up when you leave insert mode on a row, in any buffer. The
# row is checked here, so that table.vim loads only for a table.
augroup bartleby_table
  autocmd!
  autocmd InsertLeave * if getline('.') =~# CO.TABLE_ROW_PAT | TB.OnInsertLeave() | endif
augroup END

augroup bartleby_autosave
  autocmd!
  autocmd CursorHold,InsertLeave * A.Save(false)
  autocmd FocusLost,BufLeave * A.Save(true)
augroup END

augroup bartleby_session
  autocmd!
  autocmd CursorHold * SS.CaptureCurDoc()
  autocmd VimLeavePre * SS.CaptureCurDoc()
  # The setting is checked here, so that bartleby.vim loads at startup
  # only to restore a scrive.
  autocmd VimEnter * if g:bartleby_session_auto_restore | BA.AutoRestoreSession() | endif
augroup END

# The native menu waits for GUIEnter, so that loading the plugin loads
# no autoload script in gVim either. A plugin that loads late has missed
# GUIEnter.
if v:vim_did_enter && has('gui_running')
  BM.RegisterNative()
else
  augroup bartleby_menu
    autocmd!
    autocmd GUIEnter * ++once BM.RegisterNative()
  augroup END
endif
