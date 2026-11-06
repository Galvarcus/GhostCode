//! What the analyzer reports for small projects, as the Vim suite
//! asked it before the core moved to Rust.
//!
//! Each test here carries the files and the expectation of its Vim
//! original in tests/test_ghostcode.vim, under the same name, so that
//! the two can be read side by side.
//!
//! License: GNU GPL 3.0

mod common;

use common::TempDir;
use ghostcode::report;

/// FUNCTION: Scan a project of the given files and return each
/// finding as `kind name`, sorted, as the Vim helper did.
fn ghosts(tag: &str, files: &[(&str, &str)], exports_are_api: bool) -> Vec<String> {
    let dir = TempDir::new(tag);
    for (path, text) in files {
        dir.write(path, text);
    }

    let cfg = common::cfg(exports_are_api);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    let mut out: Vec<String> = r
        .findings
        .iter()
        .map(|f| format!("{} {}", f.kind, f.name))
        .collect();
    out.sort();
    out
}

/// FUNCTION: A plugin with an exported class and two exported
/// functions. The plugin script uses one function and one method; the
/// other function and method are exported and used by nothing.
fn library() -> Vec<(&'static str, &'static str)> {
    vec![
        (
            "autoload/lib.vim",
            "vim9script\n\
             export class Thing\n\
             \x20 def Used()\n\
             \x20 enddef\n\
             \x20 def Unused()\n\
             \x20 enddef\n\
             endclass\n\
             export def Helper()\n\
             enddef\n\
             export def Orphan()\n\
             enddef\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\n\
             import autoload \"lib.vim\" as L\n\
             L.Helper()\n\
             var t = L.Thing.new()\n\
             t.Used()\n",
        ),
    ]
}

#[test]
fn an_export_is_api_by_default() {
    assert!(ghosts("api-default", &library(), true).is_empty());
}

#[test]
fn strict_mode_reports_an_export_that_nothing_uses() {
    assert_eq!(
        ghosts("strict-export", &library(), false),
        vec!["function Orphan", "method Unused"]
    );
}

#[test]
fn a_symbol_nothing_reaches_is_reported_in_both_modes() {
    let mut files = library();
    files[0].1 = "vim9script\n\
                  export class Thing\n\
                  \x20 def Used()\n\
                  \x20 enddef\n\
                  \x20 def Unused()\n\
                  \x20 enddef\n\
                  endclass\n\
                  export def Helper()\n\
                  enddef\n\
                  export def Orphan()\n\
                  enddef\n\
                  def Dead()\n\
                  enddef\n";

    assert_eq!(ghosts("dead-api", &files, true), vec!["function Dead"]);
    assert_eq!(
        ghosts("dead-strict", &files, false),
        vec!["function Dead", "function Orphan", "method Unused"]
    );
}

#[test]
fn every_candidate_of_an_ambiguous_name_counts_as_used() {
    let files = [
        (
            "autoload/a.vim",
            "vim9script\n\
             export class A\n\
             \x20 def Close()\n\
             \x20 enddef\n\
             endclass\n\
             export class B\n\
             \x20 def Close()\n\
             \x20 enddef\n\
             \x20 def Other()\n\
             \x20 enddef\n\
             endclass\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\n\
             import autoload \"a.vim\" as X\n\
             def Run(thing: any)\n\
             \x20 thing.Close()\n\
             enddef\n\
             Run(X.A.new())\n\
             Run(X.B.new())\n",
        ),
    ];

    assert_eq!(
        ghosts("ambiguous", &files, false),
        vec!["method Other"],
        "the call may reach either Close, so both count"
    );
}

#[test]
fn a_bare_name_that_two_files_define_counts_for_both() {
    let files = [
        (
            "autoload/a.vim",
            "vim9script\nexport def Helper()\nenddef\n",
        ),
        (
            "autoload/b.vim",
            "vim9script\nexport def Helper()\nenddef\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\n\
             import autoload \"a.vim\" as A\n\
             import autoload \"b.vim\" as B\n\
             call(\"Helper\", [])\n",
        ),
    ];

    assert!(ghosts("bare-name", &files, false).is_empty());
}

#[test]
fn a_class_qualified_call_reaches_only_its_own_member() {
    let files = [
        (
            "autoload/m.vim",
            "vim9script\n\
             export class Menu\n\
             \x20 def new(this.label: string)\n\
             \x20 enddef\n\
             endclass\n\
             export class Other\n\
             \x20 def new()\n\
             \x20 enddef\n\
             endclass\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\nimport autoload \"m.vim\" as M\nM.Menu.new(\"x\")\n",
        ),
    ];

    assert_eq!(
        ghosts("class-qualified", &files, false),
        vec!["class Other", "method new"]
    );
}

#[test]
fn a_default_constructor_credits_nothing() {
    let files = [
        (
            "autoload/m.vim",
            "vim9script\n\
             export class Plain\n\
             endclass\n\
             export class Other\n\
             \x20 def new()\n\
             \x20 enddef\n\
             endclass\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\nimport autoload \"m.vim\" as M\nM.Plain.new()\n",
        ),
    ];

    assert_eq!(
        ghosts("default-ctor", &files, false),
        vec!["class Other", "method new"],
        "building Plain must not credit Other's constructor"
    );
}

#[test]
fn a_field_read_through_an_untyped_receiver_counts() {
    let files = [
        (
            "autoload/f.vim",
            "vim9script\n\
             export class Item\n\
             \x20 public var label: string\n\
             endclass\n\
             export class Entry\n\
             \x20 public var label: string\n\
             endclass\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\n\
             import autoload \"f.vim\" as F\n\
             def Show(thing: any): string\n\
             \x20 return thing.label\n\
             enddef\n\
             Show(F.Item.new())\n\
             Show(F.Entry.new())\n",
        ),
    ];

    assert!(ghosts("untyped-field", &files, false).is_empty());
}

#[test]
fn a_name_used_in_a_concatenation_counts_as_used() {
    let files = [(
        "plugin/p.vim",
        "vim9script\n\
         const PREFIX: string = \"a-\"\n\
         const SUFFIX: string = \"-z\"\n\
         def Join(name: string): string\n\
         \x20 return PREFIX .. name .. SUFFIX\n\
         enddef\n\
         Join(\"x\")\n",
    )];

    assert!(ghosts("concat", &files, false).is_empty());
}

#[test]
fn a_name_used_in_a_parameter_default_counts_as_used() {
    let files = [(
        "plugin/p.vim",
        "vim9script\n\
         const ROOT: string = \"/x\"\n\
         def Dirs(): list<string>\n\
         \x20 return [ROOT]\n\
         enddef\n\
         def List(dirs: list<string> = Dirs(), n: number = 0): list<string>\n\
         \x20 return dirs\n\
         enddef\n\
         List()\n",
    )];

    assert!(ghosts("param-default", &files, false).is_empty());
}

#[test]
fn a_class_named_in_an_interface_field_is_not_reported() {
    let files = vec![
        (
            "plugin/p.vim",
            "vim9script\nimport autoload 'lib.vim'\nlib.Hold()\n",
        ),
        (
            "autoload/lib.vim",
            "vim9script\n\
             export class Thing\n\
             endclass\n\
             export interface Holder\n\
             \x20 def One()\n\
             \x20 var box: Thing\n\
             endinterface\n\
             export def Hold(h: Holder)\n\
             enddef\n",
        ),
    ];

    assert_eq!(
        ghosts("interface_field", &files, false),
        vec!["field box"],
        "the annotation in the interface's body names the class"
    );
}

/// Vim9 reserves `null_object` and its siblings, and an enum value is
/// the one declaration that may carry such a name. A word held in the
/// parser's keywords emits no reference at all, so holding the word
/// there leaves the value with nothing crediting it and makes a
/// finding of legal code.
///
/// Both values are read, because a value's own line no longer credits
/// it: the read is the only credit either of them has.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
#[test]
fn an_enum_value_named_like_a_null_literal_is_not_reported() {
    let files = vec![(
        "plugin/p.vim",
        "vim9script\n\
         enum Mode\n\
         \x20 null_list\n\
         \x20 Other\n\
         endenum\n\
         echo Mode.null_list\n\
         echo Mode.Other\n",
    )];

    assert_eq!(
        ghosts("null_enum_value", &files, false),
        Vec::<String>::new()
    );
}

/// A variable spelled like one of the words the report prints was
/// suppressed wherever it stood, so the read that credits it was lost
/// and the variable itself was reported.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/28
#[test]
fn a_variable_named_like_a_kind_word_is_not_reported() {
    let files = vec![
        (
            "autoload/lib.vim",
            "vim9script\nvar enum_value = 1\nexport def Run()\n  echo enum_value\nenddef\n",
        ),
        (
            "plugin/p.vim",
            "vim9script\nimport autoload 'lib.vim' as L\nL.Run()\n",
        ),
    ];

    assert_eq!(ghosts("kind_word", &files, false), Vec::<String>::new());
}

/// Every enum value used to credit itself, through the reference its
/// own declaration line emitted, so no value could ever be reported.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/23
#[test]
fn an_unused_enum_value_is_reported() {
    let files = vec![(
        "plugin/p.vim",
        "vim9script\nenum Mode\n  Alpha,\n  Beta\nendenum\necho Mode.Alpha\n",
    )];

    assert_eq!(
        ghosts("unused_enum_value", &files, false),
        vec!["enum_value Beta".to_string()]
    );
}
