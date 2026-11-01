//! Reachability: which symbols the entry points can reach.
//!
//! License: GNU GPL 3.0

use std::collections::HashMap;
use std::collections::HashSet;

use crate::model::Analysis;
use crate::model::SymbolId;
use crate::resolve::Resolved;

/// FUNCTION: Every symbol an entry point reaches, through the calls
/// that resolved, the files those symbols live in, and the imports
/// that source one file from another.
///
/// Three kinds of edge make the graph:
///
/// A reference joins the symbol that holds it to each symbol it may
/// name. Where a name was ambiguous it names several, and all of them
/// count, because this analyzer reports only what it can prove.
///
/// A symbol joins its own file's top-level code, because reaching any
/// symbol of a file sources the whole file, and that code then runs.
///
/// An import joins the importing file's top-level code to the imported
/// file's, because an import sources that file whether or not anything
/// it exports is ever named.
pub fn walk(a: &Analysis, r: &Resolved) -> HashSet<SymbolId> {
    let mut edges: HashMap<SymbolId, Vec<SymbolId>> = HashMap::new();

    for (i, targets) in &r.targets {
        let Some(re) = a.refs.get(*i) else {
            continue;
        };
        let origin = re
            .origin
            .clone()
            .unwrap_or_else(|| SymbolId::script(&re.file));

        for target in targets {
            add(&mut edges, origin.clone(), target.clone());
        }
    }

    for sym in &a.syms {
        add(&mut edges, sym.id.clone(), SymbolId::script(&sym.file));
    }

    for imp in &a.imports {
        add(
            &mut edges,
            SymbolId::script(&imp.from),
            SymbolId::script(&imp.to),
        );
    }

    let mut seen: HashSet<SymbolId> = HashSet::new();
    let mut queue: Vec<SymbolId> = a.roots.clone();

    while let Some(id) = queue.pop() {
        if !seen.insert(id.clone()) {
            continue;
        }

        for child in edges.get(&id).into_iter().flatten() {
            if !seen.contains(child) {
                queue.push(child.clone());
            }
        }
    }

    seen
}

/// FUNCTION: Join two nodes, once.
fn add(edges: &mut HashMap<SymbolId, Vec<SymbolId>>, from: SymbolId, to: SymbolId) {
    let out = edges.entry(from).or_default();

    if !out.contains(&to) {
        out.push(to);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Import;
    use crate::model::Kind;
    use crate::model::Reference;
    use crate::model::Symbol;
    use std::path::Path;
    use std::path::PathBuf;

    fn sym(file: &str, name: &str) -> Symbol {
        Symbol {
            id: SymbolId::of(Path::new(file), None, name),
            kind: Kind::Function,
            name: name.to_string(),
            file: PathBuf::from(file),
            line: 1,
            exported: false,
            owner: None,
        }
    }

    /// FUNCTION: A reference from one symbol's body to a name.
    fn re(file: &str, from: Option<&str>, name: &str) -> Reference {
        Reference {
            name: name.to_string(),
            recv: None,
            file: PathBuf::from(file),
            line: 1,
            origin: Some(match from {
                Some(owner) => SymbolId::of(Path::new(file), None, owner),
                None => SymbolId::script(Path::new(file)),
            }),
            target: None,
        }
    }

    /// FUNCTION: Resolve and walk, as a run does.
    fn reached(a: &Analysis) -> Vec<String> {
        let r = crate::resolve::all(a);
        let mut out: Vec<String> = walk(a, &r).iter().map(|id| id.to_string()).collect();
        out.sort();
        out
    }

    #[test]
    fn a_symbol_an_entry_script_calls_is_reachable() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", "Used")],
            refs: vec![re("plugin/p.vim", None, "Used")],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        assert!(reached(&a).contains(&"autoload/a.vim::Used".to_string()));
    }

    #[test]
    fn a_symbol_only_a_dead_symbol_calls_is_not_reachable() {
        let a = Analysis {
            syms: vec![
                sym("autoload/a.vim", "Dead"),
                sym("autoload/a.vim", "Deeper"),
            ],
            refs: vec![re("autoload/a.vim", Some("Dead"), "Deeper")],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        let out = reached(&a);
        assert!(!out.contains(&"autoload/a.vim::Dead".to_string()));
        assert!(!out.contains(&"autoload/a.vim::Deeper".to_string()));
    }

    #[test]
    fn a_cycle_between_two_dead_symbols_stays_unreachable() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", "One"), sym("autoload/a.vim", "Two")],
            refs: vec![
                re("autoload/a.vim", Some("One"), "Two"),
                re("autoload/a.vim", Some("Two"), "One"),
            ],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        let out = reached(&a);
        assert!(!out.contains(&"autoload/a.vim::One".to_string()));
        assert!(
            !out.contains(&"autoload/a.vim::Two".to_string()),
            "a cycle is not a root"
        );
    }

    #[test]
    fn reaching_a_symbol_reaches_its_own_files_top_level_code() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", "Used")],
            refs: vec![re("plugin/p.vim", None, "Used")],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        assert!(
            reached(&a).contains(&"autoload/a.vim::<script>".to_string()),
            "loading any symbol of a file sources the whole file"
        );
    }

    #[test]
    fn an_import_reaches_the_imported_files_top_level_code() {
        let a = Analysis {
            imports: vec![Import {
                from: PathBuf::from("plugin/p.vim"),
                to: PathBuf::from("autoload/a.vim"),
                alias: Some("a".to_string()),
                names: Vec::new(),
            }],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        assert!(
            reached(&a).contains(&"autoload/a.vim::<script>".to_string()),
            "an import sources the file whether or not a name is used"
        );
    }

    #[test]
    fn a_receiver_credits_the_class_it_names() {
        let mut class = sym("autoload/m.vim", "Menu");
        class.kind = Kind::Class;
        let mut method = sym("autoload/m.vim", "new");
        method.kind = Kind::Method;
        method.owner = Some("Menu".to_string());
        method.id = SymbolId::of(Path::new("autoload/m.vim"), Some("Menu"), "new");

        let a = Analysis {
            syms: vec![class, method],
            refs: vec![
                re("plugin/p.vim", None, "Menu"),
                Reference {
                    recv: Some("Menu".to_string()),
                    ..re("plugin/p.vim", None, "new")
                },
            ],
            roots: vec![SymbolId::script(Path::new("plugin/p.vim"))],
            ..Analysis::default()
        };

        let out = reached(&a);
        assert!(
            out.contains(&"autoload/m.vim::Menu".to_string()),
            "the receiver of Menu.new() is a use of Menu: {out:?}"
        );
        assert!(out.contains(&"autoload/m.vim::Menu.new".to_string()));
    }
}
