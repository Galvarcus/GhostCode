//! Member access: which names stand behind a dot, and what one that
//! no class declares does to the findings.
//!
//! License: GNU GPL 3.0

mod common;

use common::source;
use common::TempDir;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Reference;
use ghostcode::report;

/// FUNCTION: The reference one snippet emits for a name.
fn one(text: &str, name: &str) -> Reference {
    let mut found = Analysis::default();
    Vim9.scan(&source("autoload/p.vim", text), &mut found)
        .expect("a scan never fails on one file");

    found
        .refs
        .into_iter()
        .find(|r| r.name == name)
        .unwrap_or_else(|| panic!("no reference named {name}"))
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_name_behind_a_dot_is_a_member() {
    let text = "vim9script\ndef F()\n  var fx = Setup()\n  echo fx.root\nenddef\n";

    assert!(one(text, "root").member);
}

#[test]
fn a_name_behind_a_call_is_a_member() {
    let text = "vim9script\ndef F()\n  echo Written().today\nenddef\n";

    assert!(one(text, "today").member);
}

#[test]
fn a_name_behind_an_index_is_a_member() {
    let text = "vim9script\ndef F()\n  var rows = Rows()\n  echo rows[0].kind\nenddef\n";

    assert!(one(text, "kind").member);
}

#[test]
fn a_name_before_a_dot_is_no_member() {
    let text = "vim9script\ndef F()\n  echo Outer.inner\nenddef\n";

    assert!(!one(text, "Outer").member);
}

#[test]
fn a_name_behind_a_concatenation_is_no_member() {
    let text = "vim9script\ndef F()\n  echo First() .. Second()\nenddef\n";

    assert!(!one(text, "Second").member);
}

/// A name behind a dot reads no variable, so a key of a dictionary
/// hides no local of the same spelling in another body of the file.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_key_behind_a_dot_hides_no_unread_local_of_its_spelling() {
    let dir = TempDir::new("member-blind");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nexport def Used()\n  var fx = Setup()\n  echo fx.root\nenddef\n\
         export def Other()\n  var root = 1\nenddef\n\
         def Setup(): any\n  return {}\nenddef\n",
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used()\nlib.Other()\n",
    );

    let cfg = common::cfg_with_locals(false);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");
    let found: Vec<String> = r
        .findings
        .iter()
        .map(|f| format!("{} {} {}", f.class, f.kind, f.name))
        .collect();

    assert_eq!(found, vec!["local variable root"]);
    assert_eq!(r.summary.unplaced_names, 0);
}

/// FUNCTION: The report of a plugin of one class, built by one call.
fn built(tag: &str, class: &str) -> report::Report {
    let dir = TempDir::new(tag);
    dir.write(
        "autoload/lib.vim",
        &format!("vim9script\nexport class Menu\n{class}endclass\n"),
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nvar menu = lib.Menu.new()\necho menu\n",
    );

    report::analyze(dir.path(), &common::cfg_with_locals(false)).expect("the scan runs")
}

/// Vim supplies `new` for a class that declares no constructor, so
/// the name is the language's there and nothing is left to place.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_constructor_vim_supplies_is_marked_as_vims() {
    let text = "vim9script\ndef F()\n  var menu = Menu.new()\nenddef\n";

    assert!(one(text, "new").owned);
}

#[test]
fn the_constructor_vim_supplies_is_not_an_unplaced_name() {
    let r = built("new-supplied", "  var title = ''\n");

    assert_eq!(r.summary.unplaced_names, 0);
}

/// The mark is read only where nothing resolved, so a constructor the
/// class declares still takes the credit of the call.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_constructor_the_class_declares_still_takes_the_credit() {
    let r = built("new-declared", "  def new()\n  enddef\n");

    assert!(r.findings.is_empty());
    assert_eq!(r.summary.unplaced_names, 0);
}

#[test]
fn a_variable_named_new_is_not_marked() {
    let text = "vim9script\ndef F()\n  echo new\nenddef\n";

    assert!(!one(text, "new").owned);
}
