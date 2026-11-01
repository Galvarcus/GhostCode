vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_lang.vim: the language framework of lang.vim and its users.
# Checks the language setting and the English fallback, and uses a second
# language file, tools/lang/zz.json, written for the test and removed
# afterward, to show that a language file changes the word rules and
# hides Passive when the tagger has no passive rule for it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/pos.vim' as POS
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/tagger.vim' as TA

const TEST_FILE: string = LA.PluginRoot() .. '/tools/lang/zz.json'
const MOCK_TAGGER: string = expand('<sfile>:p:h') .. '/mock_tagger.py'

# FUNCTION: Switch to language code, and forget every cached file and list.
def UseLanguage(code: string): void
  g:bartleby_language = code
  LA.ClearCache()
  POS.ClearLists()
enddef

def Test_setting_sets_the_code(): void
  UseLanguage('en')
  assert_equal('en', LA.Code())
  assert_equal('English', LA.Get('language', ''))
enddef

def Test_missing_language_file_uses_english(): void
  UseLanguage('xx')
  assert_equal('English', LA.Get('language', ''))
  UseLanguage('en')
enddef

def Test_language_file_sets_the_rules(): void
  writefile([json_encode({
    language: 'Test', tagger_passive: false, spacy_model: 'en_core_web_sm',
    adverb_suffixes: ['ment'], contraction_suffixes: [],
    lists: {adverbs: [], adverb_exceptions: []},
  })], TEST_FILE)
  UseLanguage('zz')
  var lists = POS.Lists()
  assert_true(POS.IsHeuristicAdverb('rapidement', lists))
  assert_false(POS.IsHeuristicAdverb('quickly', lists))
  assert_false(POS.IsContraction("don't", lists))
  delete(TEST_FILE)
  UseLanguage('en')
  lists = POS.Lists()
  assert_true(POS.IsHeuristicAdverb('quickly', lists))
  assert_true(POS.IsContraction("don't", lists))
enddef

def Test_passive_hidden_without_a_passive_rule(): void
  writefile([json_encode({language: 'Test', tagger_passive: false, spacy_model: 'x'})], TEST_FILE)
  g:bartleby_spotlight_tagger = ['python3', MOCK_TAGGER]
  TA.Reset()
  UseLanguage('zz')
  assert_equal(-1, index(SP.AvailableModes(), 'Passive'))
  assert_true(index(SP.AvailableModes(), 'Nouns') >= 0)
  UseLanguage('en')
  assert_true(index(SP.AvailableModes(), 'Passive') >= 0)
  delete(TEST_FILE)
  g:bartleby_spotlight_tagger = ''
  TA.Reset()
enddef

export def RunAll(): void
  Test_setting_sets_the_code()
  Test_missing_language_file_uses_english()
  Test_language_file_sets_the_rules()
  Test_passive_hidden_without_a_passive_rule()
  UseLanguage('')
enddef
