vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

import 'bartleby/variables/constants.vim' as CO

##############################################################################
# Plugin_Name: Bartleby
# lexicon_result.vim: the result of a dictionary or thesaurus lookup, the
# contract between lexicon.vim, every provider, and lexiconpopup.vim.
# License: GNU GPL 3.0
##############################################################################

# CLASS: A lookup result. A class, so that a mistyped field is an error when
# Vim compiles the code that reads it, not a silent default when it runs.
# status is ok, notfound, or error. entries holds the entries for status ok:
# dictionary entries {headword, display, fl, defs}, or thesaurus entries
# {headword, fl, senses, ants}, where senses is a list of {label, syns}.
# display is the headword as shown, fl the part of speech as text, defs a
# list of short definitions, label a short definition of the sense, and
# syns and ants lists of words. suggestions holds spelling suggestions for
# status notfound, and message the error text for status error. A result
# never changes, so its fields can be read but not set from outside.
export class Result
  var status: string
  var entries: list<dict<any>>
  var suggestions: list<any>
  var message: string

  def new(this.status, this.entries, this.suggestions, this.message)
  enddef

  # METHOD: Return the result as a dict, for the cache on disk, which is
  # JSON. The keys are the field names, as they have always been on disk.
  def ToDict(): dict<any>
    return {status: this.status, entries: this.entries, suggestions: this.suggestions, message: this.message}
  enddef

  # METHOD: Return the result that ToDict made, tolerating a missing key.
  static def FromDict(src: dict<any>): Result
    return Result.new(get(src, 'status', CO.STATUS_ERR), get(src, 'entries', []),
      get(src, 'suggestions', []), get(src, 'message', ''))
  enddef
endclass

# FUNCTION: Return a result with entries.
export def Ok(entries: list<dict<any>>): Result
  return Result.new(CO.STATUS_OK, entries, [], '')
enddef

# FUNCTION: Return a result for a word that was not found, with optional
# spelling suggestions.
export def NotFound(suggestions: list<any> = []): Result
  return Result.new(CO.STATUS_NOTFOUND, [], suggestions, '')
enddef

# FUNCTION: Return a result for a failed lookup.
export def Error(message: string): Result
  return Result.new(CO.STATUS_ERR, [], [], message)
enddef
