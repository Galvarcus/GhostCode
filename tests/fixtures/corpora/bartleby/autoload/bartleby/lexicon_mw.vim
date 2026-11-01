vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexicon_mw.vim: the Merriam-Webster provider for lexicon.vim, through
# dictionaryapi.com. A provider is a script with two functions:
#   BuildUrl(ref, word, key)  The request URL for word, already cleaned.
#                             ref is the entry of CO.REFS.
#   Parse(kind, word, body)   The result, see lexicon_result.vim, from
#                             the response body.
# lexicon.vim registers each provider in its Provider function. See
# Localization_README.md for adding one.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lexicon_result.vim' as LR
import autoload 'bartleby/locale/compile.vim' as MK
import 'bartleby/variables/constants.vim' as CO

const PAT_CHARS: string = '\zs'
const URL_ESCAPE: string = '%%%02X'
var base_url: string = g:bartleby_lexicon_base_url

# FUNCTION: Return the request URL. g:bartleby_lexicon_base_url replaces
# the Merriam-Webster address, for a proxy or a test server.
export def BuildUrl(ref: dict<string>, word: string, key: string): string
  var base: string = substitute(base_url, '/\+$', '', '')
  return $'{base}/{ref.apiName}/json/{UrlEncode(word)}?key={key}'
enddef

# FUNCTION: Parse a Merriam-Webster response body. A list of strings means
# not found, with spelling suggestions. Merriam-Webster answers a bad key
# with plain text, not JSON: that becomes an error with its first line.
export def Parse(kind: string, word: string, body: string): LR.Result
  var text: string = trim(body)
  if text ==# ''
    return LR.Error(MK.EmptyRespMerriam())
  endif
  var data: any
  try
    data = json_decode(text)
  catch
    return LR.Error(MK.MerriamWebster(strcharpart(split(text, "\n")[0], 0, 120)))
  endtry
  if type(data) != v:t_list
    return LR.Error(MK.UnexpectedRespMerriam())
  endif
  if empty(data) || data->copy()->filter((_, v) => type(v) != v:t_string)->empty()
    return LR.NotFound(data)
  endif

  var raw: list<dict<any>> = data->copy()->filter((_, v) => type(v) == v:t_dict)
  var matching: list<dict<any>> = raw->copy()->filter((_, e) => IsEntryFor(e, word))
  var chosen: list<dict<any>> = empty(matching) ? raw : matching
  var entries: list<dict<any>> = kind ==# CO.KIND_THESAURUS
    ? chosen->mapnew((_, e) => ThesaurusEntry(e))
    : chosen->mapnew((_, e) => DictEntry(e))
  entries = entries->filter((_, e) => !empty(e))
  return empty(entries) ? LR.NotFound() : LR.Ok(entries)
enddef

# FUNCTION: Percent-encode every byte outside the RFC 3986 unreserved set.
export def UrlEncode(text: string): string
  var encoded: string = ''
  for ch in split(text, PAT_CHARS)
    if ch =~# '^[A-Za-z0-9._~-]$'
      encoded ..= ch
    else
      for byte in str2blob([ch])
        encoded ..= printf(URL_ESCAPE, byte)
      endfor
    endif
  endfor
  return encoded
enddef

def StripSyllables(headword: string): string
  return substitute(headword, '\*', '', 'g')
enddef

def IsEntryFor(entry: dict<any>, word: string): bool
  var meta: dict<any> = get(entry, 'meta', {})
  var stems: list<any> = get(meta, 'stems', [])
  if index(stems->mapnew((_, s) => tolower(s)), word) >= 0
    return true
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', '')
  return tolower(StripSyllables(hw)) ==# word
enddef

def DictEntry(entry: dict<any>): dict<any>
  var defs: list<any> = get(entry, 'shortdef', [])->filter((_, d) => type(d) == v:t_string)
  if empty(defs)
    return {}
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', get(get(entry, 'meta', {}), 'id', ''))
  return {
    headword: StripSyllables(hw),
    display: substitute(hw, '\*', '·', 'g'),
    fl: get(entry, 'fl', ''),
    defs: defs,
  }
enddef

def ThesaurusEntry(entry: dict<any>): dict<any>
  var meta: dict<any> = get(entry, 'meta', {})
  var synLists: list<any> = get(meta, 'syns', [])
  var shortdefs: list<any> = get(entry, 'shortdef', [])
  var senses: list<dict<any>> = []
  for i in range(len(synLists))
    if !empty(synLists[i])
      senses->add({label: get(shortdefs, i, ''), syns: synLists[i]})
    endif
  endfor
  var ants: list<any> = flattennew(get(meta, 'ants', []))->uniq()
  if empty(senses) && empty(ants)
    return {}
  endif
  var hw: string = get(get(entry, 'hwi', {}), 'hw', get(meta, 'id', ''))
  return {
    headword: StripSyllables(hw),
    fl: get(entry, 'fl', ''),
    senses: senses,
    ants: ants,
  }
enddef
