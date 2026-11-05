//! The names Vim9 owns: which references the scan marks as the
//! language's own rather than as a name this project could declare.
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

/// FUNCTION: Whether the references to a name are the language's own,
/// as a list, so that a snippet naming it twice shows both answers.
fn owned(text: &str, name: &str) -> Vec<bool> {
    refs(text)
        .iter()
        .filter(|r| r.name == name)
        .map(|r| r.owned)
        .collect()
}

#[test]
fn a_type_word_in_an_annotation_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var s: string\nenddef\n";

    assert_eq!(owned(text, "string"), vec![true]);
}

#[test]
fn a_return_type_is_the_languages_own() {
    let text = "vim9script\ndef F(): bool\n  return true\nenddef\n";

    assert_eq!(owned(text, "bool"), vec![true]);
}

#[test]
fn a_type_word_inside_another_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var l: list<dict<string>>\nenddef\n";

    assert_eq!(owned(text, "list"), vec![true]);
    assert_eq!(owned(text, "dict"), vec![true]);
    assert_eq!(owned(text, "string"), vec![true]);
}

/// A type word is also a builtin function, and a call is a call. The
/// builtins are a bucket of their own in the issue this belongs to.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_type_word_that_is_called_is_a_reference_like_any_other() {
    let text = "vim9script\ndef F()\n  var s = string(1)\nenddef\n";

    assert_eq!(owned(text, "string"), vec![false]);
}

#[test]
fn an_annotation_naming_a_class_is_a_reference_like_any_other() {
    let text = "vim9script\ndef F()\n  var m: Menu\nenddef\n";

    assert_eq!(
        owned(text, "Menu"),
        vec![false],
        "a project class must still be credited by the annotation naming it"
    );
}

#[test]
fn a_null_literal_is_the_languages_own() {
    let text = "vim9script\ndef F(): any\n  return null_object\nenddef\n";

    assert_eq!(owned(text, "null_object"), vec![true]);
}

/// An enum value may carry a reserved name, so a null literal is
/// marked rather than dropped: a reference the scan never emits
/// credits nothing, and the value would be reported as unreferenced.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_null_literal_is_still_a_reference() {
    let text = "vim9script\ndef F(): any\n  return null_object\nenddef\n";

    assert_eq!(
        refs(text)
            .iter()
            .filter(|r| r.name == "null_object")
            .count(),
        1
    );
}

#[test]
fn an_object_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var c: object<C>\nenddef\n";

    assert_eq!(owned(text, "object"), vec![true]);
}

/// The type of a parameter reached past the tokens a signature can
/// hold: `...` for a variadic argument and `?` for an optional one.
#[test]
fn a_type_inside_a_func_type_is_the_languages_own() {
    let text = "vim9script\ndef F()\n  var f: func(...list<blob>): void\n  var g: func(number, ?channel): bool\nenddef\n";

    assert_eq!(owned(text, "blob"), vec![true]);
    assert_eq!(owned(text, "channel"), vec![true]);
}

/// A dictionary entry whose value calls the builtin of a type word's
/// name: the value is a call, whatever the colon before it suggests.
#[test]
fn a_call_after_a_colon_is_a_reference_like_any_other() {
    let text = "vim9script\ndef F()\n  var d = {days: string(30)}\nenddef\n";

    assert_eq!(owned(text, "string"), vec![false]);
}
