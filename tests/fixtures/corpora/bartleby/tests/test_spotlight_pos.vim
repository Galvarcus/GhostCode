vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_spotlight_pos.vim: Spotlight's part-of-speech modes in a real
# buffer. Reads which words stay bright from the SpotlightDim match of the
# window. Tagger modes use tests/mock_tagger.py, which needs only Python
# 3, not spaCy, and wait for its asynchronous results.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/tagger.vim' as TA
import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/pos.vim' as POS

const MOCK_TAGGER: string = expand('<sfile>:p:h') .. '/mock_tagger.py'
const TEXT: list<string> = [
  '# Chapter One',
  '',
  'She quietly walked away very slowly, "Wait," and the red door was opened by him.',
]

def OpenBuffer(): void
  new
  setlocal buftype=nofile filetype=markdown
  setline(1, TEXT)
  cursor(3, 1)
enddef

def CloseBuffer(): void
  SP.Execute(true, '')
  bwipe!
enddef

def UseTagger(setting: any): void
  g:bartleby_spotlight_tagger = setting
  TA.Reset()
enddef

# FUNCTION: Return the dimmed columns of line lnum, from the SpotlightDim
# match of the current window.
def DimmedColumns(lnum: number): dict<bool>
  var dimmed: dict<bool> = {}
  for m in getmatches()->filter((_, x) => x.group ==# 'SpotlightDim')
    for [k, v] in items(m)
      if k =~# '^pos' && v[0] == lnum
        var first: number = len(v) == 1 ? 1 : v[1]
        var last: number = len(v) == 1 ? strlen(getline(lnum)) : v[1] + v[2] - 1
        for c in range(first, last)
          dimmed[c] = true
        endfor
      endif
    endfor
  endfor
  return dimmed
enddef

# FUNCTION: Return the runs of text on line lnum that are not dimmed.
def LitWords(lnum: number): list<string>
  var dimmed: dict<bool> = DimmedColumns(lnum)
  var text: string = getline(lnum)
  var words: list<string> = []
  var word: string = ''
  for c in range(1, strlen(text))
    if strpart(text, c - 1, 1) =~ '\S' && !has_key(dimmed, c)
      word ..= strpart(text, c - 1, 1)
    elseif word !=# ''
      words->add(word)
      word = ''
    endif
  endfor
  if word !=# ''
    words->add(word)
  endif
  return words
enddef

# FUNCTION: Wait up to 10 seconds for expected on line 3, because tagger
# results arrive asynchronously, then check it.
def AssertLitSoon(expected: list<string>, what: string): void
  var waited: number = 0
  while LitWords(3) != expected && waited < 10000
    sleep 100m
    waited += 100
  endwhile
  assert_equal(expected, LitWords(3), what)
enddef

def Test_tagger_modes_hidden_without_a_tagger(): void
  UseTagger('')
  var modes = SP.AvailableModes()
  for mode in ['Nouns', 'Verbs', 'Adjectives', 'Passive']
    assert_equal(-1, index(modes, mode), mode)
  endfor
  for mode in ['Paragraph', 'Dialogue', 'Adverbs', 'Pronouns', 'Determiners',
      'Prepositions', 'Conjunctions', 'Auxiliaries', 'Contractions', 'Fillers']
    assert_true(index(modes, mode) >= 0, mode)
  endfor
enddef

def Test_word_list_modes_light_their_words(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Adverbs')
  assert_equal(['quietly', 'away', 'very', 'slowly'], LitWords(3))
  SP.Execute(false, 'Pronouns')
  assert_equal(['She', 'him'], LitWords(3))
  SP.Execute(false, 'Fillers')
  assert_equal(['very'], LitWords(3))
  CloseBuffer()
enddef

def Test_heading_line_dims_entirely(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Adverbs')
  assert_equal([], LitWords(1))
  CloseBuffer()
enddef

def Test_dialogue_lights_quoted_speech(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Dialogue')
  assert_equal(['"Wait,"'], LitWords(3))
  CloseBuffer()
enddef

def Test_dialogue_lights_curly_quotes(): void
  new
  setlocal buftype=nofile filetype=markdown
  setline(1, ['Title', '', 'She said, “Wait,” and left.'])
  cursor(3, 1)
  SP.Execute(false, 'Dialogue')
  assert_equal(['“Wait,”'], LitWords(3))
  CloseBuffer()
enddef

def Test_mock_tagger_modes(): void
  UseTagger(['python3', MOCK_TAGGER])
  var modes = SP.AvailableModes()
  for mode in ['Nouns', 'Verbs', 'Adjectives', 'Passive']
    assert_true(index(modes, mode) >= 0, mode)
  endfor
  OpenBuffer()
  SP.Execute(false, 'Nouns')
  AssertLitSoon(['away', 'very', 'slowly', 'Wait', 'door'], 'Nouns')
  SP.Execute(false, 'Verbs')
  AssertLitSoon(['walked', 'opened'], 'Verbs')
  SP.Execute(false, 'Adjectives')
  AssertLitSoon(['red'], 'Adjectives')
  SP.Execute(false, 'Passive')
  AssertLitSoon(['was', 'opened'], 'Passive')
  # With a tagger, Adverbs uses the tags, not the ly heuristic. The mock
  # tags only quietly as ADV.
  SP.Execute(false, 'Adverbs')
  AssertLitSoon(['quietly'], 'Adverbs with a tagger')
  CloseBuffer()
  UseTagger('')
enddef

def Test_failing_tagger_turns_spotlight_off_and_hides_modes(): void
  UseTagger(['python3', '-c', 'import sys; sys.exit(3)'])
  OpenBuffer()
  SP.Execute(false, 'Nouns')
  var waited: number = 0
  while SP.IsOn() && waited < 10000
    sleep 100m
    waited += 100
  endwhile
  assert_false(SP.IsOn())
  assert_equal(-1, index(SP.AvailableModes(), 'Nouns'))
  assert_true(index(SP.AvailableModes(), 'Adverbs') >= 0)
  CloseBuffer()
  UseTagger('')
enddef

# FUNCTION: Every registered mode needs a display name.
def Test_mode_names_cover_every_mode(): void
  g:bartleby_spotlight_tagger = ['python3', MOCK_TAGGER]
  TA.Reset()
  assert_equal(sort(SP.AvailableModes()), sort(keys(SP.ModeNames())))
  g:bartleby_spotlight_tagger = ''
  TA.Reset()
enddef

# FUNCTION: The line cache keys on the text, so an edited line is lit from its
# new text, not from what the cache remembers.
def Test_an_edited_line_is_lit_from_its_new_text(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Adverbs')
  assert_equal(['quietly', 'away', 'very', 'slowly'], LitWords(3))
  setline(3, 'She ran quickly.')
  doautocmd CursorMoved
  assert_equal(['quickly'], LitWords(3))
  CloseBuffer()
enddef

# FUNCTION: The cache keeps positions without a line number, so a line that
# moves down is lit at its new place.
def Test_a_moved_line_is_lit_at_its_new_place(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Adverbs')
  var expected: list<string> = LitWords(3)
  append(1, 'A new line.')
  doautocmd CursorMoved
  assert_equal(expected, LitWords(4))
  CloseBuffer()
enddef

def Test_an_edited_line_is_lit_again_in_dialogue_mode(): void
  UseTagger('')
  OpenBuffer()
  SP.Execute(false, 'Dialogue')
  setline(3, 'He said "go now" and left.')
  doautocmd CursorMoved
  assert_equal(['"go', 'now"'], LitWords(3))
  CloseBuffer()
enddef

# FUNCTION: The dialogue pattern comes from the language, and the line cache
# keys on it, so a new language relights a line whose text is the same.
def Test_a_new_language_relights_dialogue(): void
  var file: string = LA.PluginRoot() .. '/tools/lang/zz.json'
  writefile([json_encode({language: 'Test', dialogue_pattern: '«[^»]*»'})], file)
  UseTagger('')
  OpenBuffer()
  setline(3, 'He said «go now» and "stop here" then left.')
  SP.Execute(false, 'Dialogue')
  assert_equal(['"stop', 'here"'], LitWords(3))
  g:bartleby_language = 'zz'
  LA.ClearCache()
  POS.ClearLists()
  # Change another line, so that the whole window cache is not reused.
  setline(1, getline(1) .. ' ')
  doautocmd CursorMoved
  assert_equal(['«go', 'now»'], LitWords(3))
  CloseBuffer()
  delete(file)
  g:bartleby_language = 'en'
  LA.ClearCache()
  POS.ClearLists()
enddef

export def RunAll(): void
  # Spotlight computes its dim color from Normal.
  highlight Normal ctermfg=252 ctermbg=235 guifg=#d0d0d0 guibg=#262626
  set t_Co=256
  # Spotlight needs a color model for its dim color, and 256 colors is the
  # one these tests set up, see Dim in spotlight.vim. A system that keeps
  # its own count sends Dim to its last branch, which throws, and then
  # every assertion below fails for a reason of its own, so the premise
  # says so itself.
  assert_equal('256', &t_Co, 'the system kept its own color count')
  Test_tagger_modes_hidden_without_a_tagger()
  Test_word_list_modes_light_their_words()
  Test_an_edited_line_is_lit_from_its_new_text()
  Test_a_moved_line_is_lit_at_its_new_place()
  Test_an_edited_line_is_lit_again_in_dialogue_mode()
  Test_a_new_language_relights_dialogue()
  Test_heading_line_dims_entirely()
  Test_dialogue_lights_quoted_speech()
  Test_dialogue_lights_curly_quotes()
  Test_mock_tagger_modes()
  Test_failing_tagger_turns_spotlight_off_and_hides_modes()
  Test_mode_names_cover_every_mode()
  # The mode of Spotlight is one setting of the whole Vim and outlives this
  # suite, and these tests leave it on a mode of the tagger. A later suite
  # that asks for Spotlight without naming a mode would then ask for that
  # one, which refuses without a tagger, and say only that Spotlight did
  # not start. So the suite leaves the mode as it found it, off and on
  # Paragraph. test_tty.vim used to do this by accident, until it stopped
  # running on Windows.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
  SP.Execute(false, 'Paragraph')
  SP.Execute(true, '')
enddef
