//! An enum body: which names a value's own line declares rather than
//! uses, so that a value nothing reads can be reported.
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

/// The line that lists a value declares it, exactly as a `var` line
/// declares its name, so the line is not a use of it.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
#[test]
fn a_value_line_does_not_use_the_value_it_declares() {
    let text = "vim9script\nenum Mode\n  Alpha\nendenum\n";

    assert_eq!(count(text, "Alpha"), 0);
}

#[test]
fn a_value_line_declares_every_value_on_it() {
    let text = "vim9script\nenum Mode\n  Alpha, Beta\nendenum\n";

    assert_eq!(count(text, "Alpha"), 0);
    assert_eq!(count(text, "Beta"), 0);
}

#[test]
fn a_value_that_takes_arguments_is_still_declared() {
    let text = "vim9script\nenum Colour\n  Blue('b'),\n  Red('r')\nendenum\n";

    assert_eq!(count(text, "Blue"), 0);
    assert_eq!(count(text, "Red"), 0);
}

/// A read of a value anywhere else is a use, and carries the enum as
/// its receiver.
#[test]
fn a_read_of_a_value_is_still_a_reference() {
    let text = "vim9script\nenum Mode\n  Alpha\nendenum\ndef F()\n  echo Mode.Alpha\nenddef\n";

    assert_eq!(count(text, "Alpha"), 1);
    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "Alpha")
            .and_then(|r| r.recv.clone()),
        Some("Mode".to_string())
    );
}

/// An enum body may hold methods, and what one calls is a use like
/// any other.
#[test]
fn a_call_inside_an_enums_method_is_still_a_reference() {
    let text =
        "vim9script\nenum Mode\n  Alpha\n  def Name(): string\n    return Label()\n  enddef\nendenum\n";

    assert_eq!(count(text, "Label"), 1);
}
