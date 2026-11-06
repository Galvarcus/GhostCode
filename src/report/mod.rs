//! The report: what a run found, and the pipeline that found it.
//!
//! License: GNU GPL 3.0

mod json;
mod text;

use std::collections::HashSet;
use std::path::Path;
use std::path::PathBuf;

use serde::Serialize;

pub use json::json;
pub use text::text;

use crate::config::Config;
use crate::lang;
use crate::model::Analysis;
use crate::model::Class;
use crate::model::Kind;
use crate::model::Sink;
use crate::model::SymbolId;
use crate::project;
use crate::reach;
use crate::resolve;

/// The version of the output's shape. It rises when a change would
/// break a reader, and it is not the binary's version: a front end
/// that meets a schema it does not know says so and stops, rather
/// than guessing.
pub const SCHEMA: u32 = 1;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Summary {
    pub symbols: usize,
    pub ghost: usize,

    /// How many variables of a function body nothing reads. Zero
    /// unless the class is asked for, and counted apart from the
    /// ghosts because a build that counts ghosts must not see one.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub local: usize,
    /// References that named nothing this project declares and that
    /// the host language does not own. It measures what the analyzer
    /// could not place rather than what a reader should act on. The
    /// front end does not show it, and no part of the report is
    /// derived from it.
    pub unplaced_names: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Finding {
    pub class: Class,
    pub kind: Kind,
    pub name: String,
    pub file: PathBuf,
    pub line: u32,
    pub col: u32,
    pub lang: &'static str,
}

/// A file discovery found and could not read. It is reported rather
/// than passed over in silence: a symbol that only the dropped file
/// uses looks unreferenced, so a finding this causes cannot be
/// explained without it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Dropped {
    pub file: PathBuf,
    pub why: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Report {
    pub schema: u32,
    pub root: PathBuf,
    pub summary: Summary,
    pub findings: Vec<Finding>,
    pub skipped: Vec<Dropped>,
}

/// FUNCTION: One run, from a root to a report: discover the files,
/// scan each in its own language, resolve every reference, walk the
/// graph from the roots, and report what nothing reached.
///
/// # Errors
/// When the root cannot be read, or a configured glob will not
/// compile.
pub fn analyze(root: &Path, cfg: &Config) -> anyhow::Result<Report> {
    let found = project::discover(root, cfg)?;
    let mut a = Analysis::default();

    let files: HashSet<PathBuf> = found.sources.iter().map(|s| s.rel.clone()).collect();

    for src in &found.sources {
        let Some(lang) = lang::for_path(&src.rel) else {
            continue;
        };

        lang.scan(src, &mut a)?;

        if lang.is_entry(root, &src.rel) || cfg.entry.contains(&src.rel) {
            a.root(SymbolId::script(&src.rel));
        }
    }

    // An import to a file the scan never discovered names nothing: it
    // is outside the root, or git ignores it, which is the same answer
    // discovery gave for the file itself.
    a.imports.retain(|i| files.contains(&i.to));

    // An exported symbol is public API, so it is a root as well as
    // being unreportable: what its body calls is used.
    if cfg.exports_are_api {
        let exported: Vec<SymbolId> = a
            .syms
            .iter()
            .filter(|s| is_api(s, cfg))
            .map(|s| s.id.clone())
            .collect();
        for id in exported {
            a.root(id);
        }
    }

    text_references(&mut a);

    let resolved = resolve::all(&a);
    let reached = reach::walk(&a, &resolved);

    let mut report = build(root, &a, &reached, resolved.unplaced, cfg);

    report.skipped = found
        .skipped
        .iter()
        .map(|s| Dropped {
            file: s.path.strip_prefix(root).unwrap_or(&s.path).to_path_buf(),
            why: match s.why {
                project::SkipReason::NotUtf8 => "not UTF-8",
                project::SkipReason::Unreadable => "cannot be read",
                project::SkipReason::OutsideRoot => "outside the root",
            },
        })
        .collect();

    Ok(report)
}

/// FUNCTION: Turn the text a project holds into references, for the
/// names the project itself declares.
///
/// Vim evaluates text in places no parser can see: the right-hand side
/// of a mapping, a command's completion function, a `feedkeys`
/// sequence, a substitution opening with `\=`. A name used only there
/// is still used, and reporting it would be a finding the author
/// cannot act on, so this pass credits it.
///
/// Only a name the project declares becomes a reference. A word in a
/// message that matches nothing stays a word, so the count of what
/// resolved to nothing keeps its meaning.
///
/// A variable of a function body is named only by text inside that
/// body. Matching one from anywhere would turn every string holding a
/// short word into a reference that resolves to nothing, because a
/// body's `md` or `n` is a word thousands of strings contain.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn text_references(a: &mut Analysis) {
    let names: HashSet<&str> = a
        .syms
        .iter()
        .filter(|s| s.scope.is_none())
        .map(|s| s.name.as_str())
        .collect();

    let scoped: HashSet<(&crate::model::SymbolId, &str)> = a
        .syms
        .iter()
        .filter_map(|s| s.scope.as_ref().map(|at| (at, s.name.as_str())))
        .collect();

    let mut found: Vec<crate::model::Reference> = Vec::new();

    for t in &a.texts {
        for name in lang::vim9::parse::identifiers(&t.text) {
            let visible = names.contains(name.as_str())
                || t.origin
                    .as_ref()
                    .is_some_and(|at| scoped.contains(&(at, name.as_str())));

            if !visible {
                continue;
            }

            found.push(crate::model::Reference {
                name,
                recv: None,
                file: t.file.clone(),
                line: t.line,
                origin: t.origin.clone(),
                target: None,
                owned: false,
            });
        }
    }

    a.refs.extend(found);
}

/// FUNCTION: Turn what a walk reached into the report of what it did
/// not.
pub fn build(
    root: &Path,
    a: &Analysis,
    reached: &HashSet<SymbolId>,
    unplaced_names: usize,
    cfg: &Config,
) -> Report {
    let mut findings: Vec<Finding> = a
        .syms
        .iter()
        .filter_map(|s| {
            classify(s, reached, cfg).map(|class| Finding {
                class,
                kind: s.kind,
                name: s.name.clone(),
                file: s.file.clone(),
                line: s.line,
                col: 1,
                lang: lang::for_path(&s.file).map_or("", |l| l.name()),
            })
        })
        .collect();

    findings.sort_by(|a, b| a.file.cmp(&b.file).then(a.line.cmp(&b.line)));

    Report {
        schema: SCHEMA,
        root: root.to_path_buf(),
        summary: Summary {
            symbols: a.syms.len(),
            ghost: count(&findings, Class::Ghost),
            local: count(&findings, Class::Local),
            unplaced_names,
        },
        findings,
        skipped: Vec::new(),
    }
}

/// FUNCTION: Whether a symbol is public API, asked of the language
/// that declared it.
/// FUNCTION: Which class a symbol is reported as, or none when it is
/// not reported at all.
///
/// A variable of a function body is reported when its body is reached
/// and nothing credits it. The body being reached is the test that
/// matters: a dead function is itself the finding, and naming its
/// variables beside it would report the symptom several times over
/// and the cause once. A local cannot be exported, so the API rule
/// has nothing to say about one.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
fn classify(
    sym: &crate::model::Symbol,
    reached: &HashSet<SymbolId>,
    cfg: &Config,
) -> Option<Class> {
    if let Some(body) = &sym.scope {
        let unread = cfg.findings.locals && reached.contains(body) && !reached.contains(&sym.id);

        return unread.then_some(Class::Local);
    }

    (!reached.contains(&sym.id) && !is_api(sym, cfg)).then_some(Class::Ghost)
}

/// FUNCTION: How many findings carry one class.
fn count(findings: &[Finding], class: Class) -> usize {
    findings.iter().filter(|f| f.class == class).count()
}

fn is_api(sym: &crate::model::Symbol, cfg: &Config) -> bool {
    lang::for_path(&sym.file).is_some_and(|l| l.is_api(sym, cfg))
}
