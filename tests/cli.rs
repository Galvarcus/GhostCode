//! Arguments and configuration: what a run's settings resolve to.
//!
//! License: GNU GPL 3.0

mod common;

use std::process::Command;

use common::TempDir;
use ghostcode::cli::Args;
use ghostcode::config::Config;

const TOML_STRICT: &str = "exports_are_api = false\n";

/// FUNCTION: Resolve the settings for a root, as a run would.
fn load(root: &std::path::Path, extra: &[&str]) -> Config {
    let mut argv = vec!["ghostcode", root.to_str().expect("a UTF-8 test path")];
    argv.extend_from_slice(extra);
    let args = Args::from_argv(&argv).expect("parse the test's arguments");
    Config::load(root, &args).expect("load the test's configuration")
}

/// FUNCTION: What `--help` prints, which is where a user at a
/// terminal learns that a flag exists.
fn help() -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_ghostcode"))
        .arg("--help")
        .output()
        .expect("run the built binary");
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// FUNCTION: Run the binary on a root and return its status and stderr.
fn run(root: &str) -> (bool, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ghostcode"))
        .arg(root)
        .output()
        .expect("run the built binary");
    (
        out.status.success(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn toml_sets_exports_are_api_when_no_flag_given() {
    let dir = TempDir::new("toml-sets");
    dir.write("ghostcode.toml", TOML_STRICT);

    assert!(!load(dir.path(), &[]).exports_are_api);
}

#[test]
fn flag_overrides_the_toml_value() {
    let dir = TempDir::new("flag-overrides");
    dir.write("ghostcode.toml", TOML_STRICT);

    assert!(load(dir.path(), &["--exports-are-api", "true"]).exports_are_api);
}

#[test]
fn defaults_apply_when_neither_is_present() {
    let dir = TempDir::new("defaults");
    let cfg = load(dir.path(), &[]);

    assert!(cfg.exports_are_api, "an export is public API by default");
    assert!(cfg.ignore.is_empty());
    assert!(cfg.entry.is_empty());
    assert!(!cfg.no_ignore);
    assert!(!cfg.findings.write_only);
    assert!(!cfg.findings.locals);
}

#[test]
fn a_toml_ignore_glob_reaches_the_configuration() {
    let dir = TempDir::new("toml-ignore");
    dir.write("ghostcode.toml", "ignore = [\"deps/**\"]\n");

    assert_eq!(load(dir.path(), &[]).ignore, vec!["deps/**".to_string()]);
}

#[test]
fn a_missing_root_exits_nonzero_with_one_message() {
    let dir = TempDir::new("missing-root");
    let missing = dir.path().join("nowhere");
    let (ok, err) = run(missing.to_str().expect("a UTF-8 test path"));

    assert!(!ok, "a root that does not exist must fail the run");
    assert_eq!(err.lines().count(), 1, "one message, not a panic: {err}");
    assert!(err.contains("nowhere"), "the message names the root: {err}");
}

#[test]
fn a_file_as_root_exits_nonzero_with_one_message() {
    let dir = TempDir::new("file-root");
    let file = dir.write("notadir.vim", "vim9script\n");
    let (ok, err) = run(file.to_str().expect("a UTF-8 test path"));

    assert!(!ok, "a file as root must fail the run");
    assert_eq!(err.lines().count(), 1, "one message, not a panic: {err}");
    assert!(
        err.contains("notadir.vim"),
        "the message names the root: {err}"
    );
}

#[test]
fn the_help_names_the_locals_flag() {
    let text = help();

    assert!(
        text.contains("--locals"),
        "a user cannot ask for a class the help does not name: {text}"
    );
}

#[test]
fn the_help_hides_a_flag_that_no_detection_backs() {
    let text = help();

    assert!(
        !text.contains("--write-only"),
        "nothing emits the class, so the flag promises what it cannot give: {text}"
    );
}
