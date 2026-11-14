//! Vim's own commands: which words the scan keeps out of the
//! reference list because they stand where Vim reads a command.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;

/// FUNCTION: Every reference one snippet emits.
fn refs(text: &str) -> Vec<Reference> {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found.refs
}

/// FUNCTION: How many references a snippet emits for one name.
fn count(text: &str, name: &str) -> usize {
    refs(text).iter().filter(|r| r.name == name).count()
}

#[test]
fn a_bare_command_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  redraw\nenddef\n";

    assert_eq!(count(text, "redraw"), 0);
}

#[test]
fn a_bare_command_at_script_level_is_not_a_reference() {
    let text = "vim9script\nredrawstatus\n";

    assert_eq!(count(text, "redrawstatus"), 0);
}

#[test]
fn a_command_after_a_modifier_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  noautocmd redraw\nenddef\n";

    assert_eq!(count(text, "redraw"), 0);
}

/// The head of the statement is the only place Vim reads a command.
/// `echo` is itself a command, so a word after one is a value, and a
/// project may well declare it.
#[test]
fn a_command_word_used_as_a_value_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  echo redraw\nenddef\n";

    assert_eq!(count(text, "redraw"), 1);
}

#[test]
fn a_variable_written_in_statement_position_is_still_a_reference() {
    let text = "vim9script\nvar copy = 1\ncopy = 2\n";

    assert_eq!(count(text, "copy"), 1);
}

#[test]
fn a_variable_indexed_in_statement_position_is_still_a_reference() {
    let text = "vim9script\nvar copy = [1]\ncopy[0] = 2\n";

    assert_eq!(count(text, "copy"), 1);
}

#[test]
fn a_variable_reached_through_an_arrow_is_still_a_reference() {
    let text = "vim9script\nvar sort = []\nsort->add(1)\n";

    assert_eq!(count(text, "sort"), 1);
}

/// A scope prefix is one letter, and a name of one letter is left out
/// of the table, so nothing here reads `g:flags->add(1)` as a command.
/// The variable is read by its full spelling, and the name behind the
/// scope is no bare name of the project.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
#[test]
fn a_scoped_name_read_in_statement_position_is_still_a_reference() {
    let text = "vim9script\ng:flags->add(1)\n";

    assert_eq!(count(text, "g:flags"), 1);
    assert_eq!(count(text, "flags"), 0);
}

#[test]
fn a_project_function_called_in_statement_position_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  Setup()\nenddef\n";

    assert_eq!(count(text, "Setup"), 1);
}

/// A command word is Vim's at the head of a statement and the
/// project's anywhere else. A project that declares a variable of
/// such a name keeps every read of it.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
#[test]
fn a_variable_named_after_a_command_keeps_the_read_of_it() {
    let text = "vim9script\nvar set = 1\ndef F()\n  echo set\nenddef\n";

    assert_eq!(count(text, "set"), 1);
}

#[test]
fn a_command_word_at_the_head_of_a_statement_is_still_not_a_reference() {
    let text = "vim9script\ndef F()\n  echo 1\nenddef\n";

    assert_eq!(count(text, "echo"), 0);
}

/// FUNCTION: The reference one snippet emits for a name, with its mark.
fn one(text: &str, name: &str) -> Reference {
    refs(text)
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// Vim accepts any unambiguous prefix of a command, and 43 of the
/// lowercase names the corpora declare are themselves a legal
/// abbreviation, so the word is marked as the language's rather than
/// dropped: a project symbol of that spelling still takes the credit.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/31
#[test]
fn an_abbreviated_command_at_the_head_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  bwipe 3\nenddef\n";

    assert!(one(text, "bwipe").owned);
}

#[test]
fn a_command_written_whole_at_the_head_is_dropped() {
    let text = "vim9script\ndef F()\n  bwipeout 3\nenddef\n";

    assert_eq!(count(text, "bwipeout"), 0);
}

#[test]
fn an_abbreviated_mapping_command_hides_its_notation() {
    let text = "vim9script\nnn <buffer> x Fn()\n";

    assert_eq!(count(text, "buffer"), 0);
    assert_eq!(count(text, "Fn"), 1);
}

#[test]
fn an_abbreviated_command_definition_keeps_the_name_it_declares() {
    let text = "vim9script\ncom! -nargs=1 Recover BA.Recover(<q-args>)\n";

    assert_eq!(count(text, "args"), 0);
    assert_eq!(count(text, "Recover"), 1);
}

#[test]
fn an_abbreviated_modifier_leaves_the_command_at_the_head() {
    let text = "vim9script\ndef F()\n  sil! bwipe 3\nenddef\n";

    assert!(one(text, "sil").owned);
    assert!(one(text, "bwipe").owned);
}

/// A bar ends one command and starts the next, so Vim reads a command
/// after it as surely as at the head of the line.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_command_after_a_bar_is_not_a_reference() {
    let text = "vim9script\ndef F()\n  if g:flag | echo 1 | endif\nenddef\n";

    assert_eq!(count(text, "echo"), 0);
}

#[test]
fn a_call_after_a_bar_keeps_its_reference() {
    let text = "vim9script\nautocmd VimEnter * if g:flag | Fn() | endif\n";

    assert_eq!(count(text, "Fn"), 1);
}

/// A range stands between the colon and the command, so the command
/// behind it is where Vim reads one, as it is with no range. `bwipe`
/// abbreviates `bwipeout`, so it is marked rather than dropped.
#[test]
fn an_abbreviated_command_behind_a_range_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  silent! :%bwipe!\nenddef\n";

    assert!(one(text, "bwipe").owned);
}

#[test]
fn a_command_written_whole_behind_a_range_is_dropped() {
    let text = "vim9script\ndef F()\n  :%bwipeout!\nenddef\n";

    assert_eq!(count(text, "bwipeout"), 0);
}

#[test]
fn a_command_behind_a_colon_alone_is_dropped() {
    let text = "vim9script\ndef F()\n  :bwipeout!\nenddef\n";

    assert_eq!(count(text, "bwipeout"), 0);
}

#[test]
fn a_command_behind_a_range_of_lines_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  :1,$ bwipe\nenddef\n";

    assert!(one(text, "bwipe").owned);
}

#[test]
fn a_command_behind_an_offset_from_the_current_line_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  :.;.+2 bwipe\nenddef\n";

    assert!(one(text, "bwipe").owned);
}

/// A colon inside an expression opens no command: the word behind
/// the colon of a conditional is a value.
#[test]
fn a_value_behind_the_colon_of_a_conditional_is_not_marked() {
    let text = "vim9script\ndef F()\n  echo ok ? 1 : bwipe\nenddef\n";

    assert!(!one(text, "bwipe").owned);
}

/// A lambda written as a block holds whole commands, and the lexer
/// keeps the block in the statement that opens it, so each line of
/// the block is where Vim reads a command.
#[test]
fn a_command_on_the_first_line_of_a_lambda_block_is_dropped() {
    let text = "vim9script\ndef F()\n  timer_start(0, (_) => {\n    execute Cmd\n  })\nenddef\n";

    assert_eq!(count(text, "execute"), 0);
}

#[test]
fn a_command_on_a_later_line_of_a_lambda_block_is_dropped() {
    let text =
        "vim9script\ndef F()\n  timer_start(0, (_) => {\n    G()\n    redraw\n  })\nenddef\n";

    assert_eq!(count(text, "redraw"), 0);
}

#[test]
fn a_command_behind_a_modifier_in_a_lambda_block_is_dropped() {
    let text = "vim9script\ndef F()\n  timer_start(0, (_) => {\n    silent! redraw\n  })\nenddef\n";

    assert_eq!(count(text, "redraw"), 0);
}

#[test]
fn a_command_in_a_lambda_block_past_a_nested_block_is_dropped() {
    let text = "vim9script\ndef F()\n  A(() => {\n    B(() => {\n      G()\n    })\n    redraw\n  })\nenddef\n";

    assert_eq!(count(text, "redraw"), 0);
}

/// A line that continues an expression inside the block opens no
/// command, so a word there keeps its reference.
#[test]
fn a_value_on_a_continued_line_of_a_lambda_block_keeps_its_reference() {
    let text = "vim9script\ndef F()\n  A(() => {\n    G(1,\n      redraw)\n  })\nenddef\n";

    assert_eq!(count(text, "redraw"), 1);
}

/// A dictionary a lambda returns is no block, so its first key line
/// opens no command.
#[test]
fn a_value_in_a_dictionary_a_lambda_returns_keeps_its_reference() {
    let text = "vim9script\ndef F()\n  A(() => ({\n    k: 1,\n    v: [\n      redraw]}))\nenddef\n";

    assert_eq!(count(text, "redraw"), 1);
}

#[test]
fn a_value_after_a_command_in_a_lambda_block_keeps_its_reference() {
    let text = "vim9script\ndef F()\n  A(() => {\n    echo redraw\n  })\nenddef\n";

    assert_eq!(count(text, "redraw"), 1);
}

/// The argument of a command that names something Vim keeps: a
/// highlight group, a color scheme, a locale, a filetype. The
/// project declares nothing one of them could mean.
#[test]
fn the_group_an_echohl_command_names_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  echohl ErrorMsg\nenddef\n";

    assert!(one(text, "ErrorMsg").owned);
}

#[test]
fn the_scheme_a_colorscheme_command_names_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  colorscheme default\nenddef\n";

    assert!(one(text, "default").owned);
}

#[test]
fn the_category_a_language_command_names_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  language messages de_DE.UTF-8\nenddef\n";

    assert!(one(text, "messages").owned);
}

#[test]
fn the_locale_a_language_command_names_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  language messages de_DE.UTF-8\nenddef\n";

    assert!(one(text, "de_DE").owned);
}

#[test]
fn the_filetype_a_setfiletype_command_names_is_marked_as_vims() {
    let text = "vim9script\nautocmd BufRead,BufNewFile *.fountain setfiletype fountain\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "fountain")
        .all(|r| r.owned));
}

/// A command ends at a bar, and the word behind the bar is no
/// argument of it.
#[test]
fn a_value_behind_the_bar_of_an_echohl_command_is_not_marked() {
    let text = "vim9script\ndef F()\n  echohl None | echo Later\nenddef\n";

    assert!(!one(text, "Later").owned);
}

/// A word with a capital at the head of a statement is a user
/// command: Vim9 script reads nothing else there unless the word is
/// called, reached into or assigned to.
#[test]
fn a_user_command_with_a_bang_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  PluginOpen!\nenddef\n";

    assert!(one(text, "PluginOpen").owned);
}

#[test]
fn a_user_command_with_an_argument_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  PluginOpen draft\nenddef\n";

    assert!(one(text, "PluginOpen").owned);
}

#[test]
fn a_function_called_at_the_head_of_a_statement_is_not_marked() {
    let text = "vim9script\ndef F()\n  PluginOpen()\nenddef\n";

    assert!(!one(text, "PluginOpen").owned);
}

#[test]
fn a_class_reached_into_at_the_head_of_a_statement_is_not_marked() {
    let text = "vim9script\ndef F()\n  Menu.Open()\nenddef\n";

    assert!(!one(text, "Menu").owned);
}

#[test]
fn a_word_with_a_capital_behind_a_command_is_not_marked() {
    let text = "vim9script\ndef F()\n  echo PluginOpen\nenddef\n";

    assert!(!one(text, "PluginOpen").owned);
}

/// `:messages` takes a keyword or a count, and nothing of the project.
#[test]
fn the_keyword_a_messages_command_takes_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  messages clear\nenddef\n";

    assert!(one(text, "clear").owned);
}

#[test]
fn the_file_a_source_command_names_is_marked_as_vims() {
    let text = "vim9script\nsource plugin/logger.vim\n";

    assert!(one(text, "logger").owned);
}

/// A legacy `:function` line states parameters and flags, and none
/// of them is a name the project could declare.
#[test]
fn a_flag_behind_a_legacy_function_signature_is_marked_as_vims() {
    let text = "function! plug#ext#init(ext) abort\nendfunction\n";

    assert!(one(text, "abort").owned);
}

#[test]
fn a_parameter_of_a_legacy_function_is_marked_as_vims() {
    let text = "function! plug#ext#init(ext) abort\nendfunction\n";

    assert!(one(text, "ext").owned);
}

/// `a:` holds the arguments of a legacy function and `l:` its
/// variables, so the name behind either is no symbol of the project.
#[test]
fn a_name_behind_the_argument_scope_is_marked_as_vims() {
    let text = "function! F(ext)\n  call a:ext.add('x')\nendfunction\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "ext")
        .all(|r| r.owned));
}

#[test]
fn a_name_behind_the_local_scope_is_marked_as_vims() {
    let text = "function! F()\n  let l:space = g:sep . l:space\nendfunction\n";

    assert!(refs(text)
        .iter()
        .filter(|r| r.name == "space")
        .all(|r| r.owned));
}

/// The colon of a conditional stands apart from the names around it,
/// so the name behind it is a value.
#[test]
fn a_value_behind_the_colon_of_a_conditional_named_like_a_scope_is_not_marked() {
    let text = "vim9script\ndef F(a: bool, l: number)\n  echo a ? l : Width\nenddef\n";

    assert!(!one(text, "Width").owned);
}

/// `function()` is a builtin, and what it is called with is a value.
#[test]
fn an_argument_of_the_function_builtin_is_not_marked() {
    let text = "vim9script\ndef F()\n  var R = function(Width)\nenddef\n";

    assert!(!one(text, "Width").owned);
}

/// Most commands of Vim take text and no expression, so their
/// arguments are Vim's: a file, a keyword, a register, an event.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/108
#[test]
fn the_arguments_of_a_command_that_takes_text_are_marked_as_vims() {
    let text =
        "vim9script\nedit foo.txt\nfiletype plugin on\nwincmd p\nredir END\npackadd matchit\n";

    for word in ["foo", "plugin", "on", "p", "END", "matchit"] {
        assert!(one(text, word).owned, "{word}");
    }
}

#[test]
fn the_argument_of_a_command_that_takes_an_expression_is_still_a_name() {
    let text = "vim9script\nreturn Helper\n";

    assert!(!one(text, "Helper").owned);
}

#[test]
fn the_command_a_command_runs_is_still_read_as_one() {
    let text = "vim9script\nwindo Helper()\n";

    assert!(!one(text, "Helper").owned);
}

/// The pattern of `:catch` is text that Vim matches, not code.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/92
#[test]
fn the_pattern_of_a_catch_command_is_marked_as_vims() {
    let text = "vim9script\ntry\n  echo 1\ncatch /^Vim\\%((\\a\\+)\\)\\?:E11/\nendtry\n";

    for word in ["Vim", "a", "E11"] {
        assert!(one(text, word).owned, "{word}");
    }
}

/// A modifier may stand before the colon and the range of the command
/// it modifies, and Vim reads the command behind both.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/109
#[test]
fn a_command_behind_a_modifier_a_colon_and_a_range_is_found() {
    let text = "vim9script\n:silent! :%d _\n:silent :1,$delete\n";

    assert!(one(text, "d").owned);
    assert_eq!(count(text, "delete"), 0);
    assert!(one(text, "_").owned);
}

/// The table missed six commands whose row in the help index has spaces
/// in place of a tab, `:scriptencoding` among them.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/110
#[test]
fn scriptencoding_is_a_command_and_its_argument_is_vims() {
    let text = "vim9script\nscriptencoding utf-8\n";

    assert_eq!(count(text, "scriptencoding"), 0);
    assert!(one(text, "utf").owned);
}

#[test]
fn the_argument_of_vim9script_is_vims() {
    let text = "vim9script noclear\necho 1\n";

    assert!(one(text, "noclear").owned);
}

/// The body of a user command gets its arguments as `<args>`. They can
/// be an expression there, but a mark still credits a symbol of its
/// spelling, so no finding is lost.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/111
#[test]
fn the_arguments_of_a_user_command_are_marked_as_vims() {
    let text = "vim9script\nDiag next\n:2Diag prev\n";

    assert!(one(text, "next").owned);
    assert!(one(text, "prev").owned);
}

#[test]
fn the_arguments_of_a_user_command_in_an_executed_string_are_marked_as_vims() {
    let text = "vim9script\nexecute('Diag show')\n";

    assert!(one(text, "show").owned);
}

#[test]
fn a_bar_ends_the_arguments_of_a_user_command() {
    let text = "vim9script\nDiag next | echo Helper\n";

    assert!(!one(text, "Helper").owned);
}
