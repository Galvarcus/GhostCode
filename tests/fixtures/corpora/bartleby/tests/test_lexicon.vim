vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_lexicon.vim: the pure parts of lexicon.vim: ParseResponse
# for each kind of response, CleanWord, UrlEncode, MatchCase, the rules
# that turn lookups on and off, and BuildUrl. No network. The fixtures
# follow the formats in Merriam-Webster's JSON documentation.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/lexicon_mw.vim' as LXM
import autoload 'bartleby/lexicon_result.vim' as LR

const DICTIONARY_BODY: string = json_encode([
  {
    meta: {id: 'murmurous', stems: ['murmurous', 'murmurously']},
    hwi: {hw: 'mur*mur*ous'},
    fl: 'adjective',
    shortdef: ['filled with or characterized by murmurs : low and indistinct'],
  },
  {
    meta: {id: 'murmur', stems: ['murmur']},
    hwi: {hw: 'mur*mur'},
    fl: 'noun',
    shortdef: ['a half-suppressed or muttered complaint'],
  },
])

const THESAURUS_BODY: string = json_encode([
  {
    meta: {
      id: 'component', stems: ['component', 'components'],
      syns: [['building block', 'constituent', 'element']],
      ants: [['whole']],
    },
    hwi: {hw: 'component'},
    fl: 'noun',
    shortdef: ['one of the parts that make up a whole'],
  },
])

def Test_parse_dictionary_keeps_only_matching_entries(): void
  var result = LE.ParseResp('dictionary', 'murmurous', DICTIONARY_BODY)
  assert_equal('ok', result.status)
  assert_equal(1, len(result.entries))
  assert_equal('murmurous', result.entries[0].headword)
  assert_equal('mur·mur·ous', result.entries[0].display)
  assert_equal('adjective', result.entries[0].fl)
  assert_equal(['filled with or characterized by murmurs : low and indistinct'],
    result.entries[0].defs)
enddef

def Test_parse_dictionary_keeps_all_entries_when_none_match(): void
  var result = LE.ParseResp('dictionary', 'murmurings', DICTIONARY_BODY)
  assert_equal(2, len(result.entries))
enddef

def Test_parse_thesaurus_senses_and_antonyms(): void
  var result = LE.ParseResp('thesaurus', 'component', THESAURUS_BODY)
  assert_equal('ok', result.status)
  var entry = result.entries[0]
  assert_equal('one of the parts that make up a whole', entry.senses[0].label)
  assert_equal(['building block', 'constituent', 'element'], entry.senses[0].syns)
  assert_equal(['whole'], entry.ants)
enddef

def Test_parse_suggestion_list_is_notfound_with_suggestions(): void
  var result = LE.ParseResp('dictionary', 'murmerous', '["murmurous", "murmurs"]')
  assert_equal('notfound', result.status)
  assert_equal(['murmurous', 'murmurs'], result.suggestions)
enddef

def Test_parse_empty_list_is_notfound_without_suggestions(): void
  var result = LE.ParseResp('dictionary', 'zzzq', '[]')
  assert_equal('notfound', result.status)
  assert_equal([], result.suggestions)
enddef

def Test_parse_plain_text_is_an_error_with_its_first_line(): void
  var result = LE.ParseResp('dictionary', 'word', "Invalid API key. Not subscribed for this reference.\n")
  assert_equal('error', result.status)
  assert_match('Invalid API key', result.message)
enddef

def Test_parse_empty_body_is_an_error(): void
  assert_equal('error', LE.ParseResp('dictionary', 'word', '  ').status)
enddef

def Test_parse_entries_without_definitions_are_notfound(): void
  var body = json_encode([{meta: {id: 'x', stems: ['x']}, hwi: {hw: 'x'}, fl: 'noun'}])
  assert_equal('notfound', LE.ParseResp('dictionary', 'x', body).status)
enddef

def Test_clean_word(): void
  assert_equal('quiet', LE.CleanWord('  Quiet, '))
  assert_equal('sam', LE.CleanWord("Sam's"))
  assert_equal('go-between', LE.CleanWord('"go-between"'))
  assert_equal('ice cream', LE.CleanWord('Ice   Cream'))
enddef

def Test_url_encode(): void
  assert_equal('ice%20cream', LXM.UrlEncode('ice cream'))
  assert_equal('go-between', LXM.UrlEncode('go-between'))
  assert_equal('caf%C3%A9', LXM.UrlEncode('café'))
enddef

def Test_match_case(): void
  assert_equal('calm', LE.MatchCase('quiet', 'calm'))
  assert_equal('Calm', LE.MatchCase('Quiet', 'calm'))
  assert_equal('CALM', LE.MatchCase('QUIET', 'calm'))
  assert_equal('Calm', LE.MatchCase('I', 'calm'))
enddef

def Test_disabled_without_a_key(): void
  var saved = g:bartleby_dictionary_api_key
  var savedEnv = getenv('BARTLEBY_MW_DICTIONARY_KEY')
  g:bartleby_dictionary_api_key = ''
  setenv('BARTLEBY_MW_DICTIONARY_KEY', v:null)
  assert_false(LE.IsEnabled('dictionary'))
  assert_match('g:bartleby_dictionary_api_key', LE.DisabledReason('dictionary'))
  g:bartleby_dictionary_api_key = saved
  setenv('BARTLEBY_MW_DICTIONARY_KEY', savedEnv)
enddef

def Test_environment_key_is_the_fallback(): void
  var saved = g:bartleby_thesaurus_api_key
  var savedEnv = getenv('BARTLEBY_MW_THESAURUS_KEY')
  g:bartleby_thesaurus_api_key = ''
  setenv('BARTLEBY_MW_THESAURUS_KEY', 'env-key')
  assert_equal('env-key', LE.ApiKey('thesaurus'))
  g:bartleby_thesaurus_api_key = 'global-key'
  assert_equal('global-key', LE.ApiKey('thesaurus'))
  g:bartleby_thesaurus_api_key = saved
  setenv('BARTLEBY_MW_THESAURUS_KEY', savedEnv)
enddef

def Test_unknown_or_wrong_kind_reference_is_disabled(): void
  var savedKey = g:bartleby_dictionary_api_key
  var savedRef = g:bartleby_dictionary_reference
  g:bartleby_dictionary_api_key = 'k'
  g:bartleby_dictionary_reference = 'thesaurus'
  assert_equal({}, LE.Ref('dictionary'))
  assert_false(LE.IsEnabled('dictionary'))
  g:bartleby_dictionary_reference = 'nosuch'
  assert_false(LE.IsEnabled('dictionary'))
  g:bartleby_dictionary_api_key = savedKey
  g:bartleby_dictionary_reference = savedRef
enddef

def Test_build_url(): void
  var savedKey = g:bartleby_dictionary_api_key
  g:bartleby_dictionary_api_key = 'abc'
  assert_equal('https://www.dictionaryapi.com/api/v3/references/collegiate/json/ice%20cream?key=abc',
    LE.BuildUrl('dictionary', 'ice cream'))
  g:bartleby_dictionary_api_key = savedKey
enddef

def Test_reference_comes_from_the_language_file(): void
  var saved = g:bartleby_dictionary_reference
  g:bartleby_dictionary_reference = ''
  assert_equal('collegiate', LE.Ref('dictionary').apiName)
  assert_equal('merriam-webster', LE.Ref('dictionary').provider)
  g:bartleby_dictionary_reference = saved
enddef

def Test_unknown_reference_is_off_with_a_reason(): void
  var saved = g:bartleby_dictionary_reference
  g:bartleby_dictionary_reference = 'nosuch'
  assert_false(LE.IsEnabled('dictionary'))
  assert_match('no dictionary reference "nosuch"', LE.DisabledReason('dictionary'))
  g:bartleby_dictionary_reference = saved
enddef

# FUNCTION: The cache on disk is JSON, so a result is stored as a dict, with
# the keys that it had before Result was a class. A cache file that is
# already on disk stays valid, and a missing key does not break a read.
def Test_a_result_keeps_its_shape_on_disk(): void
  var result = LR.NotFound(['murmurous'])
  assert_equal({status: 'notfound', entries: [], suggestions: ['murmurous'], message: ''}, result.ToDict())
  var back = LR.Result.FromDict(json_decode(json_encode(result.ToDict())))
  assert_equal('notfound', back.status)
  assert_equal(['murmurous'], back.suggestions)
  assert_equal('error', LR.Result.FromDict({}).status)
enddef

export def RunAll(): void
  Test_a_result_keeps_its_shape_on_disk()
  Test_parse_dictionary_keeps_only_matching_entries()
  Test_parse_dictionary_keeps_all_entries_when_none_match()
  Test_parse_thesaurus_senses_and_antonyms()
  Test_parse_suggestion_list_is_notfound_with_suggestions()
  Test_parse_empty_list_is_notfound_without_suggestions()
  Test_parse_plain_text_is_an_error_with_its_first_line()
  Test_parse_empty_body_is_an_error()
  Test_parse_entries_without_definitions_are_notfound()
  Test_clean_word()
  Test_url_encode()
  Test_match_case()
  Test_disabled_without_a_key()
  Test_environment_key_is_the_fallback()
  Test_unknown_or_wrong_kind_reference_is_disabled()
  Test_build_url()
  Test_reference_comes_from_the_language_file()
  Test_unknown_reference_is_off_with_a_reason()
enddef
