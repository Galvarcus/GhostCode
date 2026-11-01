//! Vim9 imports: which file an import names, and under what name.
//!
//! License: GNU GPL 3.0

mod common;

use std::path::Path;
use std::path::PathBuf;

use common::source;
use ghostcode::lang::vim9::Vim9;
use ghostcode::lang::Lang;
use ghostcode::model::Analysis;
use ghostcode::model::Import;

/// FUNCTION: The imports one file states.
fn imports(rel: &str, text: &str) -> Vec<Import> {
    let mut found = Analysis::default();
    Vim9.scan(&source(rel, text), &mut found)
        .expect("a scan never fails on one file");
    found.imports
}

/// FUNCTION: The one import a file states.
fn one(rel: &str, text: &str) -> Import {
    let mut all = imports(rel, text);
    assert_eq!(all.len(), 1, "one import: {all:?}");
    all.remove(0)
}

#[test]
fn a_relative_import_resolves_against_the_importing_file() {
    let i = one(
        "autoload/bartleby/quill.vim",
        "vim9script\nimport './menu.vim' as M\n",
    );

    assert_eq!(i.to, PathBuf::from("autoload/bartleby/menu.vim"));
}

#[test]
fn a_parent_relative_import_climbs_one_directory() {
    let i = one(
        "autoload/bartleby/quill.vim",
        "vim9script\nimport '../bartleby.vim' as B\n",
    );

    assert_eq!(i.to, PathBuf::from("autoload/bartleby.vim"));
}

#[test]
fn import_autoload_resolves_under_autoload() {
    let i = one("plugin/p.vim", "vim9script\nimport autoload 'foo.vim'\n");

    assert_eq!(i.to, PathBuf::from("autoload/foo.vim"));
}

#[test]
fn a_plain_import_resolves_under_import() {
    let i = one("plugin/p.vim", "vim9script\nimport 'Logger/logger.vim'\n");

    assert_eq!(i.to, PathBuf::from("import/Logger/logger.vim"));
}

#[test]
fn a_named_import_records_each_name() {
    let i = one(
        "autoload/p.vim",
        "vim9script\nimport {Foo, Bar} from './mod.vim'\n",
    );

    assert_eq!(
        i.names,
        vec![
            ("Foo".to_string(), "Foo".to_string()),
            ("Bar".to_string(), "Bar".to_string()),
        ]
    );
}

#[test]
fn a_named_import_records_an_as_alias() {
    let i = one(
        "autoload/p.vim",
        "vim9script\nimport {Foo as Renamed} from './mod.vim'\n",
    );

    assert_eq!(
        i.names,
        vec![("Renamed".to_string(), "Foo".to_string())],
        "the alias is what the file calls it, the original what it is"
    );
}

#[test]
fn a_namespace_import_defaults_its_alias_to_the_file_stem() {
    let i = one("plugin/p.vim", "vim9script\nimport autoload 'foo.vim'\n");

    assert_eq!(i.alias.as_deref(), Some("foo"));
}

#[test]
fn a_namespace_import_takes_an_as_alias() {
    let i = one(
        "plugin/p.vim",
        "vim9script\nimport autoload 'foo.vim' as NS\n",
    );

    assert_eq!(i.alias.as_deref(), Some("NS"));
}

#[test]
fn an_import_naming_a_file_outside_the_root_resolves_to_none() {
    let found = imports(
        "autoload/p.vim",
        "vim9script\nimport '../../elsewhere/mod.vim' as E\n",
    );

    assert!(
        found.is_empty(),
        "a file outside the root is not the project's: {found:?}"
    );
}

#[test]
fn the_importing_file_is_recorded_as_the_source() {
    let i = one("autoload/p.vim", "vim9script\nimport './m.vim' as M\n");

    assert_eq!(i.from, Path::new("autoload/p.vim"));
}
