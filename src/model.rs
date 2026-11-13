//! The model: what a scan found, in terms no language defines.
//!
//! License: GNU GPL 3.0

use serde::Serialize;
use std::collections::HashMap;
use std::fmt;
use std::path::Component;
use std::path::Path;
use std::path::PathBuf;

// What opens the id of a symbol that belongs to no file.
const SHARED: &str = "<shared>::";

/// What a symbol is. The text of each one is a contract: it is the word
/// the quickfix line carries, which CI and every front end read.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "kebab-case")]
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
        let file = Self::text(file);

        match owner {
            Some(owner) => Self(format!("{file}::{owner}.{name}")),
            None => Self(format!("{file}::{name}")),
        }
    }

    /// METHOD: The id of a name inside another symbol's body, as a
    /// local variable of `F` is. A dot joins it to the body's own id,
    /// exactly as a member is joined to its container, so a local of
    /// a method nests without a second spelling.
    ///
    /// A class and a function cannot share a name in one file, so this
    /// cannot collide with a member id built by `of`.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub fn in_scope(scope: &Self, name: &str) -> Self {
        Self(format!("{scope}.{name}"))
    }

    /// METHOD: The id standing for "this file's top-level code ran".
    /// Angle brackets never appear in an identifier, so it cannot
    /// collide with a declaration's id.
    pub fn script(file: &Path) -> Self {
        Self(format!("{}::<script>", Self::text(file)))
    }

    /// METHOD: The id of a symbol that belongs to no file, because every
    /// file that names it names the same one. Angle brackets never
    /// appear in an identifier, so it cannot collide with a
    /// declaration's id.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    pub fn shared(name: &str) -> Self {
        Self(format!("{SHARED}{name}"))
    }

    /// METHOD: Whether this is the id of a symbol that belongs to no
    /// file.
    pub fn is_shared(&self) -> bool {
        self.0.starts_with(SHARED)
    }

    /// METHOD: A file's path as an id carries it, with `/` between its
    /// parts whatever the platform separates with. One file can be
    /// named in more than one way, and an id built from the text of a
    /// path would make each of those names a symbol of its own.
    fn text(file: &Path) -> String {
        file.components()
            .filter(|c| *c != Component::CurDir)
            .map(|c| c.as_os_str().to_string_lossy())
            .collect::<Vec<_>>()
            .join("/")
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

    /// The symbol whose body owns this one, where one does. A local
    /// variable carries the id of its function; everything a whole
    /// file can see carries `None`. Resolution reads it to keep a
    /// scoped symbol out of every by-name lookup, so that a body's
    /// own variable cannot be credited from anywhere else.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub scope: Option<SymbolId>,

    /// Set where this declaration is the one a finding names among
    /// several of one id. A variable every file shares can be written
    /// in many places, and the reader is sent to the one that states
    /// what it is.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
    pub lead: bool,
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
    /// Set where the name is the language's own, as a Vim9 type word
    /// in a type is. It is still resolved, because a project symbol of
    /// that name must still be credited, and the mark is read only
    /// where nothing resolved, to say that the gap is not one.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub owned: bool,
    /// Set where the name stands behind a dot, whatever the receiver
    /// is: a name, a call or an index. Such a name is a member of a
    /// class or a key of a dictionary, and never a bare name of the
    /// project.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub member: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Import {
    pub from: PathBuf,
    pub to: PathBuf,
    /// The namespace alias: the name after `as`, or the target's own
    /// file stem, which is what `import autoload 'foo.vim'` binds.
    pub alias: Option<String>,
    /// Each name of `import {A, B as C} from ...`, as the pair the
    /// file calls it by and the name it really has.
    pub names: Vec<(String, String)>,
}

/// A piece of text a file holds. Vim evaluates text in many places a
/// parser cannot see: a mapping's right-hand side, a command's
/// completion function, `feedkeys`, and a substitution that opens with
/// `\\=`. A name in one of those is used, so the text is kept and
/// matched against the project's own names once they are all known.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Text {
    pub text: String,
    pub file: PathBuf,
    pub line: u32,
    pub origin: Option<SymbolId>,
}

/// A name with a gap in it. Part of a name can be known only when the
/// program runs, as the `{kind}` of `g:plugin_{kind}_width`, and the
/// read then names every symbol that the fixed parts fit. It is kept
/// until all the symbols are known, as text is.
/// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/55
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fit {
    /// What the name starts with.
    pub head: String,
    /// What the name ends with, which may be nothing.
    pub tail: String,
    /// Set where no part of the name itself is fixed, so that the read
    /// names everything the start alone admits.
    pub whole: bool,
    pub file: PathBuf,
    pub line: u32,
    pub origin: Option<SymbolId>,
}

/// TRAIT: What a language's scan writes its findings into, so that a
/// language need not know how they are stored.
pub trait Sink {
    fn sym(&mut self, s: Symbol);
    fn re(&mut self, r: Reference);
    fn import(&mut self, i: Import);
    fn root(&mut self, id: SymbolId);
    fn text(&mut self, t: Text);
    fn fit(&mut self, f: Fit);
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Analysis {
    pub syms: Vec<Symbol>,
    pub refs: Vec<Reference>,
    pub roots: Vec<SymbolId>,
    pub imports: Vec<Import>,
    /// The imports that name a file the scan does not hold: a plugin
    /// outside the root, or a file git ignores. Such an import
    /// resolves to nothing, and the names it binds are still names
    /// the importing file declares.
    /// REFERENCE: https://github.com/Galvarcus/GhostCode/issues/12
    pub outside: Vec<Import>,
    pub texts: Vec<Text>,
    pub fits: Vec<Fit>,
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

    fn text(&mut self, t: Text) {
        self.texts.push(t);
    }

    fn fit(&mut self, f: Fit) {
        self.fits.push(f);
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

    #[test]
    fn a_shared_id_names_no_file_and_cannot_collide() {
        let id = SymbolId::shared("g:x");

        assert_eq!(id.to_string(), "<shared>::g:x");
        assert!(id.is_shared());
        assert!(!SymbolId::of(Path::new("plugin/p.vim"), None, "x").is_shared());
    }

    /// One file can be named in more than one way: a `ghostcode.toml`
    /// entry can carry a leading `./`, and a path built from text can
    /// separate its parts with `/` where the platform separates with
    /// `\`. Each of those names one file, so each must give one id.
    #[test]
    fn one_file_named_two_ways_gives_one_id() {
        let plain = Path::new("autoload/ghostcode/log.vim");
        let dotted = Path::new("./autoload/ghostcode/log.vim");

        assert_eq!(
            SymbolId::of(plain, None, "New"),
            SymbolId::of(dotted, None, "New")
        );
        assert_eq!(SymbolId::script(plain), SymbolId::script(dotted));
    }

    /// The guard for Windows, where this cannot fail: the walker
    /// separates a path with `\` there, and `src/resolve.rs` builds
    /// an autoload path from text with `/`, so an id that kept the
    /// platform separator would leave every nested autoload function
    /// unreachable and reported as a ghost.
    #[test]
    fn an_id_separates_its_path_with_forward_slashes() {
        let file = PathBuf::from("autoload").join("ghostcode").join("log.vim");

        assert_eq!(
            SymbolId::of(&file, None, "New").to_string(),
            "autoload/ghostcode/log.vim::New"
        );
    }
}
