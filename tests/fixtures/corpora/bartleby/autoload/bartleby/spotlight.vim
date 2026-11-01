vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# spotlight.vim: Spotlight, which dims the text outside the current
# paragraph or outside what a mode selects. Converted from Limelight,
# github.com/junegunn/limelight.vim, to a Vim9 class. Use it together
# with Focus: Focus arranges the windows, Spotlight dims the text.
#
# A mode returns what to dim, never what to keep bright. An earlier
# version dimmed everything with one match and restored the bright part
# with a second, higher-priority match. That broke syntax highlighting
# in the bright part: any matchadd match that sets a color hides the
# syntax color below it, at any priority, and a match with every
# attribute NONE only lets the next match, the dim one, win. So, as in
# Limelight, only the dimmed text gets a match, and the bright text
# keeps its syntax colors because no match covers it.
#
# Paragraph mode dims everything before and after the paragraph with one
# regex, as Limelight does. Every other mode keeps scattered spans
# bright, such as quoted speech or the words of one part of speech. It
# computes the dim gaps between the spans and applies them with
# matchaddpos. A regex with one alternative per gap redraws too slowly:
# with 1,100 gaps, 157 ms per redraw as a regex, 1 ms as positions.
#
# Part-of-speech modes take their words from word lists and patterns in
# pos.vim, or from a part-of-speech tagger when one is set, in
# tagger.vim. Nouns, Verbs, Adjectives, and Passive need the tagger and
# are hidden without one.
#
# The color math in Dim, Hex2Rgb, GrayContiguous, GrayAnsi, and
# ValidateCoeff is Limelight's GUI and 256-color blending, unchanged.
#
# Not converted: Limelight's fixed range from an operator or Visual mode.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/pos.vim' as POS
import autoload 'bartleby/tagger.vim' as TA
import autoload 'bartleby/tty.vim' as TY
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/locale/writing.vim' as MW
import 'bartleby/variables/constants.vim' as CO

const NOUNS: string = 'Nouns'
const VERBS: string = 'Verbs'
const ADJECTIVES: string = 'Adjectives'
const PRONOUNS: string = 'Pronouns'
const DETERMINERS: string = 'Determiners'
const PREPOSITIONS: string = 'Prepositions'
const CONJUNCTIONS: string = 'Conjunctions'
const AUXILIARIES: string = 'Auxiliaries'
const FILLERS: string = 'Fillers'
const PROPN: string = 'PROPN'
const SCONJ: string = 'SCONJ'
const PASSIVE_KEY: string = 'tagger_passive'
const SEARCH_BACK_HERE: string = 'cbW'
const SEARCH_BACK: string = 'bW'
const WIN_TOP: string = 'w0'
const DIALOGUE_KEY: string = 'dialogue_pattern'
const HEX_FMT: string = '%02x'
const HL_DIM: string = 'SpotlightDim'

var log = L.New(expand('<sfile>:t'))
var default_coefficient: float = g:bartleby_spotlight_default_coefficient
var conceal_guifg: string = g:bartleby_spotlight_conceal_guifg
# A terminal color is a number, which a user may write without quotes.
var spotlightconcealctermfg: string = $'{g:bartleby_spotlight_conceal_ctermfg}'
var bop: string = g:bartleby_spotlight_bop
var eop: string = g:bartleby_spotlight_eop
var para_span: number = g:bartleby_spotlight_paragraph_span
var priority: number = g:bartleby_spotlight_priority

##############################################################################
# SECTION: Mode registry. A handler takes the mode name and returns what
# to dim, never the text that stays bright:
#   {key: string, pattern: string}          a regex, for Paragraph
#   {key: string, positions: list<any>}     positions for matchaddpos
# key identifies the result, so an unchanged result is not applied again.
# Handlers are plain functions that receive the mode name, not closures.
##############################################################################

const MODE_PARA: string = 'Paragraph'
const MODE_DIALOGUE: string = 'Dialogue'
const MODE_PASSIVE: string = 'Passive'

var mode_handlers: dict<func(string): dict<any>> = {}
var mode_available: dict<func(): bool> = {}
var mode_order: list<string> = []

# The last positions per buffer. The key covers the mode, the text, the
# window range, and the tagger results. See CachedPositions.
var span_cache: dict<dict<any>> = {}
const SPOTLIGHT_DIALOGUE_WIN_MARGIN: number = 200
const SPOTLIGHT_POS_WIN_MARGIN: number = 50
# How far past the window edge a paragraph is followed, so that a
# paragraph cut by the edge is still classified as a whole.
const SPOTLIGHT_PARA_LIMIT: number = 200

# The part-of-speech modes in picker order, and the Universal POS tags
# that keep a word bright when a tagger is set. An empty list means the
# mode always uses its word list or pattern, see pos.vim. Nouns, Verbs,
# Adjectives, and Passive have no word list, so they need the tagger.
const POS_MODES: list<string> = [
  NOUNS, VERBS, ADJECTIVES, CO.MODE_ADVERBS, PRONOUNS, DETERMINERS,
  PREPOSITIONS, CONJUNCTIONS, AUXILIARIES, CO.MODE_CONTRACTIONS, FILLERS,
]
const POS_TAGS: dict<list<string>> = {
  Nouns: ['NOUN', PROPN],
  Verbs: ['VERB'],
  Adjectives: ['ADJ'],
  Adverbs: ['ADV'],
  Pronouns: ['PRON'],
  Determiners: ['DET'],
  Prepositions: ['ADP'],
  Conjunctions: ['CCONJ', SCONJ],
  Auxiliaries: ['AUX'],
  Contractions: [],
  Fillers: [],
}
const TAGGER_ONLY_MODES: list<string> = ['Nouns', 'Verbs', 'Adjectives', 'Passive']

const GRAY_CONVERTER: dict<number> = {0: 231, 7: 254, 15: 256, 16: 231, 231: 256}

var cur_mode: string = MODE_PARA
var cur_coeff: float = -1.0
var dialogue_pat: string = g:bartleby_spotlight_dialogue_pattern

def RegisterMode(name: string, Handler: func(string): dict<any>,
    Available: func(): bool): void
  if !has_key(mode_handlers, name)
    mode_order->add(name)
  endif
  mode_handlers[name] = Handler
  mode_available[name] = Available
enddef

# FUNCTION: Return every mode usable now, in registration order, for the
# mode picker and to check a :BartlebySpotlight argument.
export def AvailableModes(): list<string>
  return mode_order->copy()->filter((_, name) => mode_available[name]())
enddef

def IsModeAvailable(name: string): bool
  return has_key(mode_handlers, name) && mode_available[name]()
enddef

def Always(): bool
  return true
enddef

def TaggerReady(): bool
  return TA.IsReady()
enddef

# FUNCTION: Return true when the tagger is ready and the language file
# declares that the tagger has a passive rule for the language.
def PassiveReady(): bool
  return TA.IsReady() && LA.Get(PASSIVE_KEY, false)
enddef

# FUNCTION: Return true when mode takes its words from the tagger now.
def UsesTagger(mode: string): bool
  return mode ==# MODE_PASSIVE || (!empty(get(POS_TAGS, mode, [])) && TA.IsReady())
enddef

# FUNCTION: Return a regex for everything before and after the paragraph
# with the cursor, as Limelight's getpos and hl do.
# g:bartleby_spotlight_paragraph_span, Limelight's paragraph_span, keeps
# that many more paragraphs bright on each side.
def ParaPat(): string
  var emptyAdjust: number = getline('.') =~# '^\s*$' ? 1 : 0
  var span: number = max([0, para_span - emptyAdjust])

  var pos: list<number> = getcurpos()
  var start: number = 0
  for i in range(0, span)
    start = searchpos(bop, i == 0 ? SEARCH_BACK_HERE : SEARCH_BACK)[0]
  endfor
  setpos('.', pos)

  var endLine: number = 0
  for _ in range(0, span)
    endLine = searchpos(eop, 'W')[0]
  endfor
  setpos('.', pos)

  # When bop never matched, start is 0 and the cursor paragraph is the
  # first in the buffer. The pattern for line 0 then matches nothing, which
  # is harmless, so it needs no special case. Limelight uses the same trick.
  var pats: list<string> = [$'\%<{start}l.']
  if endLine > 0
    pats->add($'\%>{endLine}l.')
  endif
  return join(pats, '\|')
enddef

# FUNCTION: Return the first and last line of the visible window, widened
# by margin lines on each side.

def VisibleLineRange(margin: number): list<number>
  return [max([1, line(WIN_TOP) - margin]), min([line('$'), line('w$') + margin])]
enddef

def ParaSpec(mode: string): dict<any>
  var pattern: string = ParaPat()
  return {key: $'{mode}:{pattern}', pattern: pattern}
enddef

# FUNCTION: Return the positions of mode for the window range, reused
# while the buffer text, the range, and the tagger results do not change.
def CachedPositions(mode: string, margin: number,
    Compute: func(string, number, number): list<any>): dict<any>
  var bufNr: number = bufnr('%')
  var [first: number, last: number] = VisibleLineRange(margin)
  # Insert mode is part of the key: the tagger sends no requests while you
  # type, so a result computed in Insert mode must not be reused after it.
  var typing: string = mode() =~# '^[iR]' ? 'i' : 'n'
  var key: string = $'{mode}:{bufNr}:{b:changedtick}:{first}:{last}:{TA.Generation()}:{typing}'
  var cached: dict<any> = get(span_cache, bufNr, {})
  if get(cached, 'key', '') ==# key
    return cached
  endif
  var spec: dict<any> = {key: key, positions: Compute(mode, first, last)}
  span_cache[bufNr] = spec
  return spec
enddef

# The most line results that the line cache keeps before it starts again:
# enough for every line of a long manuscript in a few modes.
const CACHE_MAX: number = 20000

# CLASS: Remembers the dim positions of each line text, so that a refresh
# recomputes only the lines that changed or came into view. Typing changes
# one line and scrolling brings a few into view, while the whole window
# cache of CachedPositions misses on both. The positions are kept with line
# number 0 and get the real number when used, so an entry stays valid when
# lines above it are added or removed. New word lists, as from another
# language, start the cache again.
class LineCache
  var _items: dict<list<any>> = {}
  var _size: number = 0
  var _lists: dict<any> = {}

  # METHOD: Return the dim positions of text on line lnum. kind names what
  # the positions depend on besides the text, such as the mode or the
  # dialogue pattern. Compute makes them, for line number 0, on a miss.
  def Get(kind: string, lnum: number, text: string,
      Compute: func(string): list<any>): list<any>
    var key: string = kind .. "\n" .. text
    if !has_key(this._items, key)
      if this._size >= CACHE_MAX
        this._items = {}
        this._size = 0
      endif
      this._items[key] = Compute(text)
      this._size += 1
    endif
    return this._items[key]->mapnew((_, p) => [lnum] + p[1 :])
  enddef

  # METHOD: Start again when the word lists are not the ones that the
  # cached positions were made with.
  def UseLists(lists: dict<any>): void
    if lists isnot this._lists
      this._items = {}
      this._size = 0
      this._lists = lists
    endif
  enddef
endclass

var line_cache: LineCache = LineCache.new()

# FUNCTION: Return the dim position for a whole nonblank line.
def WholeLine(lnum: number, text: string): list<any>
  return text =~ CO.PAT_NONBLANK ? [[lnum]] : []
enddef

# FUNCTION: Dialogue mode. Dims everything except quoted speech, in
# straight or curly double quotes, the usual form of direct speech in
# English prose. The quoted spans get no match, so they keep their syntax
# colors. A quote does not continue across lines: speech that runs past a
# paragraph break usually reopens its quote, which this does not handle.
# g:bartleby_spotlight_dialogue_pattern sets another quote pattern, for
# example for guillemets. The result is computed for the visible window
# plus a margin and cached per buffer, see CachedPositions. CursorMoved
# and WinScrolled recompute it, so text is ready before it scrolls into
# view.
def DialogueSpec(mode: string): dict<any>
  return CachedPositions(mode, SPOTLIGHT_DIALOGUE_WIN_MARGIN, DialoguePositions)
enddef

def DialoguePositions(mode: string, first: number, last: number): list<any>
  return &filetype ==# CO.FILETYPE_FOUNTAIN ? FountainDialoguePositions(first, last)
    : ProseDialoguePositions(first, last)
enddef

# FUNCTION: Return the dialogue pattern: g:bartleby_spotlight_dialogue_pattern
# when set, else the dialogue quotes of the language file. Read on each
# use, not when this script loads, so that a changed language applies.
def DialoguePat(): string
  return dialogue_pat !=# '' ? dialogue_pat
    : LA.Get(DIALOGUE_KEY, '"[^"]*"')
enddef

def ProseDialoguePositions(first: number, last: number): list<any>
  var pattern: string = DialoguePat()
  var positions: list<any> = []
  for lnum in range(first, last)
    positions += line_cache.Get('dialogue:' .. pattern, lnum, getline(lnum),
      (text: string): list<any> => DialogueLine(text, pattern))
  endfor
  return positions
enddef

# FUNCTION: Return the dim positions of one prose line in Dialogue mode,
# for line number 0: the text outside the quotes, or the whole line when it
# has none.
def DialogueLine(text: string, pattern: string): list<any>
  var spans: list<list<number>> = []
  var from: number = 0
  while true
    var found: list<any> = matchstrpos(text, pattern, from)
    if found[1] < 0 || found[2] <= found[1]
      break
    endif
    spans->add([found[1], found[2]])
    from = found[2]
  endwhile
  return empty(spans) ? WholeLine(0, text) : POS.GapPositions(0, text, spans)
enddef

# FUNCTION: Return true for a Fountain character cue: a line in capitals,
# optionally with a parenthetical such as V.O., that is not a scene
# heading. Fountain dialogue has no quotes. The lines after a cue, up to
# the next blank line, are spoken dialogue.
def IsFountainCharCue(text: string): bool
  if text ==# '' || text =~# CO.FOUNTAIN_SCENE_HEADING_PAT
    return false
  endif
  return text =~# CO.FOUNTAIN_CHAR_PAT
enddef

def FountainDialoguePositions(first: number, last: number): list<any>
  var positions: list<any> = []
  var total: number = line('$')

  # A dialogue block spans several lines: the cue, then the lines after it.
  # A window that starts inside a block never sees its cue, so it would
  # treat those lines as narration. Look back from first to check.
  var lnum: number = first
  var back: number = first - 1
  while back >= 1 && getline(back) !=# ''
    if IsFountainCharCue(getline(back))
      var dEnd: number = back + 1
      while dEnd <= total && getline(dEnd) !=# ''
        dEnd += 1
      endwhile
      lnum = dEnd
      break
    endif
    back -= 1
  endwhile

  while lnum <= last
    var text: string = getline(lnum)
    positions += WholeLine(lnum, text)
    if IsFountainCharCue(text)
      # The cue line dims, because it is not spoken. The lines after it are
      # the bright dialogue.
      lnum += 1
      while lnum <= total && getline(lnum) !=# ''
        lnum += 1
      endwhile
    else
      lnum += 1
    endif
  endwhile
  return positions
enddef

def PosSpec(mode: string): dict<any>
  return CachedPositions(mode, SPOTLIGHT_POS_WIN_MARGIN, PosPositions)
enddef

# FUNCTION: Keep the words of the part of speech mode bright and dim the
# rest of each prose line. Structure lines, such as headings and Fountain
# cues, dim completely. The range is widened to whole paragraphs, so the
# tagger always sees complete sentences and each paragraph keeps one
# cache entry.
def PosPositions(mode: string, first: number, last: number): list<any>
  var ft: string = &filetype
  var total: number = line('$')
  var start: number = first
  while start > 1 && first - start < SPOTLIGHT_PARA_LIMIT
      && POS.IsProseLine(getline(start - 1), ft)
    start -= 1
  endwhile
  var stop: number = last
  while stop < total && stop - last < SPOTLIGHT_PARA_LIMIT
      && POS.IsProseLine(getline(stop + 1), ft)
    stop += 1
  endwhile

  var tagged: bool = UsesTagger(mode)
  var lists: dict<any> = tagged ? {} : POS.Lists()
  var positions: list<any> = []
  var lnum: number = start
  while lnum <= stop
    var text: string = getline(lnum)
    if !POS.IsProseLine(text, ft)
      positions += WholeLine(lnum, text)
      lnum += 1
      continue
    endif
    var blockStart: number = lnum
    var lines: list<string> = []
    while lnum <= stop && POS.IsProseLine(getline(lnum), ft)
      lines->add(getline(lnum))
      lnum += 1
    endwhile
    positions += tagged ? TaggedPositions(mode, blockStart, lines)
      : LexicalPositions(mode, blockStart, lines, lists)
  endwhile
  return positions
enddef

def LexicalPositions(mode: string, blockStart: number, lines: list<string>,
    lists: dict<any>): list<any>
  line_cache.UseLists(lists)
  var positions: list<any> = []
  for i in range(len(lines))
    positions += line_cache.Get(mode, blockStart + i, lines[i],
      (text: string): list<any> => POS.GapPositions(0, text, POS.LexicalSpans(mode, text, lists)))
  endfor
  return positions
enddef

# FUNCTION: Return the positions from the tagger results for one
# paragraph. While the results are not ready, the paragraph stays
# undimmed, and the tagger update redraws it later.
def TaggedPositions(mode: string, blockStart: number, lines: list<string>): list<any>
  var tags: dict<any> = TA.Tags(join(lines, "\n"))
  if empty(tags)
    return []
  endif
  var spans: list<any>
  if mode ==# MODE_PASSIVE
    spans = tags.passive
  else
    var wanted: list<string> = POS_TAGS[mode]
    spans = tags.tokens->copy()->filter((_, t) => index(wanted, t[2]) >= 0)
  endif

  # Convert paragraph byte offsets to spans per line. A span across a line
  # break, such as a passive that starts on one line and ends on the next,
  # is split there.
  var perLine: list<list<list<number>>> = []
  var starts: list<number> = []
  var offset: number = 0
  for text in lines
    perLine->add([])
    starts->add(offset)
    offset += strlen(text) + 1
  endfor
  for span in spans
    for i in range(len(lines))
      var lineStart: number = starts[i]
      var lineEnd: number = lineStart + strlen(lines[i])
      if span[0] < lineEnd && span[1] > lineStart
        perLine[i]->add([max([span[0], lineStart]) - lineStart, min([span[1], lineEnd]) - lineStart])
      endif
    endfor
  endfor

  var positions: list<any> = []
  for i in range(len(lines))
    positions += POS.GapPositions(blockStart + i, lines[i], perLine[i])
  endfor
  return positions
enddef

RegisterMode(MODE_PARA, ParaSpec, Always)
RegisterMode(MODE_DIALOGUE, DialogueSpec, Always)
for posMode in POS_MODES
  RegisterMode(posMode, PosSpec, index(TAGGER_ONLY_MODES, posMode) >= 0 ? TaggerReady : Always)
endfor
RegisterMode(MODE_PASSIVE, PosSpec, PassiveReady)

##############################################################################
# SECTION: Color math, Limelight's hex2rgb and dim, unchanged. Blends the
# Normal foreground toward its background by coeff, from 0.0 for no dim to
# 1.0 for the background color, for a smooth dim in true color and 256
# colors instead of a fixed highlight group.
##############################################################################
# FUNCTION: Convert a hex color string to a list of red, green, and blue.

def Hex2Rgb(str: string): list<number>
  var hex: string = substitute(str, '^#', '', '')
  return [str2nr(hex[0 : 1], 16), str2nr(hex[2 : 3], 16), str2nr(hex[4 : 5], 16)]
enddef

def GrayContiguous(col: number): number
  var val: number = get(GRAY_CONVERTER, col, col)
  if val < 231 || val > 256
    throw Unsupported()
  endif
  return val
enddef

def GrayAnsi(col: number): number
  if col ==# 231
    return 0
  elseif col ==# 256
    return 231
  endif
  return col
enddef

def ValidateCoeff(coeff: float): float
  var c: float = coeff < 0 ? default_coefficient : coeff
  if c < 0 || c > 1
    throw MW.InvalidSpotlightDefault()
  endif
  return c
enddef

def Unsupported(): string
  var isGui: bool = has('gui_running')
  var varName: string = $'g:bartleby_spotlight_conceal_{isGui ? "gui" : "cterm"}fg'
  var concealSet: bool = isGui ? conceal_guifg !=# '' : spotlightconcealctermfg !=# ''
  if concealSet
    return MW.CannotCalcBg()
  endif
  return MW.UnsupportedColorScheme(varName)
enddef

# FUNCTION: Compute and set the SpotlightDim highlight group for the
# current colorscheme and coeff. Throws Unsupported or a coefficient range
# error instead of failing silently. The caller reports it.
def Dim(coeff: float): void
  var synid: number = synIDtrans(hlID('Normal'))
  var fg: string = synIDattr(synid, 'fg#')
  var bg: string = synIDattr(synid, 'bg#')

  if has('gui_running') || (has('termguicolors') && &termguicolors)
    var dim: string
    if coeff < 0 && conceal_guifg !=# ''
      dim = conceal_guifg
    elseif fg ==# '' || bg ==# ''
      throw Unsupported()
    else
      var c: float = ValidateCoeff(coeff)
      var fgRgb: list<number> = Hex2Rgb(fg)
      var bgRgb: list<number> = Hex2Rgb(bg)
      var dimRgb: list<number> = [
        float2nr(bgRgb[0] * c + fgRgb[0] * (1 - c)),
        float2nr(bgRgb[1] * c + fgRgb[1] * (1 - c)),
        float2nr(bgRgb[2] * c + fgRgb[2] * (1 - c)),
      ]
      dim = '#' .. join(dimRgb->mapnew((_, v) => printf(HEX_FMT, v)), '')
    endif
    execute $'highlight SpotlightDim guifg={dim} guisp=bg'
  elseif str2nr(&t_Co) ==# 256
    var dim: any
    if coeff < 0 && spotlightconcealctermfg !=# ''
      dim = spotlightconcealctermfg
    elseif str2nr(fg) <= -1 || str2nr(bg) <= -1
      throw Unsupported()
    else
      var c: float = ValidateCoeff(coeff)
      var fgGray: number = GrayContiguous(str2nr(fg))
      var bgGray: number = GrayContiguous(str2nr(bg))
      dim = GrayAnsi(float2nr(bgGray * c + fgGray * (1 - c)))
    endif
    execute $'highlight SpotlightDim ctermfg={dim}'
  elseif TY.IsLowColor()
    # With 8 or 16 colors there is nothing to blend toward. The background
    # is black, so the dimmed text is dark gray. A coefficient does not
    # apply here.
    if coeff < 0 && spotlightconcealctermfg !=# ''
      execute $'highlight SpotlightDim ctermfg={spotlightconcealctermfg}'
    else
      execute 'highlight SpotlightDim ' .. TY.DimArgs()
    endif
  else
    throw MW.UnsupportedTerminal()
  endif
enddef

# CLASS: The dim match of one window, stored in
# w:bartleby_spotlight_matches. Spotlight is on or off globally, as in
# Limelight, see IsOn, but a match belongs to one window, so each window
# keeps its own match id.

class WinMatches
  var dimMatchId: number = -1
  var prevKey: string = ''

  def ClearHl(): void
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevKey = ''
  enddef

  # METHOD: Apply spec, a mode handler's result: key with pattern, or key
  # with positions.
  def RefreshDim(spec: dict<any>): void
    if spec.key ==# this.prevKey
      return
    endif
    if this.dimMatchId != -1
      matchdelete(this.dimMatchId)
      this.dimMatchId = -1
    endif
    this.prevKey = spec.key
    if has_key(spec, 'pattern')
      if spec.pattern !=# ''
        this.dimMatchId = matchadd('SpotlightDim', spec.pattern, priority)
      endif
    elseif !empty(spec.positions)
      this.dimMatchId = matchaddpos(HL_DIM, spec.positions, priority)
    endif
  enddef
endclass

##############################################################################
# SECTION: Session state and lifecycle.
##############################################################################

def CurHandler(): func(string): dict<any>
  return get(mode_handlers, cur_mode, mode_handlers[MODE_PARA])
enddef

def RefreshCurWin(): void
  var wm: WinMatches = get(w:, 'bartleby_spotlight_matches', null_object)
  # A pane of Bartleby is never dimmed, because Spotlight works only in the
  # edit window.
  if W.IsChromeBuf(bufnr())
    if wm isnot null_object
      wm.ClearHl()
    endif
    return
  endif
  if wm is null_object
    wm = WinMatches.new()
    w:bartleby_spotlight_matches = wm
  endif
  var Handler: func(string): dict<any> = CurHandler()
  wm.RefreshDim(Handler(cur_mode))
enddef

def RedimSafely(): void
  try
    Dim(cur_coeff)
  catch
    Off()
    log.Error(v:exception)
  endtry
enddef

def CleanupIfOff(): void
  if !IsOn()
    var wm: WinMatches = get(w:, 'bartleby_spotlight_matches', null_object)
    if wm isnot null_object
      wm.ClearHl()
    endif
  endif
enddef

export def IsOn(): bool
  return exists('#bartleby_spotlight')
enddef

def On(mode: string, coeffArg: float): void
  if W.RefusedInPane(MW.Spotlight())
    return
  endif
  var actualMode: string = mode ==# '' ? cur_mode : mode
  if !has_key(mode_handlers, actualMode)
    log.Error(MW.UnknownSpotlightMode(actualMode))
    return
  endif
  if !mode_available[actualMode]()
    var reason: string = TA.FailureReason()
    if reason ==# ''
      log.Error(MW.SpotlightModeNeeds(ModeName(actualMode)))
    else
      log.Error(MW.SpotlightModeNeedsPart(ModeName(actualMode), reason))
    endif
    return
  endif
  cur_mode = actualMode
  cur_coeff = coeffArg

  try
    Dim(cur_coeff)
  catch
    log.Error(v:exception)
    return
  endtry

  RefreshCurWin()

  augroup bartleby_spotlight
    autocmd!
    autocmd CursorMoved,CursorMovedI,WinScrolled * RefreshCurWin()
    # During InsertLeave, mode still reports Insert mode, and the tagger
    # sends no requests in Insert mode, so refresh just after it.
    autocmd InsertLeave * timer_start(0, (_) => RefreshCurWin())
    autocmd ColorScheme * RedimSafely()
  augroup END
  augroup bartleby_spotlight_cleanup
    autocmd!
    autocmd WinEnter * CleanupIfOff()
  augroup END
enddef

export def Off(): void
  var wm: WinMatches = get(w:, 'bartleby_spotlight_matches', null_object)
  if wm isnot null_object
    wm.ClearHl()
  endif
  augroup bartleby_spotlight
    autocmd!
  augroup END
  augroup! bartleby_spotlight
  unlet! w:bartleby_spotlight_matches
enddef

##############################################################################
# SECTION: Public entry points.
##############################################################################

# FUNCTION: Toggle Spotlight with the current mode. <leader>bl calls this.
export def Toggle(): void
  if IsOn()
    Off()
  else
    On('', -1.0)
  endif
enddef

# FUNCTION: Return each mode, by the name that code, :BartlebySpotlight,
# and the word-list settings use, to its name in the message language.
export def ModeNames(): dict<string>
  return {
    Paragraph: MW.Para(),
    Dialogue: MW.Dialogue(),
    Nouns: MW.Nouns(),
    Verbs: MW.Verbs(),
    Adjectives: MW.Adjectives(),
    Adverbs: MW.Adverbs(),
    Pronouns: MW.Pronouns(),
    Determiners: MW.Determiners(),
    Prepositions: MW.Prepositions(),
    Conjunctions: MW.Conjunctions(),
    Auxiliaries: MW.Auxiliaries(),
    Contractions: MW.Contractions(),
    Fillers: MW.Fillers(),
    Passive: MW.Passive(),
  }
enddef

export def ModeName(mode: string): string
  return get(ModeNames(), mode, mode)
enddef

# FUNCTION: Show a searchable list of the available modes. <leader>bL
# calls this. Picking a mode turns Spotlight on with it, or switches to
# it when Spotlight is already on.
export def PickMode(): void
  var modes: list<string> = AvailableModes()
  # Wide enough for the title with the longest mode name plus 2, so the
  # title is never cut and the width does not change with the current mode.
  var names: dict<string> = ModeNames()
  var longest: number = max(modes->mapnew((_, m) => strdisplaywidth(get(names, m, m))))
  var width: number = strdisplaywidth(MW.SpotlightMode(repeat('x', longest))) + 2
  IP.PromptFilter(MW.SpotlightMode(ModeName(cur_mode)), modes, (choice: string) => {
    On(choice, cur_coeff)
  }, 10, width, names)
enddef

# FUNCTION: Handle a tagger update: results arrived, or the tagger failed.
# Redraw the current window, or turn Spotlight off if the current mode
# can no longer run. tagger.vim has already reported why.
def OnTaggerUpdate(): void
  if !IsOn()
    return
  endif
  if !IsModeAvailable(cur_mode)
    Off()
    return
  endif
  RefreshCurWin()
enddef

TA.OnUpdate(OnTaggerUpdate)

# FUNCTION: Run :BartlebySpotlight[!] [mode or coefficient]. A bang turns
# Spotlight off. A mode name switches to that mode and turns Spotlight on
# if needed. Any other argument is a coefficient, as :Limelight takes.
export def Execute(bang: bool, args: string): void
  if bang
    if IsOn()
      Off()
    endif
    return
  endif

  if args ==# ''
    Toggle()
    return
  endif

  if has_key(mode_handlers, args)
    On(args, cur_coeff)
  else
    On('', str2float(args))
  endif
enddef
