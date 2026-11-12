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

/// `final` is a declaring word Vim9 treats as a `const` assigned
/// once, and `strip_modifiers` eats it before the local emitter can
/// see it. So no symbol was recorded while the read was no longer
/// dropped, and the read fell through to a project symbol of the same
/// name, taking a credit it was not owed. That is the design's first
/// anti-goal: a ghost that silently stops being reported.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_final_in_a_body_does_not_credit_a_script_variable_of_its_name() {
    let dir = TempDir::new("final-credit");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nvar helper = 1\nexport def Run()\n  final helper = 2\n  echo helper\nenddef\n",
    );
    dir.write(
        "plugin/p.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Run()\n",
    );

    let r = report::analyze(dir.path(), &common::cfg(false)).expect("the scan runs");

    assert_eq!(
        r.findings
            .iter()
            .map(|f| format!("{} {}", f.class, f.name))
            .collect::<Vec<String>>(),
        vec!["ghost helper"],
        "the script variable is read by nothing"
    );
}

/// A compound assignment reads the variable before it writes it, so
/// it is a read. `n += 1` and `n = n + 1` are the same statement
/// spelled two ways and must give one answer.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_compound_assignment_counts_as_a_read_however_it_is_spelled() {
    assert!(found("compound", "  var n = 0\n  n += 1\n").is_empty());
    assert!(found("longhand", "  var n = 0\n  n = n + 1\n").is_empty());
}

/// A plain assignment is a pure write, which is the fault the class
/// exists to find.
#[test]
fn a_plain_assignment_is_still_only_a_write() {
    assert_eq!(
        found("plain", "  var f = false\n  f = true\n"),
        vec!["local variable f"]
    );
}

/// A name declared by unpacking is a variable of the body, so one that
/// nothing reads is the same finding a plain `var` gives.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn an_unpacked_name_nothing_reads_is_reported() {
    assert_eq!(
        found("unpack", "  var [first, last] = [1, 2]\n  echo first\n"),
        vec!["local variable last"]
    );
}

#[test]
fn an_unpacked_name_something_reads_is_not_reported() {
    assert!(found(
        "unpackread",
        "  var [first, last] = [1, 2]\n  echo first + last\n"
    )
    .is_empty());
}

/// A name the analyzer marked as Vim's is one it placed. It saw no
/// read of a variable there, so the name hides no finding. The file
/// declares the name twice, which is what leaves the marked name
/// unresolved: declared once, it would resolve and credit.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/48
#[test]
fn a_name_marked_as_vims_does_not_hide_an_unread_local_of_its_spelling() {
    assert_eq!(
        found(
            "owned",
            "  var x = 1\n  def In()\n    if exists('l:x')\n    endif\n  enddef\n  def Two()\n    var x = 2\n    echo x\n  enddef\n  In()\n  Two()\n"
        ),
        vec!["local variable x"]
    );
}

/// A read the analyzer could not place may be a read of any variable
/// of that spelling in the file, so it still hides every one of them.
/// `In` reads a name that no body around it declares, and two other
/// bodies declare it.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/48
#[test]
fn a_read_nothing_placed_still_hides_a_local_of_its_spelling() {
    assert!(found(
        "blind",
        "  def In()\n    echo row\n  enddef\n  def Two()\n    var row = 2\n  enddef\n  def Three()\n    var row = 3\n  enddef\n  In()\n  Two()\n  Three()\n"
    )
    .is_empty());
}

/// A def inside a def reads the variables of the body around it, and
/// the scan names that variable as the one read. The read therefore
/// hides no other variable of the spelling: the one in `Other` is
/// unread and is reported.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn a_read_from_a_nested_def_credits_the_variable_of_the_body_around_it() {
    assert_eq!(
        found(
            "nested",
            "  var total = 0\n  def Walk()\n    echo total\n  enddef\n  Walk()\n  Other()\nenddef\ndef Other()\n  var total = 1\n"
        ),
        vec!["local variable total"]
    );
}

/// A def that only writes the variable of the body around it reads
/// nothing, so the variable is still reported.
#[test]
fn a_write_from_a_nested_def_does_not_credit_the_variable_around_it() {
    assert_eq!(
        found(
            "nestedwrite",
            "  var total = 0\n  def Walk()\n    total = 1\n  enddef\n  Walk()\n"
        ),
        vec!["local variable total"]
    );
}
