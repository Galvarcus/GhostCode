//! The speed the port exists for, measured where a regression would
//! otherwise go unnoticed.
//!
//! The Vim9 analyzer took 105.97 seconds over the Bartleby corpus. The
//! ceiling here is five seconds: several times the measured figure, so
//! that a loaded runner does not fail a build, and still twenty times
//! below the behaviour this replaces.
//!
//! License: GNU GPL 3.0

use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;
use std::time::Instant;

/// What the Vim9 analyzer took over the same corpus, for the message
/// a failure prints.
const BEFORE: f64 = 105.97;

const CEILING: Duration = Duration::from_secs(5);

#[test]
fn scanning_the_bartleby_corpus_stays_under_the_ceiling() {
    let corpus = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/corpora/bartleby");

    // One scan first, so that the measured one reads a warm cache and
    // measures the analyzer rather than the disk.
    let run = || {
        let out = Command::new(env!("CARGO_BIN_EXE_ghostcode"))
            .arg("--format=text")
            .arg(&corpus)
            .output()
            .expect("run the built binary");
        assert!(out.status.success(), "the scan failed");
    };

    run();

    let start = Instant::now();
    run();
    let spent = start.elapsed();

    println!(
        "bartleby: {:.3}s, against {BEFORE}s before the port",
        spent.as_secs_f64()
    );

    assert!(
        spent < CEILING,
        "the scan took {spent:?}, over the {CEILING:?} ceiling: \
         resolution is walking the symbols again"
    );
}
