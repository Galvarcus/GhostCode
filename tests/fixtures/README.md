# Fixture corpora

What the Vim9 analyzer reported, recorded before it was deleted, as the
golden output the Rust core must reproduce. Nothing after the deletion
can recreate these, so a refresh is deliberate and never automatic.

Each corpus holds the `.vim` files that `git ls-files` named in its
upstream repository, in their upstream paths, and no symlink. A
gitignored file is absent, so a corpus holds what CI sees rather than
what a working copy holds.

| Corpus | Upstream | Commit | Files | Lines |
| --- | --- | --- | --- | --- |
| `bartleby` | `Galvarcus/bartleby` | `05ce0c4` | 138 | 32,712 |
| `logger` | `Galvarcus/Logger` | `0c6456b` | 12 | 1,030 |
| `ghostcode` | this repository | `41a11cf` | 5 | 2,593 |
| `nested` | `logger` under `deps/Logger`, plus a root `plugin/host.vim` | built here | 13 | 1,038 |

Captured on 2026-11-01 with `tools/capture-fixtures.sh`, once per
setting of `g:ghostcode_exports_are_api`: `-api` for the default, true,
and `-strict` for false. The `.txt` form is the line Bartleby's workflow
writes, `file:line:col:text`, with the path relative to the corpus root.
The `.json` form is derived from it by `tools/fixture-json.py`, so that
both describe one run and cannot disagree. `tests/parity.rs` compares
both: the text form whole, and the JSON form's findings, which leaves
out the root, because it is the absolute path of the machine that
captured it, and the summary, which was never captured.

## Why three corpora report nothing

`bartleby`, `logger` and `ghostcode` each report no findings, in both
settings. That is correct and it is the point: the analyzer's
entry-script rule is relative to the scanned root, so a corpus whose own
`plugin/` and `tests/` sit at its root has every symbol reachable from
an entry point. These three fixtures prove the Rust core invents no
finding across 36,335 lines of real code, which is the failure that
would turn another project's build red.

`nested` is where the findings are. It places `logger` at
`deps/Logger/`, the layout Bartleby has locally, where `plugin/` and
`tests/` are no longer at the root and so root nothing. It reports 2
findings in the default setting and 102 in strict, covering the
`class`, `field`, `function`, `method` and `variable` kinds.

No corpus covers the `enum`, `enum value` or `interface` kinds, because
no upstream project uses them. The semantic tests and the truth families
cover those.

## The truth families

A corpus proves that the findings stay as they were. It cannot prove
that a finding is a ghost, or that no ghost is missed, because nothing in
it states which symbol is which. Each directory under `truth/` is a small
project of one family of constructs that does. The line above each
declaration is a marker:

| Marker | The symbol | A finding names it |
| --- | --- | --- |
| `# GHOST` | has no use | yes |
| `# LIVE` | has a use | no |
| `# MISSED` | has no use, and the readme states the limit | no |

`tests/truth.rs` scans each family with the settings in its own
`ghostcode.toml` and fails where a finding and a marker disagree, where a
symbol has no marker, and where a `# GHOST` or `# LIVE` marker sits above
a line that declares no symbol. `tests/test_truth.vim` proves that Vim
sources and compiles each file, so that a family holds only what Vim
accepts.

A new family is a new directory, with no change to either test. A case
that shows a fault of the analyzer enters with the fix of that fault.
