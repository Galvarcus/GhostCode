#!/usr/bin/env bash
#
# tools/capture-fixtures.sh: record what the Vim9 analyzer reports for one
# corpus, in both settings of g:ghostcode_exports_are_api, as the golden
# output the Rust core must reproduce. Run it once per corpus before the
# Vim9 analyzer is deleted, because nothing afterwards can recreate it.
#
#   LOGGER=/path/to/Logger tools/capture-fixtures.sh <corpus-dir> <name>
#
# License: GNU GPL 3.0

set -euo pipefail

corpus=${1:?usage: capture-fixtures.sh <corpus-dir> <name>}
name=${2:?usage: capture-fixtures.sh <corpus-dir> <name>}
logger=${LOGGER:?set LOGGER to a Logger checkout}

root=$(git rev-parse --show-toplevel)
out="$root/tests/fixtures/expected"
corpus=$(cd "$corpus" && pwd)
mkdir -p "$out"

# The quickfix path is made relative to the corpus root, so that a fixture
# does not record where the machine that captured it kept its files. Vim
# resolves ':.' against its working directory, hence the subshell cd.
for mode in api strict; do
  if [ "$mode" = api ]; then api=1; else api=0; fi
  txt="$out/$name-$mode.txt"

  (
    cd "$corpus"
    vim -u NONE -N -es \
      --cmd "set rtp+=$root,$logger" \
      -c 'runtime plugin/ghostcode.vim' \
      -c "let g:ghostcode_exports_are_api = $api" \
      -c 'GhostCode .' \
      -c "vim9cmd writefile(getqflist()->mapnew((_, i) => printf('%s:%d:%d:%s', fnamemodify(bufname(i.bufnr), ':.'), i.lnum, i.col, i.text)), '$txt')" \
      -c 'qa!'
  )

  # The JSON form is derived from the text form, not captured separately,
  # so that the two cannot disagree about one run. Every field it adds is
  # constant for this analyzer: it reports only ghosts, only in Vim9.
  python3 "$root/tools/fixture-json.py" "$txt" "$corpus" > "$out/$name-$mode.json"

  printf '%s %s: %s findings\n' "$name" "$mode" "$(wc -l < "$txt" | tr -d ' ')"
done
