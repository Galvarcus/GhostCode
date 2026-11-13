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
use std::collections::HashSet;
use std::path::Path;
use std::path::PathBuf;

use crate::lang;
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
    /// Every file that declares a symbol, which is how an autoload
    /// name is told from one of another plugin.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    files: HashSet<&'a Path>,
    /// Per file, the names an import binds to a file the scan does
    /// not hold: its alias, and each name it imports.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    outside: HashMap<&'a Path, HashSet<&'a str>>,
}

impl<'a> Index<'a> {
    /// METHOD: Build every index of an analysis in one pass, so that
    /// resolution costs the same whatever the project's size.
    pub fn build(a: &'a Analysis) -> Self {
        let mut idx = Self::default();

        for sym in &a.syms {
            idx.by_id.insert(&sym.id, sym);
            idx.files.insert(sym.file.as_path());

            // A scoped symbol enters no index keyed by name alone.
            if let Some(scope) = &sym.scope {
                idx.scoped
                    .entry(scope)
                    .or_default()
                    .insert(&sym.name, &sym.id);
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

        for imp in &a.outside {
            let names = idx.outside.entry(&imp.from).or_default();

            names.extend(imp.alias.as_deref());
            names.extend(imp.names.iter().map(|(local, _)| local.as_str()));
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

        // A name behind a dot whose receiver has no type is a member
        // of some class or a key of a dictionary. It is never a bare
        // name, so it credits no variable, no function and no import
        // of that spelling. The class is unknown, so every member of
        // the name still counts as used.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/53
        if r.member {
            return self.cloned(self.members.get(r.name.as_str()));
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

        if let Some(id) = self.stated(r) {
            return vec![id];
        }

        if let Some(id) = self.named_import(r) {
            return vec![id];
        }

        self.cloned(self.by_name.get(r.name.as_str()))
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

        // The alias of an import the scan does not hold is a namespace
        // of another plugin, so the name behind it is no member of a
        // class of the project.
        // REFERENCE: https://github.com/Galvarcus/GhostCode/issues/59
        if self.bound_outside(&r.file, recv) {
            return Vec::new();
        }

        // The receiver's type is unknown, so any member of that name
        // may be the target, and every one of them counts as used.
        self.cloned(self.members.get(r.name.as_str()))
    }

    /// METHOD: Whether an import of a file the scan does not hold
    /// binds this name in this file.
    fn bound_outside(&self, file: &Path, name: &str) -> bool {
        self.outside.get(file).is_some_and(|o| o.contains(name))
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
    ///
    /// A name an import binds to a file the scan does not hold is the
    /// same case. The plugin it names is outside the root, so no
    /// symbol can take the credit, and the importing file did declare
    /// the name.
    fn knows(&self, r: &Reference) -> bool {
        let file = r.file.as_path();
        let name = r.name.as_str();

        r.recv.is_none()
            && (self.aliases.get(file).is_some_and(|a| a.contains_key(name))
                || self.bound_outside(file, name))
    }

    /// METHOD: Whether a reference stood behind a dot of a receiver
    /// the project does not declare, which is no unplaced name.
    ///
    /// The receiver has no type, or names no class and no import of
    /// the project. The name is then a key of a dictionary or a member
    /// of a class outside the project, and no rule could place it.
    /// Where the project does declare the receiver, a member it lacks
    /// may be one the scan missed, so that one stays counted.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    fn keyed(&self, r: &Reference) -> bool {
        let declared = r.recv.as_deref().is_some_and(|recv| {
            self.containers.contains_key(recv)
                || self
                    .aliases
                    .get(r.file.as_path())
                    .is_some_and(|a| a.contains_key(recv))
        });

        r.member && !declared
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

    /// METHOD: The symbol a name states by its spelling alone, where
    /// the language of the file has such names. The rule belongs to
    /// the language, as the autoload names of Vim do.
    fn stated(&self, r: &Reference) -> Option<SymbolId> {
        let (path, func) = stated_parts(r)?;
        let id = SymbolId::of(&path, None, func);

        self.by_id.contains_key(&id).then_some(id)
    }

    /// METHOD: Whether a reference is a name that states a file the
    /// project declares nothing in, which is no unplaced name.
    ///
    /// The name states its file. A file with no symbol of the project
    /// is another plugin's, or a legacy script the scan does not read,
    /// and no rule could place the function. Where the project does
    /// declare symbols in the file, a function it lacks may be one
    /// the scan missed, so that one stays counted.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    fn foreign(&self, r: &Reference) -> bool {
        r.recv.is_none()
            && stated_parts(r).is_some_and(|(path, _)| !self.files.contains(path.as_path()))
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

/// FUNCTION: The file and the symbol the name of a reference states,
/// asked of the language of the file that makes the reference.
fn stated_parts(r: &Reference) -> Option<(PathBuf, &str)> {
    lang::for_path(&r.file)?.stated(&r.name)
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
            // gap, and neither credits a symbol. A key behind a dot is
            // no name the project could declare, and neither is an
            // autoload function of a file the project does not hold.
            if !r.owned && !idx.knows(r) && !idx.keyed(r) && !idx.foreign(r) {
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
            lead: false,
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
            lead: false,
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
            member: false,
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

    /// A body sees its own variables and no other body's, which is
    /// what Vim9 compiles. A def nested inside a body does read that
    /// body's variables, and the inner body's id does not name the
    /// outer one, so the scan states the variable as the target of
    /// such a read. A read with no target is left unplaced rather
    /// than credited to a guess: `unplaced_names_by_file` then keeps
    /// the variable off the report.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_scoped_symbol_is_invisible_from_another_scope() {
        let a = Analysis {
            syms: vec![local_sym("autoload/a.vim", "F", "row")],
            ..Analysis::default()
        };

        assert!(ids(&a, &re_in("autoload/a.vim", "G", "row")).is_empty());
    }

    /// A name the file also declares at script level is reached by
    /// the same-file rule, as it was before scopes existed.
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

    /// FUNCTION: A reference that stood behind a dot.
    fn member(file: &str, recv: Option<&str>, name: &str) -> Reference {
        Reference {
            member: true,
            ..re(file, recv, name)
        }
    }

    /// A name behind a dot that no class declares is a key of a
    /// dictionary or a member of a class outside the project. Neither
    /// is a symbol the analyzer failed to find.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_member_of_a_receiver_with_no_type_is_not_an_unplaced_name() {
        let a = Analysis {
            refs: vec![member("plugin/p.vim", None, "root")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    #[test]
    fn a_member_of_a_receiver_the_project_does_not_declare_is_not_an_unplaced_name() {
        let a = Analysis {
            refs: vec![member("plugin/p.vim", Some("LM"), "History")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    /// Where the project declares the receiver, a member it lacks may
    /// be one the scan missed, so the count keeps it.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn a_member_missing_from_a_class_of_the_project_is_an_unplaced_name() {
        let a = Analysis {
            syms: vec![sym("autoload/m.vim", None, "Menu", Kind::Class)],
            refs: vec![member("plugin/p.vim", Some("Menu"), "Missing")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 1);
    }

    #[test]
    fn a_member_missing_behind_an_alias_of_the_project_is_an_unplaced_name() {
        let mut a = aliased("plugin/p.vim", "util", "autoload/util.vim", "Trim");
        a.refs = vec![member("plugin/p.vim", Some("util"), "Missing")];

        assert_eq!(all(&a).unplaced, 1);
    }

    #[test]
    fn a_bare_name_nothing_declares_is_an_unplaced_name() {
        let a = Analysis {
            refs: vec![re("plugin/p.vim", None, "root")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 1);
    }

    /// The field changes the count and no credit: a member of a
    /// receiver with no type still reaches every member of the name.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/53
    #[test]
    fn a_member_of_a_receiver_with_no_type_still_credits_every_member_of_the_name() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", Some("Menu"), "Open", Kind::Method),
                sym("autoload/p.vim", Some("Popup"), "Open", Kind::Method),
            ],
            ..Analysis::default()
        };

        assert_eq!(ids(&a, &member("plugin/p.vim", None, "Open")).len(), 2);
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

    /// An autoload name states its file. Where the project holds no
    /// symbol of that file, the function is another plugin's, and no
    /// rule could place it.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn an_autoload_function_of_a_file_outside_the_project_is_not_an_unplaced_name() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "Helper", Kind::Function)],
            refs: vec![re("autoload/a.vim", None, "other#plugin#Enable")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    /// Where the project does hold the file, a function it lacks may
    /// be one the scan missed, so that one stays counted.
    #[test]
    fn an_autoload_function_missing_from_a_file_of_the_project_is_an_unplaced_name() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "Helper", Kind::Function)],
            refs: vec![re("plugin/p.vim", None, "a#Missing")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 1);
    }

    /// FUNCTION: An import of a file the scan does not hold.
    fn outside(from: &str, alias: Option<&str>, names: &[(&str, &str)]) -> Import {
        Import {
            from: PathBuf::from(from),
            to: PathBuf::from("import/Other/lib.vim"),
            alias: alias.map(str::to_string),
            names: names
                .iter()
                .map(|(local, orig)| (local.to_string(), orig.to_string()))
                .collect(),
        }
    }

    /// An import of a file outside the root of the scan names a
    /// plugin the scan does not hold. Its alias is a name the file
    /// declares all the same, and no rule could place it.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    #[test]
    fn the_alias_of_an_import_outside_the_scan_is_not_an_unplaced_name() {
        let a = Analysis {
            outside: vec![outside("tests/t.vim", Some("LM"), &[])],
            refs: vec![re("tests/t.vim", None, "LM")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    #[test]
    fn a_name_imported_from_outside_the_scan_is_not_an_unplaced_name() {
        let a = Analysis {
            outside: vec![outside("tests/t.vim", None, &[("Log", "Logger")])],
            refs: vec![re("tests/t.vim", None, "Log")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 0);
    }

    /// The import binds the alias in its own file and in no other.
    #[test]
    fn the_alias_of_an_import_outside_the_scan_is_unplaced_in_another_file() {
        let a = Analysis {
            outside: vec![outside("tests/t.vim", Some("LM"), &[])],
            refs: vec![re("plugin/p.vim", None, "LM")],
            ..Analysis::default()
        };

        assert_eq!(all(&a).unplaced, 1);
    }

    /// FUNCTION: A reference behind a dot whose receiver has no type.
    fn key(file: &str, body: &str, name: &str) -> Reference {
        Reference {
            member: true,
            ..re_in(file, body, name)
        }
    }

    /// A name behind a dot is a member or a key. A variable of the
    /// body is never read through a dot, so a key of that spelling
    /// gives it no credit.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/53
    #[test]
    fn a_name_behind_a_dot_does_not_credit_a_variable_of_the_body() {
        let a = Analysis {
            syms: vec![local_sym("autoload/a.vim", "F", "root")],
            ..Analysis::default()
        };

        assert!(ids(&a, &key("autoload/a.vim", "F", "root")).is_empty());
    }

    #[test]
    fn a_name_behind_a_dot_does_not_credit_a_function_of_the_file() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "Helper", Kind::Function)],
            ..Analysis::default()
        };

        assert!(ids(&a, &key("autoload/a.vim", "F", "Helper")).is_empty());
    }

    #[test]
    fn a_name_behind_a_dot_does_not_credit_a_script_variable() {
        let a = Analysis {
            syms: vec![sym("autoload/a.vim", None, "count", Kind::Variable)],
            ..Analysis::default()
        };

        assert!(ids(&a, &key("autoload/a.vim", "F", "count")).is_empty());
    }

    /// The type of the receiver is unknown, so every class member of
    /// the name still takes the credit.
    #[test]
    fn a_name_behind_a_dot_still_credits_every_member_of_the_name() {
        let a = Analysis {
            syms: vec![
                sym("autoload/m.vim", Some("Menu"), "Open", Kind::Method),
                sym("autoload/p.vim", Some("Popup"), "Open", Kind::Method),
                sym("autoload/a.vim", None, "Open", Kind::Function),
            ],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &key("autoload/a.vim", "F", "Open")),
            vec!["autoload/m.vim::Menu.Open", "autoload/p.vim::Popup.Open"]
        );
    }

    /// The alias of an import the scan does not hold is a namespace
    /// of another plugin, so a call through it names no member of a
    /// class of the project.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/59
    #[test]
    fn a_call_through_the_alias_of_an_import_outside_the_scan_credits_nothing() {
        let a = Analysis {
            syms: vec![sym("autoload/m.vim", Some("Menu"), "Open", Kind::Method)],
            outside: vec![outside("autoload/a.vim", Some("DV"), &[])],
            ..Analysis::default()
        };

        assert!(ids(&a, &member("autoload/a.vim", Some("DV"), "Open")).is_empty());
    }

    /// The import binds the alias in its own file alone, so the same
    /// receiver in another file still has no type.
    #[test]
    fn a_receiver_spelled_as_an_outside_alias_of_another_file_keeps_the_credit() {
        let a = Analysis {
            syms: vec![sym("autoload/m.vim", Some("Menu"), "Open", Kind::Method)],
            outside: vec![outside("autoload/a.vim", Some("DV"), &[])],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &member("autoload/b.vim", Some("DV"), "Open")),
            vec!["autoload/m.vim::Menu.Open"]
        );
    }

    /// A class of the file wins over an import alias of its spelling.
    #[test]
    fn a_class_of_the_file_spelled_as_an_outside_alias_keeps_its_member() {
        let a = Analysis {
            syms: vec![
                sym("autoload/a.vim", None, "DV", Kind::Class),
                sym("autoload/a.vim", Some("DV"), "Open", Kind::Method),
            ],
            outside: vec![outside("autoload/a.vim", Some("DV"), &[])],
            ..Analysis::default()
        };

        assert_eq!(
            ids(&a, &member("autoload/a.vim", Some("DV"), "Open")),
            vec!["autoload/a.vim::DV.Open"]
        );
    }
}
