vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# lexicon.vim: dictionary and thesaurus lookups: settings, keys,
# requests, and a cache, for every provider. The provider of a reference
# builds its URL and parses its response, as lexicon_mw.vim does for
# Merriam-Webster. The popups are in lexiconpopup.vim, and the result
# format in lexicon_result.vim.
#
# Each kind, dictionary and thesaurus, uses one reference of CO.REFS:
# g:bartleby_<kind>_reference when set, else the one the language file
# names. A kind is on when its reference and provider exist, curl is
# installed, and, when the provider needs a key, the key is set in
# g:bartleby_<kind>_api_key or the provider's environment variable. For
# Merriam-Webster these are $BARTLEBY_MW_DICTIONARY_KEY and
# $BARTLEBY_MW_THESAURUS_KEY. It issues one key per product, so the two
# kinds are independent.
#
# curl runs through job_start, so Vim does not wait for the network. The
# URL can contain the key, so curl reads it on stdin as a config line,
# never on the command line, where process listings show it. It is never
# logged.
#
# Parsed results are cached in memory and on disk, in
# ~/.bartleby/lexicon_cache.json, by provider, reference, and word, never
# by key. Only ok and notfound results are cached. The disk cache holds at
# most g:bartleby_lexicon_cache_max_entries results and removes the oldest
# first. 0 turns the disk cache off. CACHE_VERSION changes when the parsed
# format or the cache key changes, which discards an older cache file.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/lexicon_mw.vim' as LXM
import autoload 'bartleby/lexicon_result.vim' as LR
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/compile.vim' as MK
import 'bartleby/variables/constants.vim' as CO

const CURL: string = 'curl'
const PROVIDER_MW: string = 'merriam-webster'
const MW_DICT_KEY: string = 'BARTLEBY_MW_DICTIONARY_KEY'
const MW_THESAURUS_KEY: string = 'BARTLEBY_MW_THESAURUS_KEY'
const FLAG_MAX_TIME: string = '--max-time'
const FLAG_CONFIG: string = '--config'
const IN_IO_PIPE: string = 'pipe'
const OUT_MODE_RAW: string = 'raw'
const JOB_FAIL: string = 'fail'

var log = L.New(expand('<sfile>:t'))

var memory_cache: dict<dict<any>> = {}
var disk_cache_loaded: bool = false



const CACHE_VERSION: number = 2
var cache_max_entries: number = g:bartleby_lexicon_cache_max_entries
var timeout: number = g:bartleby_lexicon_timeout

# FUNCTION: Return the configured reference for kind, or an empty dict
# when the name is not registered or belongs to the other kind. An empty
# setting means the reference of the language file.
export def Ref(kind: string): dict<string>
  var name: string = get(g:, $'bartleby_{kind}_reference', '')
  if name ==# ''
    name = LA.Get($'{kind}_reference', '')
  endif
  var ref: dict<string> = get(CO.REFS, name, {})
  return get(ref, 'kind', '') ==# kind ? ref : {}
enddef

# FUNCTION: Return the API key for kind: the g: variable when set, else
# the environment variable of the reference's provider, else an empty
# string.
export def ApiKey(kind: string): string
  var key: string = get(g:, $'bartleby_{kind}_api_key', '')
  if key ==# ''
    var envName: string = get(get(Provider(get(Ref(kind), 'provider', '')), 'envKeys', {}), kind, '')
    key = envName ==# '' ? '' : (getenv(envName) ?? '')
  endif
  return trim(key)
enddef

# FUNCTION: Return why kind is off, or an empty string when it is on.
export def DisabledReason(kind: string): string
  var ref: dict<string> = Ref(kind)
  var provider: dict<any> = Provider(get(ref, 'provider', ''))
  if empty(ref) || empty(provider)
    var name: string = get(g:, $'bartleby_{kind}_reference', '')
    return MK.NoRefLang(KindName(kind),
      name ==# '' ? LA.Get($'{kind}_reference', '') : name)
  endif
  if provider.needsKey && ApiKey(kind) ==# ''
    var envName: string = get(provider.envKeys, kind, '')
    return MK.LookupsOffSet(KindName(kind), kind, envName)
  endif
  if !executable(CURL)
    return MK.LookupsNeedCurl(KindName(kind))
  endif
  return ''
enddef

export def IsEnabled(kind: string): bool
  return DisabledReason(kind) ==# ''
enddef

# FUNCTION: Make a lookup word from raw text: trim it, drop a possessive
# s, strip punctuation at both ends, join inner spaces, and lowercase it.
export def CleanWord(raw: string): string
  var word: string = trim(raw)
  word = substitute(word, "['’]s$", '', '')
  word = substitute(word, "^[[:punct:]“”‘’]\\+", '', '')
  word = substitute(word, "[[:punct:]“”‘’]\\+$", '', '')
  word = substitute(word, '\s\+', ' ', 'g')
  return tolower(word)
enddef

export def BuildUrl(kind: string, word: string): string
  var ref: dict<string> = Ref(kind)
  var F: func(dict<string>, string, string): string = Provider(ref.provider).buildUrl
  return F(ref, word, ApiKey(kind))
enddef

# FUNCTION: Give replacement the capitalization of original: all capitals
# when original has more than one letter and all are capitals, a capital
# first letter, or no change.
export def MatchCase(orig: string, replacement: string): string
  if strchars(orig) > 1 && orig =~# '^\u\+$'
    return toupper(replacement)
  endif
  if orig =~# '^\u'
    return toupper(strcharpart(replacement, 0, 1)) .. strcharpart(replacement, 1)
  endif
  return replacement
enddef

# FUNCTION: Parse a response body with the provider of kind's reference.
# The result follows lexicon_result.vim.
export def ParseResp(kind: string, word: string, body: string): LR.Result
  var ref: dict<string> = Ref(kind)
  var provider: dict<any> = Provider(get(ref, 'provider', ''))
  if empty(provider)
    return LR.Error(MK.NoReferenceForThis(KindName(kind)))
  endif
  var F: func(string, string, string): LR.Result = provider.parse
  return F(kind, word, body)
enddef

# FUNCTION: Look up word, already cleaned, and call Callback with the
# parsed result. A cached result also arrives through a timer, so the
# callback always runs after Lookup returns.
export def Lookup(kind: string, word: string, Callback: func(LR.Result)): void
  var reason: string = DisabledReason(kind)
  if reason !=# ''
    timer_start(0, (_) => Callback(LR.Error(reason)))
    return
  endif
  var ref: dict<string> = Ref(kind)
  var cacheKey: string = $'{ref.provider}:{ref.apiName}:{word}'
  var cached: LR.Result = CacheGet(cacheKey)
  if cached isnot null_object
    timer_start(0, (_) => Callback(cached))
    return
  endif
  StartReq(kind, word, cacheKey, Callback)
enddef

# FUNCTION: Remove every cached result, in memory and on disk.
export def ClearCache(): void
  memory_cache = {}
  disk_cache_loaded = true
  if filereadable(CachePath())
    delete(CachePath())
  endif
enddef

# FUNCTION: Return the translated name of kind, for messages.
def KindName(kind: string): string
  return kind ==# CO.KIND_THESAURUS ? MK.Thesaurus() : MK.Dict()
enddef

# FUNCTION: Return the provider name to its functions and key settings.
# To add a provider, write a script with BuildUrl and Parse, as
# lexicon_mw.vim, and add an entry here. envKeys names the environment
# variable that holds the key of each kind, when the provider needs one.
def Provider(name: string): dict<any>
  if name ==# PROVIDER_MW
    return {
      buildUrl: LXM.BuildUrl,
      parse: LXM.Parse,
      needsKey: true,
      envKeys: {
        [CO.KIND_DICT]: MW_DICT_KEY,
        [CO.KIND_THESAURUS]: MW_THESAURUS_KEY,
      },
    }
  endif
  return {}
enddef

def StartReq(kind: string, word: string, cacheKey: string,
    Callback: func(LR.Result)): void
  var out: list<string> = []
  var err: list<string> = []
  var state: dict<any> = {closed: false, exited: false, done: false, code: -1}

  # Output is complete only after both callbacks: exit_cb can arrive while
  # output is still waiting in the channel.
  var Finish = () => {
    if !state.closed || !state.exited || state.done
      return
    endif
    state.done = true
    if state.code != 0
      var detail: string = empty(err) ? MK.ExitCode(state.code) : trim(split(join(err, ''), "\n")[0])
      Callback(LR.Error(MK.LookupFailed(detail)))
      return
    endif
    var result: LR.Result = ParseResp(kind, word, join(out, ''))
    if result.status !=# CO.STATUS_ERR
      CachePut(cacheKey, result)
    endif
    Callback(result)
  }

  var job: job = job_start(['curl', '--silent', '--show-error',
      FLAG_MAX_TIME, string(timeout), FLAG_CONFIG, '-'], {
    in_io: IN_IO_PIPE,
    out_mode: OUT_MODE_RAW,
    err_mode: OUT_MODE_RAW,
    out_cb: (_, msg) => {
      out->add(msg)
    },
    err_cb: (_, msg) => {
      err->add(msg)
    },
    close_cb: (_) => {
      state.closed = true
      Finish()
    },
    exit_cb: (_, code) => {
      state.exited = true
      state.code = code
      Finish()
    },
  })
  if job_status(job) ==# JOB_FAIL
    Callback(LR.Error(MK.CouldNotStart()))
    return
  endif
  ch_sendraw(job, $'url = "{BuildUrl(kind, word)}"' .. "\n")
  ch_close_in(job)
enddef

def CachePath(): string
  return expand('~/.bartleby/lexicon_cache.json')
enddef

def LoadDiskCache(): void
  if disk_cache_loaded
    return
  endif
  disk_cache_loaded = true
  if cache_max_entries <= 0 || !filereadable(CachePath())
    return
  endif
  try
    var data: any = json_decode(join(readfile(CachePath()), "\n"))
    if type(data) == v:t_dict && get(data, 'version', 0) == CACHE_VERSION
      memory_cache = extend(get(data, 'entries', {}), memory_cache)
    endif
  catch
    log.Warn(MK.IgnoringUnreadableLexicon(CachePath()))
  endtry
enddef

def CacheGet(key: string): LR.Result
  LoadDiskCache()
  return has_key(memory_cache, key) ? LR.Result.FromDict(memory_cache[key].result) : null_object
enddef

def CachePut(key: string, result: LR.Result): void
  memory_cache[key] = {time: localtime(), result: result.ToDict()}
  var limit: number = cache_max_entries
  if limit <= 0
    return
  endif
  if len(memory_cache) > limit
    var excess: number = len(memory_cache) - limit
    var oldestFirst: list<string> = keys(memory_cache)
      ->sort((a, b) => memory_cache[a].time - memory_cache[b].time)
    for staleKey in oldestFirst[0 : excess - 1]
      remove(memory_cache, staleKey)
    endfor
  endif
  try
    mkdir(fnamemodify(CachePath(), ':h'), 'p')
    writefile([json_encode({version: CACHE_VERSION, entries: memory_cache})], CachePath())
  catch
    log.Warn(MK.CouldNotWrite(CachePath()))
  endtry
enddef
