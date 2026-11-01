//! Parity: the new core against what the Vim9 analyzer reported for
//! four real projects, captured before it was deleted.
//!
//! This is the acceptance test of the port. A difference here is
//! either a defect in this core or a fault in the old one, and neither
//! is accepted without being read.
//!
//! License: GNU GPL 3.0

use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

const CORPORA: &[&str] = &["bartleby", "ghostcode", "logger", "nested"];

/// FUNCTION: The repository root, which holds the fixtures.
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

/// FUNCTION: What the core reports for one corpus, in the text form
/// that Vim's own workflow writes out of the quickfix list.
fn scan(corpus: &str, strict: bool) -> String {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_ghostcode"));
    cmd.arg("--format=text");

    if strict {
        cmd.args(["--exports-are-api", "false"]);
    }

    let out = cmd
        .arg(root().join("tests/fixtures/corpora").join(corpus))
        .output()
        .expect("run the built binary");

    assert!(
        out.status.success(),
        "{corpus}: the scan failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    String::from_utf8(out.stdout).expect("the report is UTF-8")
}

/// FUNCTION: What the Vim9 analyzer reported for one corpus.
fn expected(corpus: &str, strict: bool) -> String {
    let mode = if strict { "strict" } else { "api" };
    let path = root().join(format!("tests/fixtures/expected/{corpus}-{mode}.txt"));

    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

#[test]
fn each_corpus_matches_what_the_vim9_analyzer_reported() {
    let mut differences: Vec<String> = Vec::new();

    for corpus in CORPORA {
        for strict in [false, true] {
            let got = scan(corpus, strict);
            let want = expected(corpus, strict);

            if got != want {
                let mode = if strict { "strict" } else { "api" };
                differences.push(format!(
                    "{corpus}-{mode}:\n  reported now:\n{}\n  reported then:\n{}",
                    indent(&got),
                    indent(&want)
                ));
            }
        }
    }

    assert!(
        differences.is_empty(),
        "the port changed what is reported:\n{}",
        differences.join("\n")
    );
}

#[test]
fn the_nested_corpus_still_finds_what_it_is_there_to_find() {
    let lines = scan("nested", true).lines().count();

    assert_eq!(
        lines, 102,
        "three corpora report nothing by design; this one carries the findings"
    );
}

#[test]
fn a_corpus_scan_reports_nothing_outside_its_own_root() {
    for corpus in CORPORA {
        for line in scan(corpus, true).lines() {
            let file = line.split(':').next().unwrap_or_default();
            assert!(
                !Path::new(file).is_absolute() && !file.starts_with(".."),
                "{corpus}: {line} names a file outside the root"
            );
        }
    }
}

fn indent(text: &str) -> String {
    if text.is_empty() {
        return "    (nothing)".to_string();
    }
    text.lines()
        .map(|l| format!("    {l}"))
        .collect::<Vec<_>>()
        .join("\n")
}
