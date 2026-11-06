//! Resolution: which symbols a reference may name.
//!
//! Every lookup here is an index lookup. The analyzer this replaces
//! walked every symbol for every reference, which is why a project of
//! thirty thousand lines cost a hundred times what one of two thousand
//! did, and the cost grew with the square of the project rather than
//! with the project.
//!
//! License: GNU GPL 3.0

use std::collections::HashMap;
use std::path::Path;
use std::path::PathBuf;

use crate::model::Analysis;
use crate::model::Kind;
use crate::model::Reference;
use crate::model::Symbol;
use crate::model::SymbolId;

/// What every reference resolved to, and how many resolved to nothing.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Resolved {
    pub targets: HashMap<usize, Vec<SymbolId>>,
    pub unplaced: usize,
}

/// Every way a reference can be looked up, each built once.
#[derive(Debug, Default)]
pub struct Index<'a> {
    by_id: HashMap<&'a SymbolId, &'a Symbol>,
    by_name: HashMap<&'a str, Vec<&'a SymbolId>>,
    members: HashMap<&'a str, Vec<&'a SymbolId>>,
    containers: HashMap<&'a str, Vec<&'a SymbolId>>,
    /// Per file, the namespace alias of an import and the file it names.
    aliases: HashMap<&'a Path, HashMap<&'a str, &'a Path>>,
    /// Per file, a named import's local name and the file and original
    /// name it stands for.
    named: HashMap<&'a Path, HashMap<&'a str, (&'a Path, &'a str)>>,
    /// Per body, the symbols only that body can name. A local lives
    /// here and in no index keyed by name alone, which is what stops
    /// a reference elsewhere in the project from crediting it.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    scoped: HashMap<&'a SymbolId, HashMap<&'a str, &'a SymbolId>>,
    /// Per file, the scoped symbols of each name. A nested def closes
    /// over the body around it, and the inner body's id does not name
    /// the outer one, so this is the last resort for a read that no
    /// other rule placed.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    scoped_in_file: HashMap<(&'a Path, &'a str), Vec<&'a SymbolId>>,
}

impl<'a> Index<'a> {
    /// METHOD: Build every index of an analysis in one pass, so that
    /// resolution costs the same whatever the project's size.
    pub fn build(a: &'a Analysis) -> Self {
        let mut idx = Self::default();

        for sym in &a.syms {
            idx.by_id.insert(&sym.id, sym);

            // A scoped symbol enters no index keyed by name alone.
            if let Some(scope) = &sym.scope {
                idx.scoped
                    .entry(scope)
                    .or_default()
                    .insert(&sym.name, &sym.id);
                idx.scoped_in_file
                    .entry((sym.file.as_path(), &sym.name))
                    .or_default()
                    .push(&sym.id);
                continue;
            }

            idx.by_name.entry(&sym.name).or_default().push(&sym.id);

            if matches!(sym.kind, Kind::Method | Kind::Field | Kind::EnumValue) {
                idx.members.entry(&sym.name).or_default().push(&sym.id);
            }

            if matches!(sym.kind, Kind::Class | Kind::Enum | Kind::Interface) {
                idx.containers.entry(&sym.name).or_default().push(&sym.id);
            }
        }

        for imp in &a.imports {
            if let Some(alias) = &imp.alias {
                idx.aliases
                    .entry(&imp.from)
                    .or_default()
                    .insert(alias, &imp.to);
            }

            for (local, orig) in &imp.names {
                idx.named
                    .entry(&imp.from)
                    .or_default()
                    .insert(local, (&imp.to, orig));
            }
        }

        idx
    }

    /// METHOD: Every symbol a reference may name.
    ///
    /// One is a proven target. Several mean the name is ambiguous, and
    /// then every candidate counts as used, because the analyzer
    /// reports only what it can prove is unreferenced. None means the
    /// reference named nothing this project declares.
    pub fn candidates(&self, r: &Reference) -> Vec<SymbolId> {
        if let Some(id) = &r.target {
            if self.by_id.contains_key(id) {
                return vec![id.clone()];
            }
        }

        if let Some(recv) = &r.recv {
            return self.dotted(r, recv);
        }

        // A variable of the body making the reference wins over
        // everything, because nothing else can be meant: Vim9 resolves
        // a bare name to the innermost declaration of it.
        if let Some(id) = self.in_scope(r) {
            return vec![id];
        }

        // A function of the same file needs no import and wins over
        // every name that matches elsewhere.
        let here = SymbolId::of(&r.file, None, &r.name);
        if self.by_id.contains_key(&here) {
            return vec![here];
        }

        if let Some(id) = self.autoload(&r.name) {
            return vec![id];
        }

        if let Some(id) = self.named_import(r) {
            return vec![id];
        }

        let by_name = self.cloned(self.by_name.get(r.name.as_str()));
        if !by_name.is_empty() {
            return by_name;
        }

        self.captured(r).into_iter().collect()
    }

    /// METHOD: The variable a nested def closed over, where nothing
    /// else placed the read.
    ///
    /// Vim9 lets a def inside a def read the enclosing body's
    /// variables, and the inner body's id does not name the outer
    /// one, so the scoped lookup cannot walk outwards. Where the file
    /// declares exactly one variable of the name, that is the one
    /// meant. Where it declares several this answers nothing, so a
    /// name two bodies share is left unplaced rather than credited to
    /// a guess.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    fn captured(&self, r: &Reference) -> Option<SymbolId> {
        let ids = self
            .scoped_in_file
            .get(&(r.file.as_path(), r.name.as_str()))?;
        let [one] = ids.as_slice() else {
            return None;
        };

        Some((*one).clone())
    }

    /// METHOD: Resolve `recv.name`, where `recv` is already the type
    /// of the receiver rather than the text that named it.
    fn dotted(&self, r: &Reference, recv: &str) -> Vec<SymbolId> {
        // A container declared in this same file.
        let here = SymbolId::of(&r.file, Some(recv), &r.name);
        if self.by_id.contains_key(&here) {
            return vec![here];
        }

        // An import's namespace alias: `import autoload 'u.vim' as u`
        // makes `u.Foo()` a call into that file.
        if let Some(to) = self.aliases.get(r.file.as_path()).and_then(|a| a.get(recv)) {
            let id = SymbolId::of(to, None, &r.name);
            if self.by_id.contains_key(&id) {
                return vec![id];
            }
        }

        // A container of that name elsewhere, where exactly one file
        // declares it. `M.Menu.new()` names Menu without naming its
        // file, so the class is found by name and the member on it.
        if let Some(file) = self.unique_container(recv) {
            let id = SymbolId::of(file, Some(recv), &r.name);
            if self.by_id.contains_key(&id) {
                return vec![id];
            }

            // A class with no `new` has the default constructor, which
            // is no symbol and so has nothing to credit. Without this
            // the call would fall through and credit every other
            // class's constructor.
            if r.name == "new" {
                return Vec::new();
            }
        }

        // The receiver's type is unknown, so any member of that name
        // may be the target, and every one of them counts as used.
        self.cloned(self.members.get(r.name.as_str()))
    }

    /// METHOD: Whether a reference names something the analyzer itself
    /// recorded, which credits no symbol and is no unplaced name.
    ///
    /// An import's namespace alias is the case. `import 'c.vim' as CO`
    /// registers the alias, and `CO.ROLE` is resolved through it, but
    /// the parser emits a reference for the `CO` token as well, which
    /// nothing declares. Counting it is counting the analyzer's own
    /// data twice.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    fn knows(&self, r: &Reference) -> bool {
        r.recv.is_none()
            && self
                .aliases
                .get(r.file.as_path())
                .is_some_and(|a| a.contains_key(r.name.as_str()))
    }

    /// METHOD: The variable of the body that made this reference, by
    /// that name, where the body declares one.
    fn in_scope(&self, r: &Reference) -> Option<SymbolId> {
        let origin = r.origin.as_ref()?;

        self.scoped
            .get(origin)?
            .get(r.name.as_str())
            .map(|id| (*id).clone())
    }

    /// METHOD: The symbol a classic autoload name states, as
    /// `foo#bar#Func` states `autoload/foo/bar.vim::Func`.
    fn autoload(&self, name: &str) -> Option<SymbolId> {
        let (prefix, func) = name.rsplit_once('#')?;
        let path = PathBuf::from("autoload").join(format!("{}.vim", prefix.replace('#', "/")));
        let id = SymbolId::of(&path, None, func);

        self.by_id.contains_key(&id).then_some(id)
    }

    /// METHOD: The symbol a named import binds, under the name this
    /// file calls it by.
    fn named_import(&self, r: &Reference) -> Option<SymbolId> {
        let (to, orig) = self.named.get(r.file.as_path())?.get(r.name.as_str())?;
        let id = SymbolId::of(to, None, orig);

        self.by_id.contains_key(&id).then_some(id)
    }

    /// METHOD: The one file declaring a container of this name, or
    /// none when none or several do.
    fn unique_container(&self, name: &str) -> Option<&Path> {
        let ids = self.containers.get(name)?;
        let [id] = ids.as_slice() else {
            return None;
        };

        Some(self.by_id.get(*id)?.file.as_path())
    }

    fn cloned(&self, ids: Option<&Vec<&'a SymbolId>>) -> Vec<SymbolId> {
        ids.map(|ids| ids.iter().map(|id| (*id).clone()).collect())
            .unwrap_or_default()
    }
}

/// FUNCTION: Resolve every reference of an analysis.
pub fn all(a: &Analysis) -> Resolved {
    let idx = Index::build(a);
    let mut out = Resolved::default();

    for (i, r) in a.refs.iter().enumerate() {
        let ids = idx.candidates(r);

        if ids.is_empty() {
            // A name the language owns, and a name the analyzer
            // recorded itself, are both names it placed: neither is a
            // gap, and neither credits a symbol.
            if !r.owned && !idx.knows(r) {
                out.unplaced += 1;
            }

            continue;
        }

        out.targets.insert(i, ids);
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Import;

    /// FUNCTION: A symbol, for a test that cares about one of its
    /// fields and not the rest.
    fn sym(file: &str, owner: Option<&str>, name: &str, kind: Kind) -> Symbol {
        Symbol {
            id: SymbolId::of(Path::new(file), owner, name),
            kind,
            name: name.to_string(),
            file: PathBuf::from(file),
            line: 1,
            exported: false,
            owner: owner.map(str::to_string),
            scope: None,
        }
    }

    /// FUNCTION: A variable of a function body, scoped to that body.
    fn local_sym(file: &str, body: &str, name: &str) -> Symbol {
        let scope = SymbolId::of(Path::new(file), None, body);

        Symbol {
            id: SymbolId::in_scope(&scope, name),
            kind: Kind::Variable,
            name: name.to_string(),
            file: PathBuf::from(file),
            line: 1,
            exported: false,
            owner: None,
            scope: Some(scope),
        }
    }

    /// FUNCTION: A reference made from inside a named function body.
    fn re_in(file: &str, body: &str, name: &str) -> Reference {
        Reference {
            origin: Some(SymbolId::of(Path::new(file), None, body)),
            ..re(file, None, name)
        }
    }

    /// FUNCTION: A reference from a file, with an optional receiver.
    fn re(file: &str, recv: Option<&str>, name: &str) -> Reference {
        Reference {
            name: name.to_string(),
            recv: recv.map(str::to_string),
            file: PathBuf::from(file),
            line: 1,
            origin: Some(SymbolId::script(Path::new(file))),
            target: None,
            owned: false,
        }
    }

    fn ids(a: &Analysis, r: &Reference) -> Vec<String> {
        let idx = Index::build(a);
        let mut out: Vec<String> = idx.candidates(r).iter().map(|i| i.to_string()).collect();
        out.sort();
        out
    }

    /// A variable of a body is a symbol only that body can name, and
    /// the read inside it is the credit that keeps it off the report.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_scoped_symbol_is_reached_only_from_its_own_scope() {
        let a = Analysis {
            syms: vec![local_sym("autoload/a.vim", "F", "row")],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re_in("autoload/a.vim", "F", "row")),
            vec!["autoload/a.vim::F.row"]
        );
    }

    /// Two bodies of one file declaring the name means the read
    /// cannot be placed on either: a nested def closes over one body
    /// only, and which one is not knowable from the id.
    #[test]
    fn a_scoped_symbol_is_invisible_from_another_scope() {
        let a = Analysis {
            syms: vec![
                local_sym("autoload/a.vim", "F", "row"),
                local_sym("autoload/a.vim", "G", "row"),
            ],
            ..Analysis::default()
        };

        assert!(ids(&a, &re_in("autoload/a.vim", "H", "row")).is_empty());
    }

    /// A def inside a def reads the enclosing body's variables, and
    /// the inner body's id does not name the outer one. Where the
    /// file declares one variable of the name, that is the one meant.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_variable_a_nested_def_closed_over_is_still_reached() {
        let a = Analysis {
            syms: vec![local_sym("autoload/a.vim", "Outer", "bufs")],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re_in("autoload/a.vim", "Walk", "bufs")),
            vec!["autoload/a.vim::Outer.bufs"]
        );
    }

    /// The fallback is the last resort, so a name the file also
    /// declares at script level still reaches the script variable.
    #[test]
    fn a_script_variable_still_wins_over_a_variable_of_some_body() {
        let a = Analysis {
            syms: vec![
                local_sym("autoload/a.vim", "F", "row"),
                sym("autoload/a.vim", None, "row", Kind::Variable),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re_in("autoload/a.vim", "G", "row")),
            vec!["autoload/a.vim::row"]
        );
    }

    #[test]
    fn a_scoped_symbol_is_invisible_to_a_bare_name_elsewhere() {
        let a = Analysis {
            syms: vec![local_sym("autoload/a.vim", "F", "row")],
            ..Analysis::default()
        };

        assert!(ids(&a, &re("plugin/p.vim", None, "row")).is_empty());
    }

    /// The anti-goal of the design, as a test: a body's own variable
    /// must take nothing from a script variable of the same name.
    #[test]
    fn a_scoped_symbol_does_not_shadow_a_script_variable_of_its_name() {
        let a = Analysis {
            syms: vec![
                local_sym("autoload/a.vim", "F", "row"),
                sym("autoload/a.vim", None, "row", Kind::Variable),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("autoload/a.vim", None, "row")),
            vec!["autoload/a.vim::row"]
        );
    }

    #[test]
    fn a_unique_name_resolves_to_one_symbol() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "Helper", Kind::Function)],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "Helper")),
            vec!["autoload/a.vim::Helper"]
        );
    }

    #[test]
    fn a_name_in_the_same_file_wins_over_one_elsewhere() {
        let a = Analysis {
            syms: vec![
                sym("autoload/a.vim", None, "Helper", Kind::Function),
                sym("plugin/p.vim", None, "Helper", Kind::Function),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "Helper")),
            vec!["plugin/p.vim::Helper"]
        );
    }

    #[test]
    fn an_ambiguous_name_resolves_to_every_candidate() {
        let a = Analysis {
            syms: vec![
                sym("autoload/a.vim", None, "Helper", Kind::Function),
                sym("autoload/b.vim", None, "Helper", Kind::Function),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "Helper")),
            vec!["autoload/a.vim::Helper", "autoload/b.vim::Helper"],
            "what cannot be told apart cannot be reported"
        );
    }

    #[test]
    fn a_typed_receiver_resolves_to_its_class_member_alone() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", Some("Menu"), "Open", Kind::Method),
                sym("autoload/p.vim", Some("Popup"), "Open", Kind::Method),
                sym("autoload/m.vim", None, "Menu", Kind::Class),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", Some("Menu"), "Open")),
            vec!["autoload/m.vim::Menu.Open"]
        );
    }

    #[test]
    fn an_untyped_receiver_resolves_to_every_member_of_the_name() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", Some("Menu"), "Close", Kind::Method),
                sym("autoload/p.vim", Some("Popup"), "Close", Kind::Method),
                sym("autoload/o.vim", None, "Close", Kind::Function),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "Close")),
            vec![
                "autoload/m.vim::Menu.Close",
                "autoload/o.vim::Close",
                "autoload/p.vim::Popup.Close"
            ],
            "with no receiver the plain name matches everything"
        );
    }

    #[test]
    fn a_class_qualified_call_credits_only_its_own_member() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", None, "Menu", Kind::Class),
                sym("autoload/m.vim", Some("Menu"), "new", Kind::Method),
                sym("autoload/o.vim", None, "Other", Kind::Class),
                sym("autoload/o.vim", Some("Other"), "new", Kind::Method),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", Some("Menu"), "new")),
            vec!["autoload/m.vim::Menu.new"]
        );
    }

    #[test]
    fn a_default_constructor_credits_nothing() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", None, "Menu", Kind::Class),
                sym("autoload/o.vim", None, "Other", Kind::Class),
                sym("autoload/o.vim", Some("Other"), "new", Kind::Method),
            ],
            ..Analysis::default()
        };

        assert!(
            ids(&a, &re("plugin/p.vim", Some("Menu"), "new")).is_empty(),
            "Menu has no new of its own, and must not credit another class's"
        );
    }

    #[test]
    fn a_namespace_alias_resolves_into_the_file_it_names() {
        let a = Analysis {
            syms: vec![sym("autoload/util.vim", None, "Trim", Kind::Function)],
            imports: vec![Import {
                from: PathBuf::from("plugin/p.vim"),
                to: PathBuf::from("autoload/util.vim"),
                alias: Some("util".to_string()),
                names: Vec::new(),
            }],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", Some("util"), "Trim")),
            vec!["autoload/util.vim::Trim"]
        );
    }

    /// FUNCTION: One alias and the member reached through it, which
    /// is what the parser emits for `util.Trim()`: a reference for
    /// each token.
    fn aliased(from: &str, alias: &str, to: &str, member: &str) -> Analysis {
        Analysis {
            syms: vec![sym(to, None, member, Kind::Function)],
            imports: vec![Import {
                from: PathBuf::from(from),
                to: PathBuf::from(to),
                alias: Some(alias.to_string()),
                names: Vec::new(),
            }],
            refs: vec![re(from, None, alias), re(from, Some(alias), member)],
            ..Analysis::default()
        }
    }

    /// An alias is a name the analyzer registered itself, and
    /// resolution reaches a member through it. Counting the alias
    /// token as a name that could not be placed counts the analyzer's
    /// own data twice.
    #[test]
    fn an_import_alias_is_not_an_unplaced_name() {
        let out = all(&aliased(
            "plugin/p.vim",
            "util",
            "autoload/util.vim",
            "Trim",
        ));
        let member: Vec<String> = out.targets[&1].iter().map(SymbolId::to_string).collect();

        assert_eq!(out.unplaced, 0);
        assert_eq!(member, vec!["autoload/util.vim::Trim"]);
        assert!(
            !out.targets.contains_key(&0),
            "the alias token credits nothing"
        );
    }

    /// The mark is read after resolution, never before it. A project
    /// symbol whose name the language also owns, as a variable called
    /// `string` is, keeps the credit of every use.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_name_the_language_owns_still_credits_a_symbol_of_that_name() {
        let a = Analysis {
            syms: vec![sym("plugin/p.vim", None, "string", Kind::Variable)],
            refs: vec![Reference {
                owned: true,
                ..re("plugin/p.vim", None, "string")
            }],
            ..Analysis::default()
        };

        let out = all(&a);

        assert_eq!(out.unplaced, 0);
        assert_eq!(
            out.targets[&0]
                .iter()
                .map(SymbolId::to_string)
                .collect::<Vec<String>>(),
            vec!["plugin/p.vim::string"]
        );
    }

    /// A name the language owns that nothing declares is placed, and
    /// raises no count.
    #[test]
    fn a_name_the_language_owns_is_not_an_unplaced_name() {
        let a = Analysis {
            refs: vec![Reference {
                owned: true,
                ..re("plugin/p.vim", None, "string")
            }],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    /// An alias belongs to the file that imported it. The same word in
    /// another file is a name like any other.
    #[test]
    fn an_alias_of_another_file_is_still_an_unplaced_name() {
        // The same import and symbol, with the alias read from a file
        // that did not write the import.
        let mut a = aliased("plugin/p.vim", "util", "autoload/util.vim", "Trim");
        a.refs = vec![re("plugin/q.vim", None, "util")];

        assert_eq!(all(&a).unplaced, 1);
    }

    #[test]
    fn a_named_import_resolves_under_the_name_it_was_given() {
        let a = Analysis {
            syms: vec![sym("autoload/mod.vim", None, "Real", Kind::Function)],
            imports: vec![Import {
                from: PathBuf::from("plugin/p.vim"),
                to: PathBuf::from("autoload/mod.vim"),
                alias: None,
                names: vec![("Alias".to_string(), "Real".to_string())],
            }],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "Alias")),
            vec!["autoload/mod.vim::Real"]
        );
    }

    #[test]
    fn the_classic_autoload_convention_resolves_by_its_path() {
        let a = Analysis {
            syms: vec![sym("autoload/foo/bar.vim", None, "Init", Kind::Function)],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &re("plugin/p.vim", None, "foo#bar#Init")),
            vec!["autoload/foo/bar.vim::Init"]
        );
    }

    #[test]
    fn an_unmatched_reference_raises_the_unplaced_count() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "Helper", Kind::Function)],
            refs: vec![re("plugin/p.vim", None, "Missing")],
            ..Analysis::default()
        };

        let out = all(&a);
        assert_eq!(out.unplaced, 1);
        assert!(out.targets.is_empty());
    }

    #[test]
    fn resolving_a_large_project_stays_linear() {
        // Twenty thousand references against twenty thousand symbols.
        // Walking every symbol for every reference would be four
        // hundred million comparisons, which no bound below would
        // survive; an index lookup is instant.
        let n = 20_000;
        let mut a = Analysis::default();

        for i in 0..n {
            let file = format!("autoload/f{i}.vim");
            a.syms
                .push(sym(&file, None, &format!("F{i}"), Kind::Function));
            a.refs.push(re("plugin/p.vim", None, &format!("F{i}")));
        }

        let start = std::time::Instant::now();
        let out = all(&a);
        let spent = start.elapsed();

        assert_eq!(out.targets.len(), n);
        assert_eq!(out.unplaced, 0);
        assert!(
            spent < std::time::Duration::from_secs(2),
            "resolution took {spent:?}, which is not an index lookup"
        );
    }
}
