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

use serde_json::Value;

const CORPORA: &[&str] = &["bartleby", "ghostcode", "logger", "nested"];

/// FUNCTION: The repository root, which holds the fixtures.
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

/// FUNCTION: The name a fixture carries for one setting of the
/// exports rule, which is what tells the captured pair apart.
fn mode(strict: bool) -> &'static str {
    if strict {
        "strict"
    } else {
        "api"
    }
}

/// FUNCTION: Run the built binary over one corpus and return what it
/// wrote, so that a scan which fails to run says so in one place
/// rather than in each caller.
fn run(corpus: &str, strict: bool, format: &str) -> String {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_ghostcode"));
    cmd.arg(format!("--format={format}"));

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

/// FUNCTION: Every local finding of one corpus, with the class turned
/// on, each line carrying the corpus it came from.
fn locals(corpus: &str) -> Vec<String> {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_ghostcode"));
    let out = cmd
        .args([
            "--format=text",
            "--exports-are-api",
            "false",
            "--locals",
            "true",
        ])
        .arg(root().join("tests/fixtures/corpora").join(corpus))
        .output()
        .expect("run the built binary");

    assert!(
        out.status.success(),
        "{corpus}: the scan failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    String::from_utf8(out.stdout)
        .expect("the report is UTF-8")
        .lines()
        .filter(|l| l.contains("[local]"))
        .map(|l| format!("{corpus}/{l}"))
        .collect()
}

/// The counts, not the findings. The captured fixtures hold what each
/// corpus reports, and nothing held what it counted, so a change could
/// trade false credits for real gaps and still read as an improvement.
///
/// These move deliberately. A fall is usually right, because placing a
/// name is the point of issue 12, but it is only right when nothing
/// new became unplaced, and the fixtures above cannot tell you that.
/// Update a number here with the reason in the commit message.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn each_corpus_counts_what_it_counted() {
    // corpus, ghost findings, unplaced names
    const COUNTS: &[(&str, u64, u64)] = &[
        ("bartleby", 0, 2360),
        ("ghostcode", 0, 25),
        ("logger", 0, 74),
        ("nested", 2, 194),
    ];

    let mut differences: Vec<String> = Vec::new();

    for (corpus, ghost, unplaced) in COUNTS {
        let got: Value =
            serde_json::from_str(&run(corpus, false, "json")).expect("the report is JSON");
        let summary = &got["summary"];

        for (field, want) in [("ghost", ghost), ("unplaced_names", unplaced)] {
            let is = summary[field].as_u64().unwrap_or_default();

            if is != *want {
                differences.push(format!("{corpus}: {field} {is}, recorded {want}"));
            }
        }
    }

    assert!(differences.is_empty(), "{}", differences.join("\n"));
}

/// The class's own fixture. Every line was read against its source
/// before being recorded: a line that is not a variable the author
/// would want to hear about is a defect in the rule, not a fixture to
/// accept.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
#[test]
fn the_local_class_finds_what_the_corpora_hold() {
    let found: Vec<String> = CORPORA.iter().flat_map(|c| locals(c)).collect();
    let want = std::fs::read_to_string(root().join("tests/fixtures/expected/locals.txt"))
        .expect("the local fixture");

    assert_eq!(found, want.lines().collect::<Vec<&str>>());
}

/// FUNCTION: What the core reports for one corpus, in the text form
/// that Vim's own workflow writes out of the quickfix list.
fn scan(corpus: &str, strict: bool) -> String {
    run(corpus, strict, "text")
}

/// FUNCTION: What the core reports for one corpus as JSON, which is
/// the form every consumer other than a person at a terminal reads.
fn scan_json(corpus: &str, strict: bool) -> Value {
    serde_json::from_str(&run(corpus, strict, "json")).expect("the report is JSON")
}

/// FUNCTION: What the Vim9 analyzer reported for one corpus.
fn expected(corpus: &str, strict: bool) -> String {
    let path = root().join(format!(
        "tests/fixtures/expected/{corpus}-{}.txt",
        mode(strict)
    ));

    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// FUNCTION: What the Vim9 analyzer reported for one corpus, as the
/// JSON form derived from its quickfix output.
fn expected_json(corpus: &str, strict: bool) -> Value {
    let path = root().join(format!(
        "tests/fixtures/expected/{corpus}-{}.json",
        mode(strict)
    ));
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));

    serde_json::from_str(&text).expect("the fixture is JSON")
}

#[test]
fn each_corpus_matches_what_the_vim9_analyzer_reported() {
    let mut differences: Vec<String> = Vec::new();

    for corpus in CORPORA {
        for strict in [false, true] {
            let got = scan(corpus, strict);
            let want = expected(corpus, strict);

            if got != want {
                differences.push(format!(
                    "{corpus}-{}:\n  reported now:\n{}\n  reported then:\n{}",
                    mode(strict),
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

/// The findings are compared whole, so a field added to one of them
/// without a reason fails here.
///
/// Two fields of the report are left out, because no fixture can carry
/// them. The root is the absolute path of the machine that ran the
/// capture, and the summary was never captured at all: the old
/// analyzer's own counts included its regex scanner's accidents.
/// Their serialised shape is pinned by tests/report.rs instead.
///
/// Only the `nested` corpus reports findings. For the other three the
/// comparison is one empty list against another, which is the point:
/// they prove the core invents nothing across 36,335 lines of real
/// code.
#[test]
fn each_corpus_matches_the_json_the_vim9_analyzer_reported() {
    let mut differences: Vec<String> = Vec::new();

    for corpus in CORPORA {
        for strict in [false, true] {
            let got = scan_json(corpus, strict);
            let want = expected_json(corpus, strict);
            let tag = format!("{corpus}-{}", mode(strict));

            // A file the scan cannot read declares nothing, so a
            // skip can leave the findings identical while the scan
            // has read less than the capture did.
            if got["skipped"] != Value::Array(Vec::new()) {
                differences.push(format!(
                    "{tag}: the scan dropped a file:\n{}",
                    indent(&pretty(&got["skipped"]))
                ));
            }

            if got["findings"] != want["findings"] {
                differences.push(format!(
                    "{tag}:\n  reported now:\n{}\n  reported then:\n{}",
                    indent(&pretty(&got["findings"])),
                    indent(&pretty(&want["findings"]))
                ));
            }
        }
    }

    assert!(
        differences.is_empty(),
        "the port changed the JSON report:\n{}",
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

/// FUNCTION: One JSON value as indented text, so that a difference is
/// read line by line rather than as one long line.
fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).expect("a parsed value serialises")
}
