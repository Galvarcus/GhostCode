vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# tagger.vim: runs the part-of-speech tagger for Spotlight's Nouns,
# Verbs, Adjectives, and Passive modes, and for the tagged versions of
# the other part-of-speech modes.
#
# g:bartleby_spotlight_tagger selects the tagger:
#   ''        No tagger, the default. The tagger-only modes are hidden.
#   'spacy'   tools/pos/spacy_tagger.py, run with python3, with the model
#             in g:bartleby_spotlight_spacy_model, else the model of
#             the language file, see lang.vim.
#   [cmd...]  Any command with the same protocol. See the header of
#             tools/pos/spacy_tagger.py.
#
# The tagger starts when first needed and keeps running, because loading
# a language model takes a second or more. It receives one paragraph at a
# time. Results are cached by the SHA-256 hash of the paragraph text, so
# an unchanged paragraph is never sent again, and an edit sends only its
# own paragraph. Results arrive asynchronously. OnUpdate sets the
# function to call then, which is Spotlight's redraw.
#
# When the tagger cannot start or exits, the last line of its error
# output is logged once, and IsReady stays false for the session.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/compile.vim' as MK
import 'bartleby/variables/constants.vim' as CO

const SETTING_SPACY: string = 'spacy'
const MODEL_KEY: string = 'spacy_model'
const SPACY_SCRIPT: string = 'tools/pos/spacy_tagger.py'
# The programs that run a Python 3 script, in the order to try. Windows
# installs python.exe and the py launcher, and carries python3.exe only as
# the alias of a Microsoft Store install, which the documentation of
# Python names as a program that may not be there. That documentation
# gives py as the way to choose a version.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/54
const PYTHONS: list<list<string>> = [['python3'], ['python'], ['py', '-3']]
const JOB_RUN: string = 'run'
const IN_MODE_NL: string = 'nl'

var log = L.New(expand('<sfile>:t'))

var tagger_job: job = null_job
var failed: bool = false
var failure_reason: string = ''
var next_id: number = 1
# Request id to paragraph hash, for requests not answered yet.
var pending: dict<string> = {}
# Paragraph hash to {tokens: [[start, end, tag]],
#                    passive: [[start, end]]}.
var cache: dict<dict<any>> = {}
var stderr_lines: list<string> = []
var generation: number = 0
var OnUpdateFn: func() = null_function

const CACHE_LIMIT: number = 5000

# FUNCTION: Return the first of cmds whose program exists, or an empty
# list when none does. Each item is a program and its flags, so the flags
# travel with the program that takes them. Exported for its own test,
# which cannot ask Vim to forget a program that this system has.
export def FirstRunnable(cmds: list<list<string>>): list<string>
  for cmd in cmds
    if !empty(cmd) && executable(cmd[0])
      return cmd
    endif
  endfor
  return []
enddef

# FUNCTION: Return the tagger command, or an empty list when none is set.
export def Command(): list<string>
  var setting: any = get(g:, 'bartleby_spotlight_tagger', '')
  if type(setting) == v:t_list
    return setting
  endif
  if setting ==# SETTING_SPACY
    # An empty model setting means the model of the language file. A
    # language without one has no tagger.
    var model: string = get(g:, 'bartleby_spotlight_spacy_model', '')
    if model ==# ''
      model = LA.Get(MODEL_KEY, '')
    endif
    var python: list<string> = FirstRunnable(PYTHONS)
    if model ==# '' || empty(python)
      return []
    endif
    return python + [$'{LA.PluginRoot()}/{SPACY_SCRIPT}', model]
  endif
  return []
enddef

# FUNCTION: Return true when a tagger is set, its program exists, and it
# has not failed.
export def IsReady(): bool
  var cmd: list<string> = Command()
  return !failed && !empty(cmd) && executable(cmd[0])
enddef

export def FailureReason(): string
  return failure_reason
enddef

# FUNCTION: Return a number that changes with each result, so that
# callers know to rebuild.
export def Generation(): number
  return generation
enddef

export def OnUpdate(Fn: func()): void
  OnUpdateFn = Fn
enddef

# FUNCTION: Return the tags of text, one paragraph with its lines joined
# by line breaks: a dict of tokens and passive with byte offsets into
# text. When they are not cached yet, request them and return an empty
# dict.
export def Tags(text: string): dict<any>
  var hash: string = sha256(text)
  if has_key(cache, hash)
    return cache[hash]
  endif
  # No requests while you type: each key changes the paragraph, and one
  # request per key would queue faster than the tagger answers. The
  # paragraph is tagged when you leave Insert mode.
  if !IsReady() || index(values(pending), hash) >= 0 || mode() =~# CO.PAT_INSERT
    return {}
  endif
  if !Start()
    return {}
  endif
  var id: number = next_id
  next_id += 1
  pending[string(id)] = hash
  ch_sendraw(tagger_job, json_encode({id: id, text: text}) .. "\n")
  return {}
enddef

export def Stop(): void
  if job_status(tagger_job) ==# JOB_RUN
    job_stop(tagger_job)
  endif
  tagger_job = null_job
  pending = {}
enddef

# FUNCTION: Stop the tagger and forget its results and any failure, so
# that a changed g:bartleby_spotlight_tagger applies.
export def Reset(): void
  Stop()
  failed = false
  failure_reason = ''
  cache = {}
  generation += 1
enddef

def Start(): bool
  if job_status(tagger_job) ==# JOB_RUN
    return true
  endif
  stderr_lines = []
  tagger_job = job_start(Command(), {
    in_mode: IN_MODE_NL,
    out_mode: IN_MODE_NL,
    err_mode: IN_MODE_NL,
    out_cb: (_, line) => OnReply(line),
    err_cb: (_, line) => {
      stderr_lines->add(line)
    },
    exit_cb: (j, code) => OnExit(j, code),
  })
  if job_status(tagger_job) !=# JOB_RUN
    Fail(MK.TaggerCmdCould(join(Command(), ' ')))
    return false
  endif
  return true
enddef

def OnReply(line: string): void
  var reply: any
  try
    reply = json_decode(line)
  catch
    return
  endtry
  if type(reply) != v:t_dict
    return
  endif
  var key: string = string(get(reply, 'id', ''))
  if !has_key(pending, key)
    return
  endif
  if len(cache) >= CACHE_LIMIT
    cache = {}
  endif
  cache[pending[key]] = {
    tokens: get(reply, 'tokens', []),
    passive: get(reply, 'passive', []),
  }
  remove(pending, key)
  generation += 1
  if OnUpdateFn != null_function
    OnUpdateFn()
  endif
enddef

def OnExit(exited: job, code: number): void
  # A job that Stop ended is no longer the current job, so its exit is not
  # a failure.
  if exited != tagger_job
    return
  endif
  if code != 0 && !failed
    var detail: string = empty(stderr_lines) ? MK.ExitCode(code) : stderr_lines[-1]
    Fail(MK.PartSpeechTagger(detail))
  endif
  tagger_job = null_job
  pending = {}
enddef

def Fail(reason: string): void
  failed = true
  failure_reason = reason
  log.Error(reason)
  generation += 1
  if OnUpdateFn != null_function
    OnUpdateFn()
  endif
enddef
