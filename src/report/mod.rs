//! The report: what a run found, and the pipeline that found it.
//!
//! License: GNU GPL 3.0

mod json;
mod text;

use std::collections::HashMap;
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

    fold(&mut a);
    text_references(&mut a);
    fit_references(&mut a);

    let resolved = resolve::all(&a);
    let reached = reach::walk(&a, &resolved);

    let blind = unplaced_names_by_file(&a, &resolved);
    let mut report = build(root, &a, &reached, &blind, resolved.unplaced, cfg);

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

/// FUNCTION: Keep one symbol for each id that belongs to no file.
///
/// A variable every file shares is declared by each write of it, in
/// any file, and all of them are one variable. The one kept is the
/// write a finding names: a lead one where the scan marked one, and
/// otherwise the first by path and line.
///
/// Only such an id is folded. Two declarations of one name in one
/// file are two symbols, as the two arms of an `if` may each hold a
/// `def`, and each is reported for itself.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
fn fold(a: &mut Analysis) {
    let mut kept: HashMap<SymbolId, usize> = HashMap::new();

    for (at, sym) in a.syms.iter().enumerate() {
        if !sym.id.is_shared() {
            continue;
        }

        let first = |s: &crate::model::Symbol| (!s.lead, s.file.clone(), s.line);

        match kept.get(&sym.id) {
            Some(&best) if first(&a.syms[best]) <= first(sym) => {}
            _ => {
                kept.insert(sym.id.clone(), at);
            }
        }
    }

    let mut at = 0;
    a.syms.retain(|sym| {
        let keep = !sym.id.is_shared() || kept.get(&sym.id) == Some(&at);
        at += 1;
        keep
    });
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
                member: false,
            });
        }
    }

    a.refs.extend(found);
}

/// FUNCTION: Turn each name with a gap into a reference to every
/// symbol its fixed parts fit.
///
/// Only a symbol that belongs to no file can be named this way. Their
/// names are sorted once, so a fit reads the run that shares its
/// start and never the whole list: the cost stays that of the names
/// it credits.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
fn fit_references(a: &mut Analysis) {
    let mut names: Vec<(&str, &SymbolId)> = a
        .syms
        .iter()
        .filter(|s| s.id.is_shared())
        .map(|s| (s.name.as_str(), &s.id))
        .collect();
    names.sort_unstable();

    let mut found: Vec<crate::model::Reference> = Vec::new();

    for fit in &a.fits {
        let from = names.partition_point(|(name, _)| *name < fit.head.as_str());
        let least = fit.head.len() + fit.tail.len();

        for (name, id) in names[from..]
            .iter()
            .take_while(|(name, _)| name.starts_with(&fit.head))
            .filter(|(name, _)| name.len() >= least && name.ends_with(&fit.tail))
        {
            found.push(crate::model::Reference {
                name: (*name).to_string(),
                recv: None,
                file: fit.file.clone(),
                line: fit.line,
                origin: fit.origin.clone(),
                target: Some((*id).clone()),
                owned: true,
                member: false,
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
    blind: &HashSet<(&Path, &str)>,
    unplaced_names: usize,
    cfg: &Config,
) -> Report {
    let mut findings: Vec<Finding> = a
        .syms
        .iter()
        .filter_map(|s| {
            classify(s, reached, blind, cfg).map(|class| Finding {
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
    blind: &HashSet<(&Path, &str)>,
    cfg: &Config,
) -> Option<Class> {
    // A symbol that belongs to no file is reported by no rule yet.
    // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    if sym.id.is_shared() {
        return None;
    }

    if let Some(body) = &sym.scope {
        let unread = cfg.findings.locals
            && reached.contains(body)
            && !reached.contains(&sym.id)
            && !blind.contains(&(sym.file.as_path(), sym.name.as_str()));

        return unread.then_some(Class::Local);
    }

    (!reached.contains(&sym.id) && !is_api(sym, cfg)).then_some(Class::Ghost)
}

/// FUNCTION: The names a file holds a reference to that resolution
/// could not place.
///
/// A def inside a def reads the enclosing body's variables, and the
/// inner body's id does not name the outer one, so such a read is
/// placed only where the file declares the name once. Where it is not
/// placed, the analyzer has seen a read of that name and cannot say
/// which variable it meant, so it must not claim any variable of that
/// name is unread.
///
/// A reference the language owns is not such a read. The analyzer
/// placed it: the name is the language's there, and no variable was
/// read, so it hides no finding. A name behind a dot is none either:
/// it is a member or a key, and a variable is never read through a
/// dot.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/48
fn unplaced_names_by_file<'a>(
    a: &'a Analysis,
    r: &crate::resolve::Resolved,
) -> HashSet<(&'a Path, &'a str)> {
    a.refs
        .iter()
        .enumerate()
        .filter(|(at, re)| !re.owned && !re.member && !r.targets.contains_key(at))
        .map(|(_, re)| (re.file.as_path(), re.name.as_str()))
        .collect()
}

/// FUNCTION: How many findings carry one class.
fn count(findings: &[Finding], class: Class) -> usize {
    findings.iter().filter(|f| f.class == class).count()
}

/// FUNCTION: Whether a symbol is public API, asked of the language
/// that declared it.
fn is_api(sym: &crate::model::Symbol, cfg: &Config) -> bool {
    lang::for_path(&sym.file).is_some_and(|l| l.is_api(sym, cfg))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Symbol;

    /// FUNCTION: One write of a variable every file shares.
    fn write(name: &str, file: &str, line: u32, lead: bool) -> Symbol {
        Symbol {
            id: SymbolId::shared(name),
            kind: Kind::Variable,
            name: name.to_string(),
            file: PathBuf::from(file),
            line,
            exported: false,
            owner: None,
            scope: None,
            lead,
        }
    }

    /// FUNCTION: Where each symbol of an analysis stands after a fold.
    fn folded(syms: Vec<Symbol>) -> Vec<(String, u32)> {
        let mut a = Analysis {
            syms,
            ..Analysis::default()
        };
        fold(&mut a);

        a.syms
            .iter()
            .map(|s| (s.file.display().to_string(), s.line))
            .collect()
    }

    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    #[test]
    fn several_writes_of_one_shared_name_fold_to_the_lead_one() {
        let syms = vec![
            write("g:x", "autoload/a.vim", 9, false),
            write("g:x", "plugin/p.vim", 4, true),
            write("g:x", "plugin/p.vim", 2, false),
        ];

        assert_eq!(folded(syms), vec![("plugin/p.vim".to_string(), 4)]);
    }

    #[test]
    fn with_no_lead_write_the_first_by_path_and_line_is_kept() {
        let syms = vec![
            write("g:x", "plugin/p.vim", 4, false),
            write("g:x", "autoload/a.vim", 9, false),
            write("g:x", "plugin/p.vim", 2, false),
        ];

        assert_eq!(folded(syms), vec![("autoload/a.vim".to_string(), 9)]);
    }

    #[test]
    fn two_symbols_of_one_file_id_are_both_kept() {
        let mut one = write("F", "a.vim", 1, false);
        one.id = SymbolId::of(Path::new("a.vim"), None, "F");
        let mut two = one.clone();
        two.line = 5;

        assert_eq!(folded(vec![one, two]).len(), 2);
    }

    /// FUNCTION: A name with a gap, read at one line of one file.
    fn gap(head: &str, tail: &str) -> crate::model::Fit {
        crate::model::Fit {
            head: head.to_string(),
            tail: tail.to_string(),
            whole: tail.is_empty() && head.len() == 2,
            file: PathBuf::from("autoload/a.vim"),
            line: 3,
            origin: None,
        }
    }

    /// FUNCTION: The names the fits of an analysis credit, in order.
    fn credited(names: &[&str], fits: Vec<crate::model::Fit>) -> Vec<String> {
        let mut a = Analysis {
            syms: names
                .iter()
                .map(|n| write(n, "plugin/p.vim", 1, false))
                .collect(),
            fits,
            ..Analysis::default()
        };
        fit_references(&mut a);

        assert!(a.refs.iter().all(|r| r.owned && r.target.is_some()));

        let mut out: Vec<String> = a.refs.into_iter().map(|r| r.name).collect();
        out.sort();
        out
    }

    #[test]
    fn a_fit_credits_each_name_its_fixed_parts_fit() {
        let names = ["g:p_a_fg", "g:p_b_fg", "g:p_a_bg", "b:p_a_fg"];

        assert_eq!(
            credited(&names, vec![gap("g:p_", "fg")]),
            vec!["g:p_a_fg", "g:p_b_fg"]
        );
    }

    #[test]
    fn a_whole_fit_credits_every_name_of_its_scope_and_no_other() {
        let names = ["g:a", "g:b", "b:a", "t:a"];

        assert_eq!(credited(&names, vec![gap("g:", "")]), vec!["g:a", "g:b"]);
    }

    /// The start and the end may not share a character of the name.
    #[test]
    fn a_fit_longer_than_a_name_does_not_fit_it() {
        assert!(credited(&["g:ab"], vec![gap("g:ab", "b")]).is_empty());
    }
}
