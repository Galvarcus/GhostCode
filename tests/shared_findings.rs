//! Scoped variables, end to end: which ones a run reports, behind
//! which flag, and what it says where a scope is read whole.
//!
//! License: GNU GPL 3.0

mod common;

use std::path::PathBuf;

use common::TempDir;
use ghostcode::config::Config;
use ghostcode::config::FindingFlags;
use ghostcode::report;
use ghostcode::report::Report;

const WRITE: &str = "vim9script\ng:p_x = 1\n";
const GHOST: &str = "plugin/p.vim:2:1:[ghost] variable g:p_x";

/// FUNCTION: A project of the given files.
fn project(tag: &str, files: &[(&str, &str)]) -> TempDir {
    let dir = TempDir::new(tag);

    for (rel, text) in files {
        dir.write(rel, text);
    }

    dir
}

/// FUNCTION: Scan a project strictly, with the given classes on.
fn run(dir: &TempDir, flags: FindingFlags) -> Report {
    report::analyze(dir.path(), &common::cfg_with(flags)).expect("the scan runs")
}

/// FUNCTION: The global class on, and no other.
fn globals() -> FindingFlags {
    FindingFlags {
        globals: true,
        ..FindingFlags::default()
    }
}

/// FUNCTION: Each finding as the text form prints it.
fn lines(r: &Report) -> Vec<String> {
    report::text(r).lines().map(str::to_string).collect()
}

/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
#[test]
fn an_unread_global_is_a_ghost_where_its_flag_is_on() {
    let dir = project("unread", &[("plugin/p.vim", WRITE)]);

    assert_eq!(lines(&run(&dir, globals())), vec![GHOST]);
}

#[test]
fn no_shared_finding_is_made_with_the_flags_off() {
    let dir = project("flags-off", &[("plugin/p.vim", WRITE)]);

    assert!(run(&dir, FindingFlags::default()).findings.is_empty());
}

#[test]
fn a_read_in_another_file_keeps_the_variable_alive() {
    let dir = project(
        "read-elsewhere",
        &[
            (
                "plugin/p.vim",
                "vim9script\nimport autoload 'a.vim' as A\ng:p_x = 1\nA.Use()\n",
            ),
            (
                "autoload/a.vim",
                "vim9script\nexport def Use()\n  echo g:p_x\nenddef\n",
            ),
        ],
    );

    assert!(run(&dir, globals()).findings.is_empty());
}

#[test]
fn a_read_in_a_function_nothing_reaches_credits_nothing() {
    let dir = project(
        "dead-read",
        &[(
            "plugin/p.vim",
            "vim9script\ng:p_x = 1\ndef Dead()\n  echo g:p_x\nenddef\n",
        )],
    );

    assert!(lines(&run(&dir, globals())).contains(&GHOST.to_string()));
}

/// The function is the cause and is reported for itself. The variable
/// is reported beside it, because it is written and nothing reads it
/// whether or not the function runs.
#[test]
fn a_variable_written_only_in_a_dead_function_is_still_reported() {
    let dir = project(
        "dead-write",
        &[(
            "plugin/p.vim",
            "vim9script\ndef Dead()\n  g:p_x = 1\nenddef\n",
        )],
    );

    assert_eq!(
        lines(&run(&dir, globals())),
        vec![
            "plugin/p.vim:2:1:[ghost] function Dead",
            "plugin/p.vim:3:1:[ghost] variable g:p_x",
        ]
    );
}

#[test]
fn a_setting_only_its_own_get_reads_is_a_ghost() {
    let dir = project(
        "setting",
        &[("plugin/p.vim", "vim9script\ng:p_x = get(g:, 'p_x', 0)\n")],
    );

    assert_eq!(lines(&run(&dir, globals())), vec![GHOST]);
}

#[test]
fn one_name_written_in_two_files_is_one_finding_at_the_lead_write() {
    let dir = project(
        "two-writes",
        &[
            (
                "autoload/a.vim",
                "vim9script\nexport def Toggle()\n  g:p_x = 1\nenddef\n",
            ),
            (
                "plugin/p.vim",
                "vim9script\nimport autoload 'a.vim' as A\ng:p_x = get(g:, 'p_x', 0)\nA.Toggle()\n",
            ),
        ],
    );

    assert_eq!(
        lines(&run(&dir, globals())),
        vec!["plugin/p.vim:3:1:[ghost] variable g:p_x"]
    );
}

#[test]
fn each_flag_gates_its_own_scope_alone() {
    let dir = project(
        "one-flag",
        &[("plugin/p.vim", "vim9script\ng:p_x = 1\nb:p_y = 1\n")],
    );
    let flags = FindingFlags {
        buffer_vars: true,
        ..FindingFlags::default()
    };

    assert_eq!(
        lines(&run(&dir, flags)),
        vec!["plugin/p.vim:3:1:[ghost] variable b:p_y"]
    );
}

#[test]
fn the_window_and_tab_flags_report_their_scopes() {
    let dir = project(
        "win-tab",
        &[("plugin/p.vim", "vim9script\nw:p_w = 1\nt:p_t = 1\n")],
    );
    let flags = FindingFlags {
        window_vars: true,
        tab_vars: true,
        ..FindingFlags::default()
    };

    assert_eq!(
        lines(&run(&dir, flags)),
        vec![
            "plugin/p.vim:2:1:[ghost] variable w:p_w",
            "plugin/p.vim:3:1:[ghost] variable t:p_t",
        ]
    );
}

/// FUNCTION: The global class on, with one pattern of names another
/// plugin reads.
fn external(pattern: &str) -> Config {
    Config {
        external: vec![pattern.to_string()],
        ..common::cfg_with(globals())
    }
}

#[test]
fn an_external_name_is_not_reported() {
    let dir = project("external", &[("plugin/p.vim", WRITE)]);
    let r = report::analyze(dir.path(), &external("g:p_*")).expect("the scan runs");

    assert!(r.findings.is_empty());
}

#[test]
fn an_external_pattern_that_fits_no_name_withholds_nothing() {
    let dir = project("external-miss", &[("plugin/p.vim", WRITE)]);
    let r = report::analyze(dir.path(), &external("g:q_*")).expect("the scan runs");

    assert_eq!(lines(&r), vec![GHOST]);
}

#[test]
fn an_external_name_still_has_a_symbol() {
    let dir = project("external-symbol", &[("plugin/p.vim", WRITE)]);
    let r = report::analyze(dir.path(), &external("g:p_*")).expect("the scan runs");

    assert_eq!(r.summary.symbols, 1);
}

const WHOLE: &str = "vim9script\ng:p_x = 1\necho keys(g:)\necho keys(g:)\n";

#[test]
fn a_scope_credited_whole_makes_one_note_and_no_finding() {
    let dir = project("whole", &[("plugin/p.vim", WHOLE)]);
    let r = run(&dir, globals());

    assert!(r.findings.is_empty());
    assert_eq!(
        r.notes,
        vec![report::Note {
            file: PathBuf::from("plugin/p.vim"),
            line: 3,
            scope: "g:".to_string(),
        }]
    );
}

#[test]
fn no_note_is_made_where_the_flag_of_the_scope_is_off() {
    let dir = project("whole-off", &[("plugin/p.vim", WHOLE)]);
    let flags = FindingFlags {
        buffer_vars: true,
        ..FindingFlags::default()
    };

    assert!(run(&dir, flags).notes.is_empty());
}

#[test]
fn the_count_of_unplaced_names_does_not_depend_on_a_flag() {
    let text = "vim9script\ng:p_x = 1\necho g:p_x g:other Missing()\n";
    let dir = project("count", &[("plugin/p.vim", text)]);
    let all = FindingFlags {
        globals: true,
        buffer_vars: true,
        window_vars: true,
        tab_vars: true,
        ..FindingFlags::default()
    };

    let off = run(&dir, FindingFlags::default()).summary.unplaced_names;

    assert_eq!(off, 1);
    assert_eq!(run(&dir, all).summary.unplaced_names, off);
}

/// A read in a function nothing reaches credits nothing, so the
/// variable is reported, and a note that said none is reported would
/// be false.
#[test]
fn a_scope_read_whole_in_dead_code_makes_no_note() {
    let dir = project(
        "whole-dead",
        &[(
            "plugin/p.vim",
            "vim9script\ng:p_x = 1\ndef Dead()\n  echo keys(g:)\nenddef\n",
        )],
    );
    let r = run(&dir, globals());

    assert!(r.notes.is_empty(), "{:?}", r.notes);
    assert!(lines(&r).contains(&GHOST.to_string()));
}
