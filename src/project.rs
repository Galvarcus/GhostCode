//! Discovery: which files a scan reads, and which it refuses.
//!
//! License: GNU GPL 3.0

use std::collections::HashSet;
use std::path::Path;
use std::path::PathBuf;

use anyhow::Context;
use ignore::overrides::OverrideBuilder;
use ignore::WalkBuilder;

use crate::config::Config;

/// Why a file that discovery found was not read. A fault in one file
/// never ends a run, so each one is collected and reported instead.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkipReason {
    NotUtf8,
    Unreadable,
    OutsideRoot,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Skipped {
    pub path: PathBuf,
    pub why: SkipReason,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Source {
    pub path: PathBuf,
    pub rel: PathBuf,
    pub text: String,
    pub lang: &'static str,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Found {
    pub sources: Vec<Source>,
    pub skipped: Vec<Skipped>,
}

/// FUNCTION: Read every file a scan should see: nothing git ignores,
/// nothing a configured glob removes, and nothing a symlink reaches
/// outside the root, because a finding outside the root is one the
/// caller cannot act on and CI will never see.
///
/// A file is identified by the path it really has, so that a symlink
/// inside the root yields its target once rather than twice. The order
/// is by that path, so that a run is reproducible.
///
/// # Errors
/// When the root cannot be resolved, or a configured glob will not
/// compile.
pub fn discover(root: &Path, cfg: &Config) -> anyhow::Result<Found> {
    let root = root
        .canonicalize()
        .with_context(|| format!("{}: cannot be resolved", root.display()))?;

    // A hidden directory is skipped, as Vim's own globpath skips one:
    // Vim sources nothing from `.github`, and a script there is run by
    // hand or by CI, so nothing in the project roots it. A project that
    // wants such a file scanned names it in `entry`, below.
    let mut walk = WalkBuilder::new(&root);
    walk.follow_links(false).parents(false).require_git(true);

    if cfg.no_ignore {
        walk.git_ignore(false)
            .git_global(false)
            .git_exclude(false)
            .ignore(false);
    }

    if !cfg.ignore.is_empty() {
        let mut globs = OverrideBuilder::new(&root);
        for glob in &cfg.ignore {
            globs
                .add(&format!("!{glob}"))
                .with_context(|| format!("{glob}: not a usable ignore glob"))?;
        }
        walk.overrides(globs.build()?);
    }

    let mut found = Found::default();
    let mut seen: HashSet<PathBuf> = HashSet::new();

    for entry in walk.build() {
        let entry = entry.context("the project cannot be walked")?;
        if !entry.path().is_file() {
            continue;
        }

        let Some(lang) = lang_of(entry.path()) else {
            continue;
        };

        // The real path decides identity and position, so a symlink to
        // a file in the root is the file, and a symlink out is neither.
        let path = match entry.path().canonicalize() {
            Ok(path) => path,
            Err(_) => {
                found.skipped.push(Skipped {
                    path: entry.path().to_path_buf(),
                    why: SkipReason::Unreadable,
                });
                continue;
            }
        };

        let Ok(rel) = path.strip_prefix(&root) else {
            found.skipped.push(Skipped {
                path,
                why: SkipReason::OutsideRoot,
            });
            continue;
        };
        let rel = rel.to_path_buf();

        if !seen.insert(path.clone()) {
            continue;
        }

        match std::fs::read(&path) {
            Ok(bytes) => match String::from_utf8(bytes) {
                Ok(text) => found.sources.push(Source {
                    path,
                    rel,
                    text,
                    lang,
                }),
                Err(_) => found.skipped.push(Skipped {
                    path,
                    why: SkipReason::NotUtf8,
                }),
            },
            Err(_) => found.skipped.push(Skipped {
                path,
                why: SkipReason::Unreadable,
            }),
        }
    }

    // A file named as an entry is scanned wherever it sits, because
    // naming it an entry point says it is the project's own code.
    for rel in &cfg.entry {
        let path = root.join(rel);

        if seen.contains(&path) || !path.is_file() {
            continue;
        }

        let Some(lang) = lang_of(&path) else {
            continue;
        };

        match std::fs::read_to_string(&path) {
            Ok(text) => {
                seen.insert(path.clone());
                found.sources.push(Source {
                    path,
                    rel: rel.clone(),
                    text,
                    lang,
                });
            }
            Err(_) => found.skipped.push(Skipped {
                path,
                why: SkipReason::Unreadable,
            }),
        }
    }

    found.sources.sort_by(|a, b| a.rel.cmp(&b.rel));
    found.skipped.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(found)
}

/// FUNCTION: The language a file's name says it holds, or none when no
/// language claims it.
fn lang_of(path: &Path) -> Option<&'static str> {
    match path.extension()?.to_str()? {
        "vim" => Some("vim9"),
        _ => None,
    }
}
