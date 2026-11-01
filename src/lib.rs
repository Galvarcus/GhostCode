//! Ghostcode: finds the code in a project that nothing references.
//!
//! License: GNU GPL 3.0

pub mod cli;
pub mod config;
pub mod lang;
pub mod model;
pub mod project;
pub mod resolve;

/// The program's name, stated once so that no other file repeats it.
pub const NAME: &str = "ghostcode";
