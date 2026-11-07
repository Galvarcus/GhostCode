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
/// of the table, so nothing here reads `g:flag = 1` as a command. The
/// prefix itself is dropped as Vim's scope notation, which is a rule
/// of its own, and the name the project chose keeps its reference.
#[test]
fn a_scoped_name_written_in_statement_position_is_still_a_reference() {
    let text = "vim9script\ng:flag = 1\n";

    assert_eq!(count(text, "flag"), 1);
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
