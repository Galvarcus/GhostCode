//! The variables of a function body: which names the scan keeps out of
//! the reference list because the body itself declares them.
//!
//! A `var` or `const` is no longer one of them. It is a symbol scoped
//! to its body, so its read is a reference that resolves there, and
//! what the old suppression protected is resolution's job now.
//! REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
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

/// A read of the body's own variable is a reference, because the
/// variable is now a symbol for it to resolve to, and that read is
/// the credit keeping it off the report. The false credit the old
/// suppression prevented is prevented by the scope instead, which
/// `tests/vim9_local_symbols.rs` holds.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_variable_the_body_declares_is_a_reference_carrying_that_body() {
    let text = "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\n";

    assert_eq!(count(text, "row"), 1);
    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "row")
            .and_then(|r| r.origin.as_ref())
            .map(ToString::to_string),
        Some("autoload/p.vim::F".to_string())
    );
}

#[test]
fn a_parameter_is_not_a_reference() {
    let text = "vim9script\ndef F(amt: number)\n  echo amt\nenddef\n";

    assert_eq!(count(text, "amt"), 0);
}

#[test]
fn a_loop_variable_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  for f in xs\n    echo f\n  endfor\nenddef\n";

    assert_eq!(count(text, "f"), 0);
}

#[test]
fn an_unpacked_loop_variable_is_not_a_reference() {
    let text = "vim9script\ndef F(d: dict<string>)\n  for [k, v] in items(d)\n    echo k .. v\n  endfor\nenddef\n";

    assert_eq!(count(text, "k"), 0);
    assert_eq!(count(text, "v"), 0);
}

#[test]
fn a_lambda_parameter_is_not_a_reference() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, s) => s)\nenddef\n";

    assert_eq!(count(text, "_"), 0);
    assert_eq!(count(text, "s"), 0);
}

/// A lambda's parameters belong to the lambda, not to the body around
/// it, so a name the body uses for its own purpose after one keeps
/// its reference.
#[test]
fn a_lambda_parameter_hides_nothing_after_the_statement() {
    let text = "vim9script\ndef F(xs: list<string>)\n  echo xs->mapnew((_, Fmt) => Fmt)\n  Fmt()\nenddef\n";

    assert_eq!(count(text, "Fmt"), 1);
}

/// The receiver of a member access is the body's own variable, and the
/// member it reaches is still a reference, carrying the type the
/// variable was declared with.
#[test]
fn a_member_of_a_local_receiver_is_still_a_reference() {
    let text = "vim9script\ndef F(m: Menu)\n  m.Open()\nenddef\n";

    assert_eq!(count(text, "m"), 0);
    assert_eq!(
        refs(text)
            .iter()
            .find(|r| r.name == "Open")
            .and_then(|r| r.recv.clone()),
        Some("Menu".to_string())
    );
}

#[test]
fn a_project_function_called_in_a_body_is_still_a_reference() {
    let text = "vim9script\ndef F()\n  Helper()\nenddef\n";

    assert_eq!(count(text, "Helper"), 1);
}

/// A script variable is a symbol of the project, and the reads of it
/// are what credit it. Nothing here may suppress one.
#[test]
fn a_script_variable_read_at_script_level_is_still_a_reference() {
    let text = "vim9script\nvar width = 1\necho width\n";

    assert_eq!(count(text, "width"), 1);
}

#[test]
fn a_script_variable_read_inside_a_body_is_still_a_reference() {
    let text = "vim9script\nvar width = 1\ndef F()\n  echo width\nenddef\n";

    assert_eq!(count(text, "width"), 1);
}

/// `var Menu = Menu.new()` names the class on the right of the
/// assignment, which the declaration on the left must not hide: the
/// class has to keep that credit. The later `Menu.Open()` names the
/// variable holding the object, which is a second reference and
/// resolves to the body's own symbol.
#[test]
fn a_name_the_statement_declares_still_credits_a_symbol_of_that_name() {
    let text = "vim9script\ndef F()\n  var Menu = Menu.new()\n  Menu.Open()\nenddef\n";

    assert_eq!(count(text, "Menu"), 2);
}

/// A parameter list is separated by its own commas. A comma inside a
/// parameter's type separates nothing, and the name after it is a
/// type the project may declare, which must keep its credit.
#[test]
fn a_name_inside_a_parameters_type_is_still_a_reference() {
    let text = "vim9script\ndef Register(Cb: func(string, Config))\nenddef\n";

    assert_eq!(count(text, "Config"), 1);
}

#[test]
fn a_name_inside_a_parameters_default_is_still_a_reference() {
    let text = "vim9script\ndef F(xs = [One, Two])\nenddef\n";

    assert_eq!(count(text, "Two"), 1);
}

#[test]
fn a_parameter_after_a_nested_comma_is_not_a_reference() {
    let text = "vim9script\ndef F(Cb: func(string, Config), amt: number)\n  echo amt\nenddef\n";

    assert_eq!(count(text, "amt"), 0);
}

/// A body outside the one that declared the name knows nothing of it.
/// Both reads are references; only the one inside F has a symbol to
/// reach, which `a_scoped_symbol_is_invisible_from_another_scope` in
/// `src/resolve.rs` holds.
#[test]
fn a_variable_of_another_body_is_still_a_reference() {
    let text =
        "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\ndef G()\n  echo row\nenddef\n";

    assert_eq!(count(text, "row"), 2);
}
