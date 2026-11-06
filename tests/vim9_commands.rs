//! A `:command` definition: which of its words are Vim's own, and
//! which are the project's, so that the one credit the line carries
//! survives the words around it.
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
    Vim9.scan(&source("plugin/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found.refs
}

/// FUNCTION: How many references a snippet emits for one name.
fn count(text: &str, name: &str) -> usize {
    refs(text).iter().filter(|r| r.name == name).count()
}

/// Vim's attribute words stand where a name would stand, and a
/// project that declares a symbol called `bar` or `complete` would be
/// credited by every command definition in the plugin.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_attribute_of_a_command_is_not_a_reference() {
    let text = "vim9script\ncommand! -bar -nargs=? -bang BarFoo Run()\n";

    assert_eq!(count(text, "bar"), 0);
    assert_eq!(count(text, "nargs"), 0);
    assert_eq!(count(text, "bang"), 0);
}

#[test]
fn a_completion_kind_is_not_a_reference() {
    let text = "vim9script\ncommand! -nargs=1 -complete=file BarFoo Run()\n";

    assert_eq!(count(text, "complete"), 0);
    assert_eq!(count(text, "file"), 0);
}

/// The one credit a command line carries beyond its body: the
/// completion function, named after the comma of `customlist,` or
/// `custom,`. Dropping it would report a function the plugin uses.
#[test]
fn a_completion_function_after_a_comma_is_still_a_reference() {
    let text = "vim9script\ncommand! -nargs=? -complete=customlist,CompleteNames BarFoo Run()\n";

    assert_eq!(count(text, "customlist"), 0);
    assert_eq!(count(text, "CompleteNames"), 1);
}

#[test]
fn a_hashed_completion_function_is_still_a_reference() {
    let text = "vim9script\ncommand! -complete=custom,p#scrive#Complete BarFoo Run()\n";

    assert_eq!(count(text, "p#scrive#Complete"), 1);
}

/// The command's own name is declared here, exactly as a `var` line
/// declares its name, so the line is not a use of it.
#[test]
fn the_name_a_command_declares_is_not_a_reference() {
    let text = "vim9script\ncommand! -bar BarFoo Run()\n";

    assert_eq!(count(text, "BarFoo"), 0);
}

/// Everything after the name is the handler, and it is often the sole
/// caller of the function it names.
#[test]
fn the_handler_of_a_command_is_still_a_reference() {
    let text = "vim9script\ncommand! -bar -nargs=? BarFoo L.Run(Arg())\n";

    assert_eq!(count(text, "Run"), 1);
    assert_eq!(count(text, "Arg"), 1);
}

/// A command's arguments reach its handler through Vim's own
/// notation, which is three tokens of nothing the project declares.
#[test]
fn vims_argument_notation_in_a_command_body_is_not_a_reference() {
    let text = "vim9script\ncommand! -nargs=* BarFoo L.Run([<f-args>], <q-args>)\n";

    assert_eq!(count(text, "f"), 0);
    assert_eq!(count(text, "q"), 0);
    assert_eq!(count(text, "args"), 0);
    assert_eq!(count(text, "Run"), 1);
}

/// A comparison in the body is not notation, so the names it reads
/// are still references.
#[test]
fn a_comparison_in_a_command_body_is_still_a_reference() {
    let text = "vim9script\ncommand! -bar BarFoo echo Lhs < Rhs\n";

    assert_eq!(count(text, "Lhs"), 1);
    assert_eq!(count(text, "Rhs"), 1);
}

/// The attributes and the name may sit on different physical lines,
/// which the lexer joins into one statement.
#[test]
fn a_command_continued_onto_another_line_is_one_definition() {
    let text = "vim9script\ncommand! -bar -nargs=? -complete=customlist,CompleteNames\n  \\ BarFoo L.Run(<q-args>)\n";

    assert_eq!(count(text, "bar"), 0);
    assert_eq!(count(text, "BarFoo"), 0);
    assert_eq!(count(text, "CompleteNames"), 1);
    assert_eq!(count(text, "Run"), 1);
}

/// Removing a command names it without using anything of the
/// project's.
#[test]
fn delcommand_does_not_use_the_name_it_removes() {
    let text = "vim9script\ndelcommand BarFoo\n";

    assert_eq!(count(text, "BarFoo"), 0);
}

/// A command may stand behind a modifier, which the head of the
/// statement looks through.
#[test]
fn a_command_behind_a_modifier_is_still_a_definition() {
    let text = "vim9script\nsilent command! -bar BarFoo L.Run()\n";

    assert_eq!(count(text, "bar"), 0);
    assert_eq!(count(text, "BarFoo"), 0);
    assert_eq!(count(text, "Run"), 1);
}
