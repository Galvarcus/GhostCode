<!--
The comments in this template are not shown in the pull request.
Delete any section that does not apply.

Write the commit message in the form this project uses:

    subject states the problem

    Problem:  Full sentence restating the subject.
    Solution: Short description of the fix, ending with the author's
              name in parentheses.

    Prose for a longer account of the problem and the fix. No bullet
    points.

    fixes:   #NNNN
    related: #NNNN

    Assisted-by: Claude Opus 5

The subject states the problem rather than the fix, in lower case,
within 72 characters, and with no trailing period. The prose wraps at
78 columns. `fixes:` names the issue the commit closes, `related:`
names one that bears on it, and their values align.

For a pull request of one commit, GitHub takes the first line as the
title and the rest as the start of this description.
-->

## AI assistance

<!--
The tool goes on an `Assisted-by:` trailer, which replaces
`Co-authored-by:`. The name in parentheses on the `Solution:` line is
the author's, whatever wrote the change.
-->

- [ ] AI involvement is disclosed in the commit message
- [ ] No AI was used

## Checklist

- [ ] The commit message follows the Problem and Solution form above
- [ ] `tools/check` prints `every check passed`
- [ ] The `Signed-off-by:` trailer is present, which the
      `prepare-commit-msg` hook adds. A fresh checkout has no hooks,
      so install them again before the first commit

### Tests

<!--
A new Rust test goes in `tests/<subject>.rs`, or in a
`#[cfg(test)] mod tests` at the end of the file it tests. A new Vim
test goes in `tests/test_<area>.vim` and is registered in
`tests/harness.vim`.

To prove a test guards the change, break the change on purpose and
confirm that a named test fails.
-->

- [ ] Tests were added, and each was watched failing first
- [ ] Existing tests cover the change
- [ ] The change cannot be tested, for the reason given below

### What the analyzer reports

<!--
The parity suite is the acceptance test of the port. A difference is
either a defect here or a fault in the analyzer this replaced, and
neither is accepted without being read. The projects under
`tests/fixtures/corpora/` run this analyzer in their own builds and
count the lines carrying `[ghost]`, so a finding that moves reaches
them.

The files under `tests/fixtures/expected/` record what the Vim9
analyzer reported before it was deleted, and nothing can recreate
them. A change to one needs a reason in the commit message.
-->

- [ ] No finding moves, and every parity fixture matches
- [ ] A finding moves, and the diff is read below

### Documentation

<!--
`doc/ghostcode.txt` is generated from `README.md` by
`.github/workflows/ci.yml` on a push to `main`, so it is never edited
by hand.
-->

- [ ] `README.md` was updated
- [ ] No documentation update is needed

## Anything reviewers should know

<!--
For example a change in behavior a user will notice, a platform the
change could not be tested on, or an assumption it rests on.
-->
