vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_tagger_smoke.vim: the real spaCy tagger,
# tools/pos/spacy_tagger.py, through tagger.vim. Skipped when python3, or
# spaCy with its model, is not installed. Runs on its own, not through
# harness.vim, and writes tests/tagger_results.txt.
#
# Usage: the same command as tests/harness.vim.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/tagger.vim' as TA
import './report.vim' as RE

const RESULT: string = 'tests/tagger_results.txt'
const PASS: string = 'All tagger tests passed'

const TEXT: string = "The door was opened by her.\nShe runs fast. The run was long."

def HasSpacy(): bool
  if !executable('python3')
    return false
  endif
  # The model that the tagger would run: the last word of its command.
  g:bartleby_spotlight_tagger = 'spacy'
  var model: string = get(TA.Command(), -1, '')
  system($'python3 -c "import spacy; spacy.load(''{model}'')"')
  return model !=# '' && v:shell_error == 0
enddef

# FUNCTION: Return the text of each byte span.
def Pieces(spans: list<any>): list<string>
  return spans->mapnew((_, s) => strpart(TEXT, s[0], s[1] - s[0]))
enddef

def Test_real_tagger(): void
  if !HasSpacy()
    echom 'SKIP: python3 with spaCy and its model not installed'
    return
  endif
  g:bartleby_spotlight_tagger = 'spacy'
  TA.Reset()
  TA.Tags(TEXT)
  var tags: dict<any> = {}
  var waited: number = 0
  while empty(tags) && waited < 60000
    sleep 200m
    waited += 200
    tags = TA.Tags(TEXT)
  endwhile
  assert_false(empty(tags), 'no tagger result within 60 seconds')
  if empty(tags)
    return
  endif
  assert_equal(['was opened'], Pieces(tags.passive))
  var tagOf: dict<string> = {}
  for t in tags.tokens
    tagOf[$'{t[0]}'] = t[2]
  endfor
  # runs is a verb and run a noun: the tagger uses the context.
  assert_equal('VERB', tagOf[string(stridx(TEXT, 'runs'))])
  assert_equal('NOUN', tagOf[string(stridx(TEXT, 'run was'))])
  assert_equal('NOUN', tagOf[string(stridx(TEXT, 'door'))])
  TA.Reset()
enddef

execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
RE.RunTests([Test_real_tagger])
if !RE.Report(RESULT, PASS)
  cquit 1
endif
