vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lang.vim: the language of the text, and its language file. Everything
# that depends on the language of the writing comes from one file per
# language, tools/lang/<code>.json: the word lists and rules of the
# part-of-speech modes, the dialogue quotes, the spaCy model, whether the
# tagger has a passive rule, and the language code for Pandoc. See
# Localization_README.md for the format.
#
# g:bartleby_language sets the code, such as en. When it is empty, the
# code comes from v:lang, the language of Vim itself. A code without a
# language file uses English. That is silent when the code came from
# v:lang, and a warning when it was set on purpose.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/compile.vim' as MK

var log = L.New(expand('<sfile>:t'))
var langscriptpath: string = expand('<sfile>:p')
var profiles: dict<dict<any>> = {}

const FALLBACK: string = 'en'

# FUNCTION: Return the language code: g:bartleby_language when set, else
# the first two letters of v:lang, else en. v:lang is C or POSIX when no
# locale is set, which gives en.
export def Code(): string
  var setting: string = get(g:, 'bartleby_language', '')
  if setting !=# ''
    return setting
  endif
  var fromVim: string = tolower(matchstr(v:lang, '^\a\a\ze\%([_.@-]\|$\)'))
  return fromVim ==# '' ? FALLBACK : fromVim
enddef

# FUNCTION: Return the language file of code, or of the current language
# when code is empty, decoded and cached. A missing file gives the
# English one.
export def Profile(code: string = ''): dict<any>
  var lang: string = code ==# '' ? Code() : code
  if has_key(profiles, lang)
    return profiles[lang]
  endif
  var path: string = $'{PluginRoot()}/tools/lang/{lang}.json'
  if !filereadable(path)
    if lang ==# FALLBACK
      log.Error(MK.MissingLangFile(path))
      profiles[lang] = {}
      return {}
    endif
    if get(g:, 'bartleby_language', '') ==# lang
      log.Warn(MK.NoLangFile(lang, path))
    endif
    profiles[lang] = Profile(FALLBACK)
    return profiles[lang]
  endif
  try
    profiles[lang] = json_decode(join(readfile(path), "\n"))
  catch
    log.Error(MK.CannotReadLang(path))
    profiles[lang] = {}
  endtry
  return profiles[lang]
enddef

# FUNCTION: Return one value of the current language file, or fallback.
export def Get(key: string, fallback: any): any
  return get(Profile(), key, fallback)
enddef

# FUNCTION: Forget the loaded language files, so that a changed setting
# or file applies.
export def ClearCache(): void
  profiles = {}
enddef

export def PluginRoot(): string
  return fnamemodify(langscriptpath, ':h:h:h')
enddef
