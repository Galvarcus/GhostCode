//! A temporary directory for one integration test, removed on drop.
//!
//! Cargo compiles this module into every integration test binary, so a
//! helper that one test needs is dead code in the others.
//!
//! License: GNU GPL 3.0

#![allow(dead_code)]

use std::path::Path;
use std::path::PathBuf;
use std::sync::atomic::AtomicU32;
use std::sync::atomic::Ordering;

// Tests run in threads of one process, so the counter keeps two
// directories of the same tag apart.
static NEXT: AtomicU32 = AtomicU32::new(0);

pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    /// METHOD: Make an empty directory named after the calling test, so
    /// that a leftover directory says which test left it.
    pub fn new(tag: &str) -> Self {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("ghostcode-{tag}-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("create the test's temporary directory");
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// METHOD: Write one file under the directory, making its parents.
    pub fn write(&self, rel: &str, text: &str) -> PathBuf {
        let file = self.path.join(rel);
        if let Some(dir) = file.parent() {
            std::fs::create_dir_all(dir).expect("create a parent directory");
        }
        std::fs::write(&file, text).expect("write a test file");
        file
    }

    /// METHOD: Write one file as raw bytes, for text that is not UTF-8.
    pub fn write_bytes(&self, rel: &str, bytes: &[u8]) -> PathBuf {
        let file = self.path.join(rel);
        if let Some(dir) = file.parent() {
            std::fs::create_dir_all(dir).expect("create a parent directory");
        }
        std::fs::write(&file, bytes).expect("write a test file");
        file
    }

    /// METHOD: Make a symlink under the directory, so that a test can
    /// prove what a scan does with one.
    pub fn link(&self, rel: &str, target: &Path) -> PathBuf {
        let link = self.path.join(rel);
        if let Some(dir) = link.parent() {
            std::fs::create_dir_all(dir).expect("create a parent directory");
        }
        std::os::unix::fs::symlink(target, &link).expect("make a test symlink");
        link
    }

    /// METHOD: Make the directory a git repository, because a gitignore
    /// rule governs nothing outside one.
    pub fn git_init(&self) {
        let out = std::process::Command::new("git")
            .args(["init", "-q"])
            .current_dir(&self.path)
            .output()
            .expect("run git init");
        assert!(
            out.status.success(),
            "git init failed in the test directory"
        );
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}
