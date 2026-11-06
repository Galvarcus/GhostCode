//! What the local class reports and, more to the point, what it does
//! not: the bindings a plugin cannot act on, and the credits a local
//! may take from nothing but its own body.
//!
//! License: GNU GPL 3.0

mod common;

use common::TempDir;
use ghostcode::report;

/// FUNCTION: Every finding of a one-file plugin, as `class kind name`,
/// with the local class turned on.
fn found(tag: &str, body: &str) -> Vec<String> {
    let dir = TempDir::new(tag);
    dir.write(
        "autoload/lib.vim",
        &format!("vim9script\nexport def Used()\n{body}enddef\n"),
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used()\n",
    );

    let cfg = common::cfg_with_locals(false);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    r.findings
        .iter()
        .map(|f| format!("{} {} {}", f.class, f.kind, f.name))
        .collect()
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_local_nothing_reads_is_reported() {
    assert_eq!(
        found("unread", "  var row = 1\n"),
        vec!["local variable row"]
    );
}

#[test]
fn a_local_something_reads_is_not_reported() {
    assert!(found("read", "  var row = 1\n  echo row\n").is_empty());
}

/// A write is not a read, which is the whole of the fault found in
/// the old analyzer: a flag maintained four times and never consulted.
#[test]
fn a_local_only_written_is_reported() {
    assert_eq!(
        found("written", "  var f = false\n  f = true\n"),
        vec!["local variable f"]
    );
}

#[test]
fn a_local_written_and_then_read_is_not_reported() {
    assert!(found("rw", "  var f = false\n  f = true\n  echo f\n").is_empty());
}

/// A parameter may be unused inside the plugin and still be part of
/// the signature its caller requires, and that caller may be Vim.
#[test]
fn a_parameter_nothing_reads_is_not_reported() {
    let dir = TempDir::new("param");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nexport def Used(winid: number)\nenddef\n",
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used(1)\n",
    );

    let cfg = common::cfg_with_locals(false);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    assert!(r.findings.is_empty());
}

/// `for i in range(4)` is how Vim9 says "four times", so a counter
/// nothing reads is the idiom working as intended.
#[test]
fn a_loop_variable_nothing_reads_is_not_reported() {
    assert!(found("loop", "  for i in range(4)\n    echo 'x'\n  endfor\n").is_empty());
}

#[test]
fn a_lambda_parameter_nothing_reads_is_not_reported() {
    assert!(found("lambda", "  var g = (x) => 1\n  echo g\n").is_empty());
}

/// The name states that the value is unwanted.
#[test]
fn the_discard_placeholder_is_not_reported() {
    assert!(found("discard", "  var _ = Call()\n").is_empty());
}

/// Vim evaluates text, so a name read only inside an interpolated
/// string is read. Reporting it would be a finding nobody can act on.
#[test]
fn a_local_read_only_in_interpolated_text_is_not_reported() {
    assert!(found("text", "  var n = 1\n  execute $'echo {n}'\n").is_empty());
}

/// The design's first anti-goal: the script variable keeps its credit
/// and stays off the report, whatever a body declares.
#[test]
fn a_local_does_not_take_the_credits_of_a_script_variable_of_its_name() {
    let dir = TempDir::new("shadow");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nvar row = 1\nexport def Used()\n  var row = 2\n  echo row\nenddef\nexport def Other(): number\n  return row\nenddef\n",
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used()\necho lib.Other()\n",
    );

    let cfg = common::cfg_with_locals(false);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    assert!(
        r.findings.is_empty(),
        "the script variable is read by Other: {:?}",
        r.findings
            .iter()
            .map(|f| format!("{} {}", f.class, f.name))
            .collect::<Vec<String>>()
    );
}

/// Vim9 scopes a `var` to its block, so one body may declare a name
/// twice and both carry one id. A read of either credits both, so
/// neither is reported: the class misses a finding rather than
/// inventing one.
#[test]
fn one_name_declared_in_two_blocks_of_a_body_is_not_reported() {
    assert!(found(
        "blocks",
        "  if Cond()\n    var row = 1\n    echo row\n  endif\n  var row = 2\n"
    )
    .is_empty());
}
