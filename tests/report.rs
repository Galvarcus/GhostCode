//! The report: what a run says, in both of the forms it says it in.
//!
//! License: GNU GPL 3.0

mod common;

use std::path::Path;
use std::path::PathBuf;

use common::TempDir;
use ghostcode::model::Class;
use ghostcode::model::Kind;
use ghostcode::report;
use ghostcode::report::Finding;
use ghostcode::report::Report;
use serde_json::Value;

const LIB: &str = "vim9script\nexport def Used()\nenddef\ndef Dead()\nenddef\n";
const ENTRY: &str = "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used()\n";

/// FUNCTION: The field names of one JSON object, sorted, so that a
/// test states the whole shape rather than the fields it remembers.
fn keys(v: &Value) -> Vec<&str> {
    let mut out: Vec<&str> = v
        .as_object()
        .unwrap_or_else(|| panic!("an object: {v}"))
        .keys()
        .map(String::as_str)
        .collect();
    out.sort_unstable();
    out
}

/// FUNCTION: Scan a project of the given files, strictly, so that an
/// export that nothing uses is reported like anything else.
fn run(dir: &TempDir) -> Report {
    let cfg = common::cfg(false);
    report::analyze(dir.path(), &cfg).expect("the scan runs")
}

/// FUNCTION: A small project: one library and one entry script.
fn project(tag: &str) -> TempDir {
    let dir = TempDir::new(tag);
    dir.write("autoload/lib.vim", LIB);
    dir.write("plugin/p.vim", ENTRY);
    dir
}

/// FUNCTION: Each finding as the text form prints it.
fn lines(r: &Report) -> Vec<String> {
    report::text(r).lines().map(str::to_string).collect()
}

#[test]
fn schema_is_one() {
    let dir = project("schema");

    assert_eq!(run(&dir).schema, 1);
}

#[test]
fn a_symbol_nothing_reaches_is_a_finding() {
    let dir = project("dead");

    assert_eq!(
        lines(&run(&dir)),
        vec!["autoload/lib.vim:4:1:[ghost] function Dead"]
    );
}

#[test]
fn an_exported_symbol_is_not_a_finding_by_default() {
    let dir = TempDir::new("exported");
    dir.write("autoload/lib.vim", "vim9script\nexport def Api()\nenddef\n");

    let cfg = common::cfg(true);
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    assert!(r.findings.is_empty(), "an export is public API: {r:?}");
}

#[test]
fn every_col_is_one() {
    let dir = project("col");

    assert!(run(&dir).findings.iter().all(|f| f.col == 1));
}

#[test]
fn findings_sort_by_file_then_line() {
    let dir = TempDir::new("order");
    dir.write(
        "autoload/b.vim",
        "vim9script\ndef Second()\nenddef\ndef Third()\nenddef\n",
    );
    dir.write("autoload/a.vim", "vim9script\ndef First()\nenddef\n");

    let names: Vec<String> = run(&dir).findings.into_iter().map(|f| f.name).collect();
    assert_eq!(names, vec!["First", "Second", "Third"]);
}

#[test]
fn paths_are_relative_to_the_root() {
    let dir = project("relative");

    assert!(run(&dir)
        .findings
        .iter()
        .all(|f| f.file == Path::new("autoload/lib.vim")));
}

#[test]
fn an_unplaced_name_is_a_summary_number_and_never_a_finding() {
    let dir = TempDir::new("unplaced");
    dir.write("plugin/p.vim", "vim9script\nNoSuchFunction()\n");

    let r = run(&dir);
    assert_eq!(r.summary.unplaced_names, 1, "the call named nothing");
    assert!(r.findings.is_empty());
}

/// FUNCTION: A project whose only fault is a variable of a body that
/// nothing reads.
fn with_unread_local(tag: &str) -> TempDir {
    let dir = TempDir::new(tag);
    dir.write(
        "autoload/lib.vim",
        "vim9script\nexport def Used()\n  var row = 1\nenddef\n",
    );
    dir.write("plugin/p.vim", ENTRY);
    dir
}

/// FUNCTION: Scan with the local class turned on.
fn run_with_locals(dir: &TempDir) -> Report {
    let cfg = common::cfg_with_locals(false);
    report::analyze(dir.path(), &cfg).expect("the scan runs")
}

/// The class waits behind its flag, so a run that did not ask for it
/// reads exactly as it did before the class existed.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_local_class_is_off_unless_its_flag_is_set() {
    let dir = with_unread_local("local-off");
    let r = run(&dir);

    assert!(r.findings.is_empty());
    assert_eq!(r.summary.local, 0);
}

/// `summary.ghost` is the count of ghosts, not of findings. A build
/// that counts ghosts must not see a local among them.
#[test]
fn a_local_finding_does_not_raise_the_ghost_count() {
    let dir = with_unread_local("local-count");
    let r = run_with_locals(&dir);

    assert_eq!(r.summary.ghost, 0);
    assert_eq!(r.summary.local, 1);
}

/// The tag is a contract: Bartleby's build counts the lines carrying
/// `[ghost]`, so a local must never print one.
#[test]
fn a_local_prints_its_own_tag_and_never_the_ghost_tag() {
    let dir = with_unread_local("local-tag");
    let r = run_with_locals(&dir);

    assert_eq!(lines(&r), vec!["autoload/lib.vim:3:1:[local] variable row"]);
}

/// A dead function is the finding. Reporting its locals beside it
/// would name the symptom several times over and the cause once.
#[test]
fn a_local_of_a_dead_function_is_not_reported_beside_it() {
    let dir = TempDir::new("local-dead");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nexport def Used()\nenddef\ndef Dead()\n  var row = 1\nenddef\n",
    );
    dir.write("plugin/p.vim", ENTRY);
    let r = run_with_locals(&dir);

    assert_eq!(
        lines(&r),
        vec!["autoload/lib.vim:4:1:[ghost] function Dead"]
    );
}

#[test]
fn the_summary_counts_every_symbol() {
    let dir = project("summary");
    let r = run(&dir);

    assert_eq!(r.summary.symbols, 2, "Used and Dead");
    assert_eq!(r.summary.ghost, 1);
}

#[test]
fn text_prints_file_line_col_then_the_tagged_kind_and_name() {
    let r = Report {
        schema: 1,
        root: PathBuf::from("/project"),
        summary: report::Summary::default(),
        findings: vec![Finding {
            class: Class::Ghost,
            kind: Kind::Method,
            name: "Open".to_string(),
            file: PathBuf::from("autoload/m.vim"),
            line: 12,
            col: 1,
            lang: "vim9",
        }],
        skipped: Vec::new(),
        notes: Vec::new(),
        unplaced: Vec::new(),
    };

    assert_eq!(
        report::text(&r),
        "autoload/m.vim:12:1:[ghost] method Open\n"
    );
}

#[test]
fn a_write_only_finding_prints_its_own_tag_not_ghost() {
    let r = Report {
        schema: 1,
        root: PathBuf::from("/project"),
        summary: report::Summary::default(),
        findings: vec![Finding {
            class: Class::WriteOnly,
            kind: Kind::Variable,
            name: "count".to_string(),
            file: PathBuf::from("autoload/m.vim"),
            line: 3,
            col: 1,
            lang: "vim9",
        }],
        skipped: Vec::new(),
        notes: Vec::new(),
        unplaced: Vec::new(),
    };

    assert_eq!(
        report::text(&r),
        "autoload/m.vim:3:1:[write-only] variable count\n"
    );
}

/// The names in this test are the JSON contract. The parity fixtures
/// cannot pin them: they carry no summary, and their root is the
/// absolute path of the machine that captured them.
#[test]
fn json_carries_every_field_a_consumer_reads() {
    let dir = project("json");
    let text = report::json(&run(&dir));
    let v: Value = serde_json::from_str(&text).expect("the report is JSON");

    assert_eq!(
        keys(&v),
        ["findings", "notes", "root", "schema", "skipped", "summary"]
    );
    // `local` joined the summary with the local finding class. A
    // reader that does not know the key is not broken by it, which is
    // the test the schema sets, so SCHEMA stays where it is.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    assert_eq!(
        keys(&v["summary"]),
        ["ghost", "local", "symbols", "unplaced_names"]
    );
    assert_eq!(
        keys(&v["findings"][0]),
        ["class", "col", "file", "kind", "lang", "line", "name"]
    );

    assert_eq!(
        v["schema"],
        report::SCHEMA,
        "the front end refuses a schema it does not know"
    );
    assert_eq!(v["findings"][0]["class"], "ghost");
    assert_eq!(v["findings"][0]["kind"], "function");
    assert_eq!(v["findings"][0]["name"], "Dead");
}

#[test]
fn a_config_entry_path_roots_what_it_calls() {
    let dir = TempDir::new("cfg-entry");
    dir.write("ghostcode.toml", "entry = [\"tools/build.vim\"]\n");
    dir.write(
        "autoload/lib.vim",
        "vim9script\nexport def Used()\nenddef\n",
    );
    dir.write(
        "tools/build.vim",
        "vim9script\nimport autoload 'lib.vim' as lib\nlib.Used()\n",
    );

    let cfg = ghostcode::config::Config {
        exports_are_api: false,
        entry: vec![PathBuf::from("tools/build.vim")],
        ..common::cfg(false)
    };
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    assert!(
        r.findings.is_empty(),
        "a configured entry roots what it calls: {:?}",
        r.findings
    );
}

#[test]
fn an_entry_script_is_not_needed_for_a_file_outside_the_entry_directories() {
    let dir = TempDir::new("no-entry");
    dir.write("autoload/lib.vim", "vim9script\ndef Dead()\nenddef\n");

    let r = run(&dir);
    assert_eq!(r.findings.len(), 1, "nothing roots autoload on its own");
    assert_eq!(r.findings[0].file, Path::new("autoload/lib.vim"));
}

/// The list and the count come from one pass, so they cannot disagree.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/84
#[test]
fn the_unplaced_list_holds_as_many_names_as_the_count() {
    let dir = TempDir::new("unplaced-count");
    dir.write("plugin/p.vim", "vim9script\nNope()\nAlso()\nNope()\n");

    let cfg = ghostcode::config::Config {
        unplaced: true,
        ..common::cfg(false)
    };
    let r = report::analyze(dir.path(), &cfg).expect("the scan runs");

    assert_eq!(r.unplaced.len(), 3, "{:?}", r.unplaced);
    assert_eq!(r.unplaced.len(), r.summary.unplaced_names);
}
