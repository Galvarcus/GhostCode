vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# pos.vim: the parts of Spotlight's part-of-speech modes that need no
# tagger: word lists, a tokenizer, classification by word list and
# pattern, which lines count as prose, and conversion of bright spans to
# dim positions. All pure functions, so tests can call them directly.
#
# The word lists and rules come from the language file, see lang.vim.
# g:bartleby_spotlight_words_add and g:bartleby_spotlight_words_remove
# change the list of a mode, by mode name, with single words:
#   {Fillers: ['anyway'], Pronouns: ['yall']}
# MODE_LISTS in constants.vim maps mode names to list keys.
#
# A span is [start, end]: byte offsets in a line, 0-based, end exclusive.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import 'bartleby/variables/constants.vim' as CO

var loaded_lists: dict<dict<any>> = {}

# A word: letters, with inner apostrophes, as in don't. The classes lower
# and upper, not alpha: in Vim only these two match letters beyond ASCII,
# such as é, ß, and Cyrillic or Greek letters. Scripts without letter
# case, such as Chinese or Japanese, still match nothing here.
const WORD_PAT: string = '\v[[:lower:][:upper:]]+%([''’][[:lower:][:upper:]]+)*'

# FUNCTION: Return the word lists of the language code, or of the current
# language when code is empty, with the user's additions and removals, as
# dicts for fast lookup: {pronouns: {i: true}}. The language rules come
# with them under the key rules, see Rules. Cached after the first load.
export def Lists(code: string = ''): dict<any>
  var lang: string = code ==# '' ? LA.Code() : code
  if has_key(loaded_lists, lang)
    return loaded_lists[lang]
  endif
  var profile: dict<any> = LA.Profile(lang)
  var lists: dict<any> = {rules: Rules(profile)}
  for [key, words] in items(get(profile, 'lists', {}))
    lists[key] = ToSet(words)
  endfor
  for [mode, words] in items(get(g:, 'bartleby_spotlight_words_add', {}))
    var key: string = get(CO.MODE_LISTS, mode, '')
    if key !=# ''
      extend(lists, {[key]: extend(get(lists, key, {}), ToSet(words))})
    endif
  endfor
  for [mode, words] in items(get(g:, 'bartleby_spotlight_words_remove', {}))
    var key: string = get(CO.MODE_LISTS, mode, '')
    if key !=# '' && has_key(lists, key)
      for word in words
        if has_key(lists[key], tolower(word))
          remove(lists[key], tolower(word))
        endif
      endfor
    endif
  endfor
  loaded_lists[lang] = lists
  return lists
enddef

# FUNCTION: Forget the loaded lists, so that changed settings apply.
export def ClearLists(): void
  loaded_lists = {}
enddef

# FUNCTION: Return the span of every word in text.
export def Tokens(text: string): list<list<number>>
  var tokens: list<list<number>> = []
  var from: number = 0
  while true
    var found: list<any> = matchstrpos(text, WORD_PAT, from)
    if found[1] < 0
      break
    endif
    tokens->add([found[1], found[2]])
    from = found[2]
  endwhile
  return tokens
enddef

# FUNCTION: Return true for a contraction: a word that ends in one of the
# contraction_suffixes of the language, such as n't or 're in English, or
# in one of its conditional_contraction_suffixes after a word in the named
# list. In English, 's counts only after words such as it and that: after
# other words it usually shows possession, as in John's hat.
export def IsContraction(word: string, lists: dict<any>): bool
  var rules: dict<any> = get(lists, 'rules', {})
  var lower: string = NormalizeApostrophes(tolower(word))
  for suffix in rules.contractionSuffixes
    if HasSuffix(lower, suffix)
      return true
    endif
  endfor
  for [suffix, listKey] in items(rules.conditionalSuffixes)
    if HasSuffix(lower, suffix)
      return has_key(get(lists, listKey, {}), strpart(lower, 0, strlen(lower) - strlen(suffix)))
    endif
  endfor
  return false
enddef

# FUNCTION: Return true for a word in the adverbs list, or a word with one
# of the adverb_suffixes of the language, such as ly in English, that is
# not in adverb_exceptions, such as family or friendly. At least two
# letters must come before the suffix. A heuristic: the tagger replaces it
# when one is set.
export def IsHeuristicAdverb(word: string, lists: dict<any>): bool
  var lower: string = tolower(word)
  if has_key(get(lists, 'adverbs', {}), lower)
    return true
  endif
  if has_key(get(lists, 'adverb_exceptions', {}), lower)
    return false
  endif
  for suffix in get(lists, 'rules', {}).adverbSuffixes
    if strchars(lower) >= strchars(suffix) + 2 && HasSuffix(lower, suffix)
      return true
    endif
  endfor
  return false
enddef

# FUNCTION: Return the spans of text that mode keeps bright, by word list
# or pattern.
export def LexicalSpans(mode: string, text: string, lists: dict<any>): list<list<number>>
  var spans: list<list<number>> = []
  var key: string = get(CO.MODE_LISTS, mode, '')
  var words: dict<any> = get(lists, key, {})
  for [start, end] in Tokens(text)
    var word: string = strpart(text, start, end - start)
    var lit: bool
    if mode ==# CO.MODE_CONTRACTIONS
      lit = IsContraction(word, lists)
    elseif mode ==# CO.MODE_ADVERBS
      lit = IsHeuristicAdverb(word, lists)
    else
      # it's and they're count as pronouns and don't as an auxiliary: try the
      # word, then its base, see ContractionBase.
      var lower: string = tolower(word)
      lit = has_key(words, lower) || has_key(words, ContractionBase(lower, get(lists, 'rules', {})))
    endif
    if lit
      spans->add([start, end])
    endif
  endfor
  return spans
enddef

# FUNCTION: Return false for a line that is structure, not prose: a
# Markdown heading, and in Fountain a scene heading, character cue, or
# transition. A mode keeps nothing bright on these lines. A blank line is
# not prose either.
export def IsProseLine(text: string, filetype: string): bool
  if text !~ CO.PAT_NONBLANK
    return false
  endif
  if filetype ==# CO.FILETYPE_FOUNTAIN
    return text !~# CO.FOUNTAIN_SCENE_HEADING_PAT
      && text !~# CO.FOUNTAIN_CHAR_PAT
      && text !~# '^\s*>'
  endif
  return text !~# '^\s*#' && text !~# CO.TABLE_ROW_PAT
enddef

# FUNCTION: Return the dim positions of one line for matchaddpos: the gaps
# between the bright spans, as [lnum, col, length] with a 1-based byte
# column. Gaps of only spaces are skipped: dimming them shows no change,
# and fewer positions keep redraws fast.
export def GapPositions(lnum: number, text: string, spans: list<list<number>>): list<list<number>>
  var positions: list<list<number>> = []
  var cursor: number = 0
  for [start, end] in sort(copy(spans), (a, b) => a[0] - b[0])
    if start > cursor && strpart(text, cursor, start - cursor) =~ CO.PAT_NONBLANK
      positions->add([lnum, cursor + 1, start - cursor])
    endif
    cursor = max([cursor, end])
  endfor
  if cursor < strlen(text) && strpart(text, cursor) =~ CO.PAT_NONBLANK
    positions->add([lnum, cursor + 1, strlen(text) - cursor])
  endif
  return positions
enddef

# FUNCTION: Return the word a contraction is built on: the text before its
# contraction suffix, mapped through contraction_bases of the language when
# listed there. In English, don't gives do, can't gives can, and they're
# gives they. word is lowercase.
def ContractionBase(word: string, rules: dict<any>): string
  var lower: string = NormalizeApostrophes(word)
  for suffix in rules.contractionSuffixes + keys(rules.conditionalSuffixes)
    if HasSuffix(lower, suffix)
      var base: string = strpart(lower, 0, strlen(lower) - strlen(suffix))
      return get(rules.contractionBases, base, base)
    endif
  endfor
  return lower
enddef

# FUNCTION: Return the rules of a language file, with defaults, so that a
# language without a rule simply has none.
def Rules(profile: dict<any>): dict<any>
  return {
    adverbSuffixes: get(profile, 'adverb_suffixes', []),
    contractionSuffixes: get(profile, 'contraction_suffixes', []),
    conditionalSuffixes: get(profile, 'conditional_contraction_suffixes', {}),
    contractionBases: get(profile, 'contraction_bases', {}),
  }
enddef

# FUNCTION: Return text with the typographic apostrophe replaced by the
# straight one, which the language files use.
def NormalizeApostrophes(text: string): string
  return substitute(text, '’', "'", 'g')
enddef

# FUNCTION: Return true when word ends in suffix and is longer than it.
def HasSuffix(word: string, suffix: string): bool
  return strlen(word) > strlen(suffix) && strpart(word, strlen(word) - strlen(suffix)) ==# suffix
enddef

def ToSet(words: list<any>): dict<bool>
  var set: dict<bool> = {}
  for word in words
    set[tolower(word)] = true
  endfor
  return set
enddef
