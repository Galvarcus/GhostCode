//! A variable of a function body as a symbol: which bindings become
//! one, what scope it carries, and that a read of it resolves there
//! and nowhere else.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Kind;
use ghostcode::resolve;

/// FUNCTION: Everything one snippet declares and reads.
fn scan(text: &str) -> Analysis {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
}

/// FUNCTION: The id and scope of every symbol of a name, as text.
fn syms(text: &str, name: &str) -> Vec<(String, String)> {
    scan(text)
        .syms
        .iter()
        .filter(|s| s.name == name)
        .map(|s| {
            (
                s.id.to_string(),
                s.scope
                    .as_ref()
                    .map(ToString::to_string)
                    .unwrap_or_default(),
            )
        })
        .collect()
}

/// FUNCTION: What the one reference of a name resolves to.
fn resolved(text: &str, name: &str) -> Vec<String> {
    let a = scan(text);
    let out = resolve::all(&a);
    let at = a
        .refs
        .iter()
        .position(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"));

    out.targets
        .get(&at)
        .map(|ids| ids.iter().map(ToString::to_string).collect())
        .unwrap_or_default()
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_local_var_is_a_symbol_scoped_to_its_body() {
    let text = "vim9script\ndef F()\n  var row = 1\nenddef\n";

    assert_eq!(
        syms(text, "row"),
        vec![(
            "autoload/p.vim::F.row".to_string(),
            "autoload/p.vim::F".to_string()
        )]
    );
}

#[test]
fn a_local_const_is_a_symbol_too() {
    let text = "vim9script\ndef F()\n  const ROOT = '/x'\nenddef\n";

    assert_eq!(syms(text, "ROOT").len(), 1);
}

#[test]
fn a_local_of_a_method_is_scoped_to_the_method() {
    let text = "vim9script\nclass C\n  def M()\n    var row = 1\n  enddef\nendclass\n";

    assert_eq!(
        syms(text, "row"),
        vec![(
            "autoload/p.vim::C.M.row".to_string(),
            "autoload/p.vim::C.M".to_string()
        )]
    );
}

/// The read is the credit that keeps the variable off the report, and
/// it must reach the body's own variable rather than anything else.
#[test]
fn a_read_of_a_local_resolves_to_it() {
    let text = "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\n";

    assert_eq!(resolved(text, "row"), vec!["autoload/p.vim::F.row"]);
}

/// The number the parity fixtures do not protect: a local's read must
/// resolve, not fall through to nothing.
#[test]
fn a_local_read_raises_no_unplaced_name() {
    let text = "vim9script\ndef F()\n  var row = 1\n  echo row\nenddef\n";

    assert_eq!(resolve::all(&scan(text)).unplaced, 0);
}

#[test]
fn a_parameter_is_not_a_symbol() {
    let text = "vim9script\ndef F(amt: number)\nenddef\n";

    assert!(syms(text, "amt").is_empty());
}

#[test]
fn a_loop_variable_is_not_a_symbol() {
    let text = "vim9script\ndef F()\n  for i in range(4)\n    Press()\n  endfor\nenddef\n";

    assert!(syms(text, "i").is_empty());
}

#[test]
fn a_lambda_parameter_is_not_a_symbol() {
    let text = "vim9script\ndef F()\n  var g = (x) => x + 1\n  echo g\nenddef\n";

    assert!(syms(text, "x").is_empty());
}

/// The name says the value is unwanted, so there is nothing to report
/// and nothing to record.
#[test]
fn the_discard_placeholder_is_not_a_symbol() {
    let text = "vim9script\ndef F()\n  var _ = Call()\nenddef\n";

    assert!(syms(text, "_").is_empty());
}

/// The design's first anti-goal: a body's own variable must take
/// nothing from a script variable that shares its name.
#[test]
fn a_script_variable_keeps_its_own_symbol_when_a_body_shadows_it() {
    let text = "vim9script\nvar row = 1\ndef F()\n  var row = 2\n  echo row\nenddef\necho row\n";
    let found = syms(text, "row");

    assert_eq!(found.len(), 2, "the script variable and the body's own");
    assert!(found.contains(&("autoload/p.vim::row".to_string(), String::new())));
    assert!(found.contains(&(
        "autoload/p.vim::F.row".to_string(),
        "autoload/p.vim::F".to_string()
    )));
}

#[test]
fn a_script_level_read_reaches_the_script_variable_and_not_the_local() {
    let text = "vim9script\nvar row = 1\ndef F()\n  var row = 2\n  echo row\nenddef\necho row\n";
    let a = scan(text);
    let out = resolve::all(&a);

    // The last reference to `row` is the script-level read.
    let at = a
        .refs
        .iter()
        .rposition(|r| r.name == "row")
        .expect("a script-level read of row");

    assert_eq!(
        out.targets[&at]
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<String>>(),
        vec!["autoload/p.vim::row"]
    );
}

/// Vim9 scopes a `var` to its block, so one body may declare a name
/// twice. Both carry one id, so a read of either credits both and
/// neither is reported. That under-reports rather than inventing a
/// finding, which is the safe direction.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn one_name_declared_twice_in_a_body_is_one_symbol_id() {
    let text =
        "vim9script\ndef F()\n  if C()\n    var row = 1\n    echo row\n  endif\n  var row = 2\nenddef\n";
    let found = syms(text, "row");

    assert!(
        found.iter().all(|(id, _)| id == "autoload/p.vim::F.row"),
        "both declarations carry the body's one id"
    );
}

/// A body's variable is of the kind the report prints as a variable.
#[test]
fn a_local_is_recorded_as_a_variable() {
    let text = "vim9script\ndef F()\n  var row = 1\nenddef\n";

    assert!(scan(text)
        .syms
        .iter()
        .any(|s| s.name == "row" && s.kind == Kind::Variable));
}
