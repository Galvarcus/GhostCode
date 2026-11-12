//! Vim9: the language the analyzer was written for, parsed here rather
//! than matched with regular expressions.
//!
//! License: GNU GPL 3.0

mod autocmd;
mod builtins;
mod evaluated;
mod events;
mod excmds;
mod exists;
pub mod lex;
pub mod parse;
pub mod rules;
mod scopevars;
mod shared;
pub mod types;

use std::path::Path;

use crate::config::Config;
use crate::lang::Lang;
use crate::model::Sink;
use crate::model::Symbol;
use crate::project::Source;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Vim9;

impl Lang for Vim9 {
    fn name(&self) -> &'static str {
        "vim9"
    }

    fn extensions(&self) -> &[&'static str] {
        &["vim"]
    }

    fn is_entry(&self, _root: &Path, file: &Path) -> bool {
        rules::is_entry(file)
    }

    fn scan(&self, src: &Source, out: &mut dyn Sink) -> anyhow::Result<()> {
        let toks = lex::tokens(&src.text);
        let stmts = parse::statements(&toks);
        parse::declarations(&src.rel, &stmts, out);
        parse::imports(&src.rel, &stmts, out);
        parse::references(&src.rel, &stmts, out);
        Ok(())
    }

    fn is_api(&self, sym: &Symbol, cfg: &Config) -> bool {
        rules::is_api(sym, cfg)
    }

    fn shared_on(&self, name: &str, cfg: &Config) -> bool {
        rules::shared_on(name, cfg)
    }
}
