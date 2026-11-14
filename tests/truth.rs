//! Truth: small projects where each declaration states, on the line
//! above it, whether it is a ghost.
//!
//! The corpora prove that a change keeps the findings as they were.
//! They cannot prove that a finding is a ghost, or that no ghost is
//! missed, because nothing in them states which symbol is which. Each
//! directory here is a project of one family of constructs that does.
//! REFERENCE: https://github.com/Galvarcus/GhostCode/issues/80
//!
//! License: GNU GPL 3.0

use std::collections::BTreeMap;
use std::collections::BTreeSet;
use std::path::Path;
use std::path::PathBuf;

use ghostcode::cli::Args;
use ghostcode::config::Config;
use ghostcode::lang;
use ghostcode::model::Analysis;
use ghostcode::project;
use ghostcode::report;
use ghostcode::NAME;

const TRUTH: &str = "tests/fixtures/truth";

/// What the line above a declaration states about it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mark {
    /// Nothing uses the symbol, and a finding names it.
    Ghost,
    /// Something uses the symbol, and no finding names it.
    Live,
    /// Nothing uses the symbol and no finding names it, which the
    /// readme states as a limit.
    Missed,
}

impl Mark {
    const ALL: [(Self, &'static str); 3] = [
        (Self::Ghost, "# GHOST"),
        (Self::Live, "# LIVE"),
        (Self::Missed, "# MISSED"),
    ];

    /// METHOD: The mark a line states, where the line is a marker and
    /// nothing else.
    fn of(line: &str) -> Option<Self> {
        Self::ALL
            .iter()
            .find(|(_, text)| line.trim() == *text)
            .map(|(mark, _)| *mark)
    }
}

/// A line of a file of one family, by the path from the family root.
type Place = (PathBuf, u32);

/// FUNCTION: Every family, in the order of its name, so that a
/// failure reads the same on each run.
fn families() -> Vec<PathBuf> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join(TRUTH);

    let mut all: Vec<PathBuf> = std::fs::read_dir(&dir)
        .expect("read the truth directory")
        .map(|entry| entry.expect("read an entry of the truth directory").path())
        .filter(|path| path.is_dir())
        .collect();

    all.sort();
    all
}

/// FUNCTION: The settings a family states in its own root, with no
/// flag, so that a family alone decides which classes it proves.
fn settings(root: &Path) -> Config {
    let path = root.to_str().expect("the root is UTF-8");
    let args = Args::from_argv(&[NAME, path]).expect("parse the arguments");

    Config::load(root, &args).expect("load the settings of the family")
}

/// FUNCTION: The line each marker speaks for, which is the line below
/// it, and the symbols the scan declares. The files are the ones a
/// scan reads, so that this test holds no rule of its own on what a
/// declaration is.
fn scanned(root: &Path, cfg: &Config) -> (BTreeMap<Place, Mark>, BTreeSet<Place>) {
    let found = project::discover(root, cfg).expect("discover the files of the family");
    let mut marks = BTreeMap::new();
    let mut a = Analysis::default();

    for src in &found.sources {
        for (idx, line) in src.text.lines().enumerate() {
            if let Some(mark) = Mark::of(line) {
                let below = u32::try_from(idx).expect("a line number fits") + 2;
                marks.insert((src.rel.clone(), below), mark);
            }
        }

        if let Some(lang) = lang::for_path(&src.rel) {
            lang.scan(src, &mut a).expect("scan a file of the family");
        }
    }

    let syms = a.syms.iter().map(|s| (s.file.clone(), s.line)).collect();

    (marks, syms)
}

/// FUNCTION: Every way one family differs from its markers, each as a
/// line that names the file and the line.
fn differences(root: &Path) -> Vec<String> {
    let cfg = settings(root);
    let (marks, syms) = scanned(root, &cfg);

    let found: BTreeSet<Place> = report::analyze(root, &cfg)
        .expect("analyze the family")
        .findings
        .iter()
        .map(|f| (f.file.clone(), f.line))
        .collect();

    let family = root
        .file_name()
        .expect("a family has a name")
        .to_string_lossy();
    let at = |place: &Place| format!("{family}/{}:{}", place.0.display(), place.1);
    let mut out = Vec::new();

    for (place, mark) in &marks {
        let named = found.contains(place);

        match mark {
            Mark::Ghost if !named => out.push(format!("{}: a ghost with no finding", at(place))),
            Mark::Live if named => out.push(format!("{}: a finding on a live symbol", at(place))),
            Mark::Missed if named => out.push(format!(
                "{}: a finding on a limit, so the marker and the readme are out of date",
                at(place)
            )),
            _ => {}
        }

        if *mark != Mark::Missed && !syms.contains(place) {
            out.push(format!("{}: a marker above no symbol", at(place)));
        }
    }

    for place in syms.iter().chain(&found) {
        if !marks.contains_key(place) {
            out.push(format!("{}: a symbol with no marker", at(place)));
        }
    }

    out.sort();
    out.dedup();
    out
}

#[test]
fn the_truth_corpus_holds_a_family() {
    assert!(
        !families().is_empty(),
        "no family under {TRUTH}, so the other test proves nothing"
    );
}

#[test]
fn each_family_reports_what_its_markers_state() {
    let all: Vec<String> = families().iter().flat_map(|f| differences(f)).collect();

    assert!(all.is_empty(), "\n{}\n", all.join("\n"));
}
