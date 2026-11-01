//! Discovery: which files a scan reads, and which it refuses.
//!
//! License: GNU GPL 3.0

mod common;

use std::path::Path;

use common::TempDir;
use ghostcode::cli::Args;
use ghostcode::config::Config;
use ghostcode::project;
use ghostcode::project::SkipReason;

const SRC: &str = "vim9script\ndef F()\nenddef\n";

/// FUNCTION: Discover a root's sources, with the given extra flags.
fn found(dir: &TempDir, extra: &[&str]) -> project::Found {
    let root = dir.path();
    let mut argv = vec!["ghostcode", root.to_str().expect("a UTF-8 test path")];
    argv.extend_from_slice(extra);
    let args = Args::from_argv(&argv).expect("parse the test's arguments");
    let cfg = Config::load(root, &args).expect("load the test's configuration");
    project::discover(root, &cfg).expect("discover the test's sources")
}

/// FUNCTION: The discovered paths, relative to the root, as text.
fn rels(f: &project::Found) -> Vec<String> {
    f.sources
        .iter()
        .map(|s| s.rel.to_string_lossy().into_owned())
        .collect()
}

#[test]
fn a_gitignored_file_is_not_scanned() {
    let dir = TempDir::new("gitignored");
    dir.git_init();
    dir.write(".gitignore", "Snippets\n");
    dir.write("autoload/p.vim", SRC);
    dir.write("Snippets/s.vim", SRC);

    assert_eq!(rels(&found(&dir, &[])), vec!["autoload/p.vim"]);
}

#[test]
fn no_ignore_scans_a_gitignored_file() {
    let dir = TempDir::new("no-ignore");
    dir.git_init();
    dir.write(".gitignore", "Snippets\n");
    dir.write("autoload/p.vim", SRC);
    dir.write("Snippets/s.vim", SRC);

    assert_eq!(
        rels(&found(&dir, &["--no-ignore"])),
        vec!["Snippets/s.vim", "autoload/p.vim"]
    );
}

#[test]
fn a_symlink_leaving_the_root_is_not_followed() {
    let outside = TempDir::new("outside-target");
    outside.write("dep.vim", SRC);

    let dir = TempDir::new("symlink-out");
    dir.write("autoload/p.vim", SRC);
    dir.link("deps/Logger", outside.path());

    let f = found(&dir, &[]);
    assert_eq!(rels(&f), vec!["autoload/p.vim"]);
    assert!(
        f.skipped.iter().all(|s| s.why != SkipReason::NotUtf8),
        "a symlink out is not a decoding fault"
    );
}

#[test]
fn a_symlink_inside_the_root_is_scanned_once() {
    let dir = TempDir::new("symlink-in");
    let real = dir.write("autoload/p.vim", SRC);
    dir.link("alias.vim", &real);

    let f = found(&dir, &[]);
    assert_eq!(rels(&f), vec!["autoload/p.vim"], "the real path, once");
}

#[test]
fn an_ignore_glob_from_the_config_removes_a_tracked_file() {
    let dir = TempDir::new("cfg-ignore");
    dir.git_init();
    dir.write("ghostcode.toml", "ignore = [\"vendor/**\"]\n");
    dir.write("autoload/p.vim", SRC);
    dir.write("vendor/v.vim", SRC);

    assert_eq!(rels(&found(&dir, &[])), vec!["autoload/p.vim"]);
}

#[test]
fn a_directory_with_no_git_repository_scans_every_file() {
    let dir = TempDir::new("no-repo");
    dir.write(".gitignore", "Snippets\n");
    dir.write("autoload/p.vim", SRC);
    dir.write("Snippets/s.vim", SRC);

    assert_eq!(
        rels(&found(&dir, &[])),
        vec!["Snippets/s.vim", "autoload/p.vim"],
        "a gitignore rule outside a repository governs nothing"
    );
}

#[test]
fn a_non_utf8_file_is_skipped_and_reported_not_fatal() {
    let dir = TempDir::new("latin1");
    dir.write("autoload/p.vim", SRC);
    dir.write_bytes("autoload/old.vim", b"vim9script\n# caf\xe9\n");

    let f = found(&dir, &[]);
    assert_eq!(rels(&f), vec!["autoload/p.vim"], "the good file survives");
    assert_eq!(f.skipped.len(), 1, "the bad file is reported once");
    assert_eq!(f.skipped[0].why, SkipReason::NotUtf8);
    assert!(f.skipped[0].path.ends_with(Path::new("autoload/old.vim")));
}

#[test]
fn the_bartleby_corpus_yields_every_tracked_file() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/corpora/bartleby");
    let args = Args::from_argv(&["ghostcode", root.to_str().expect("a UTF-8 path")])
        .expect("parse the arguments");
    let cfg = Config::load(&root, &args).expect("load the configuration");
    let f = project::discover(&root, &cfg).expect("discover the corpus");

    assert_eq!(
        f.sources.len(),
        135,
        "every tracked Vim file Vim would source"
    );
    assert!(f.skipped.is_empty(), "nothing in the corpus is unreadable");
    assert!(
        !rels(&f).contains(&".github/scripts/latex-needs.vim".to_string()),
        "a hidden directory is Vim's blind spot and the analyzer's"
    );
}

#[test]
fn a_configured_entry_is_scanned_though_it_is_hidden() {
    let dir = TempDir::new("entry-hidden");
    dir.write("ghostcode.toml", "entry = [\".github/scripts/s.vim\"]\n");
    dir.write(".github/scripts/s.vim", SRC);
    dir.write("autoload/p.vim", SRC);

    assert_eq!(
        rels(&found(&dir, &[])),
        vec![".github/scripts/s.vim", "autoload/p.vim"],
        "naming a file an entry says it is the project's own code"
    );
}
