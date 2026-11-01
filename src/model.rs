//! The model: what a scan found, in terms no language defines.
//!
//! License: GNU GPL 3.0

use std::collections::HashMap;
use std::fmt;
use std::path::Path;
use std::path::PathBuf;

/// What a symbol is. The text of each one is a contract: it is the word
/// the quickfix line carries, which CI and every front end read.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    Function,
    Method,
    Class,
    Interface,
    Enum,
    EnumValue,
    Field,
    Variable,
}

impl fmt::Display for Kind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let word = match self {
            Self::Function => "function",
            Self::Method => "method",
            Self::Class => "class",
            Self::Interface => "interface",
            Self::Enum => "enum",
            Self::EnumValue => "enum_value",
            Self::Field => "field",
            Self::Variable => "variable",
        };
        f.write_str(word)
    }
}

/// Which class of finding a symbol is reported as. Only `Ghost` is
/// always on; the other two wait behind their flags. The text is a
/// contract too: CI counts the lines that carry `[ghost]`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Class {
    Ghost,
    WriteOnly,
    Local,
}

impl fmt::Display for Class {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let word = match self {
            Self::Ghost => "ghost",
            Self::WriteOnly => "write-only",
            Self::Local => "local",
        };
        f.write_str(word)
    }
}

/// A symbol's identity: its file, its owner, and its name. Two symbols
/// of one name in two files are two symbols, and so are the methods of
/// two classes in one file.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SymbolId(String);

impl SymbolId {
    /// METHOD: The id of a declaration. `owner` is the name of the
    /// class, enum or interface that holds it, where one does.
    pub fn of(file: &Path, owner: Option<&str>, name: &str) -> Self {
        match owner {
            Some(owner) => Self(format!("{}::{owner}.{name}", file.display())),
            None => Self(format!("{}::{name}", file.display())),
        }
    }

    /// METHOD: The id standing for "this file's top-level code ran".
    /// Angle brackets never appear in an identifier, so it cannot
    /// collide with a declaration's id.
    pub fn script(file: &Path) -> Self {
        Self(format!("{}::<script>", file.display()))
    }
}

impl fmt::Display for SymbolId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Symbol {
    pub id: SymbolId,
    pub kind: Kind,
    pub name: String,
    pub file: PathBuf,
    pub line: u32,
    pub exported: bool,
    /// The name of the class, enum or interface that holds it. A name
    /// rather than an id, because a class-qualified call such as
    /// `M.Menu.new()` names a class without naming its file.
    pub owner: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reference {
    pub name: String,
    /// The receiver of a dotted call, where its type is known.
    pub recv: Option<String>,
    pub file: PathBuf,
    pub line: u32,
    /// The symbol whose body holds this reference, or none for a
    /// reference in a file's top-level code.
    pub origin: Option<SymbolId>,
    /// Set where the scan already knows the exact target, as a call
    /// through a variable of a declared type does. It bypasses every
    /// heuristic in resolution.
    pub target: Option<SymbolId>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Import {
    pub from: PathBuf,
    pub to: PathBuf,
    /// The alias of `import ... as NAME`, where one is given.
    pub alias: Option<String>,
    /// The names of `import {A, B} from ...`, where any are given.
    pub names: Vec<String>,
}

/// TRAIT: What a language's scan writes its findings into, so that a
/// language need not know how they are stored.
pub trait Sink {
    fn sym(&mut self, s: Symbol);
    fn re(&mut self, r: Reference);
    fn import(&mut self, i: Import);
    fn root(&mut self, id: SymbolId);
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Analysis {
    pub syms: Vec<Symbol>,
    pub refs: Vec<Reference>,
    pub roots: Vec<SymbolId>,
    pub imports: Vec<Import>,
}

impl Analysis {
    /// METHOD: Every symbol by its id, for the stages that look one up
    /// rather than walk them all.
    pub fn by_id(&self) -> HashMap<&SymbolId, &Symbol> {
        self.syms.iter().map(|s| (&s.id, s)).collect()
    }
}

impl Sink for Analysis {
    fn sym(&mut self, s: Symbol) {
        self.syms.push(s);
    }

    fn re(&mut self, r: Reference) {
        self.refs.push(r);
    }

    fn import(&mut self, i: Import) {
        self.imports.push(i);
    }

    fn root(&mut self, id: SymbolId) {
        self.roots.push(id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kind_display_matches_the_quickfix_words() {
        let words: Vec<String> = [
            Kind::Function,
            Kind::Method,
            Kind::Class,
            Kind::Interface,
            Kind::Enum,
            Kind::EnumValue,
            Kind::Field,
            Kind::Variable,
        ]
        .iter()
        .map(|k| k.to_string())
        .collect();

        assert_eq!(
            words,
            vec![
                "function",
                "method",
                "class",
                "interface",
                "enum",
                "enum_value",
                "field",
                "variable",
            ]
        );
    }

    #[test]
    fn symbol_ids_differ_for_the_same_name_in_two_files() {
        let a = SymbolId::of(Path::new("autoload/a.vim"), None, "Run");
        let b = SymbolId::of(Path::new("autoload/b.vim"), None, "Run");

        assert_ne!(a, b);
    }

    #[test]
    fn symbol_ids_differ_for_a_method_of_two_classes() {
        let file = Path::new("autoload/a.vim");
        let a = SymbolId::of(file, Some("Menu"), "new");
        let b = SymbolId::of(file, Some("Popup"), "new");

        assert_ne!(a, b);
    }

    #[test]
    fn a_script_id_cannot_collide_with_a_symbol() {
        let file = Path::new("plugin/p.vim");

        assert_ne!(SymbolId::script(file), SymbolId::of(file, None, "script"));
    }
}
