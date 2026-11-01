vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# progress.vim: writing goals and progress. The words written are the net
# change of the words of the Manuscript, unsaved text included and the
# title lines of a Scrivening left out, so that deleting text lowers them.
# Research, notes, and the Trash do not count.
#
# When the counts change, the User event of CHANGED_EVENT fires, for the
# Inspector to show them.
#
# A scrive has a session goal, the words since it opened in this Vim, a
# daily goal, and a tracker: a target over a number of days from a start
# date, as for NaNoWriMo. A writing day starts at the hour of
# g:bartleby_day_starts_at, midnight by default. progress.json in the
# scrive keeps the goals, the tracker, and for each day the total of the
# Manuscript when it started and when it was last counted.
#
# Refresh counts again, on pauses, on leaving Insert mode, and on saves,
# never on each key, and Status gives the text that it made, so that a
# status line costs nothing to draw.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/wordcount.vim' as WC
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/progress.vim' as MG
import 'bartleby/variables/constants.vim' as CO

const DATE_FMT: string = '%04d-%02d-%02d'
const DAY_FMT: string = '%Y-%m-%d'
const NEEDED_TODAY: string = 'neededToday'

# The file of the goals and the history, in the scrive.
const FILE_NAME: string = 'progress.json'
# The User event when the counts or the goals change.
export const CHANGED_EVENT: string = 'BartlebyProgressChanged'

# The progress of the open scrive: its folder, the data of FILE_NAME, the
# total of the Manuscript when this session started and when last counted,
# and the status text. Empty when no scrive is open.
var current: dict<any> = {}

##############################################################################
# SECTION: Days. Day numbers count from 1970-01-01, by the calendar alone,
# because strptime is not on every system.
##############################################################################

# FUNCTION: Return the day number of date, a string as 2021-11-01.
export def DayNum(date: string): number
  var [y, m, d] = split(date, '-')->mapnew((_, v) => str2nr(v))
  y -= m <= 2 ? 1 : 0
  var era: number = y / 400
  var yoe: number = y - era * 400
  var doy: number = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
  var doe: number = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146097 + doe - 719468
enddef

# FUNCTION: Return the date of day number n, as 2021-11-01.
export def DateOf(n: number): string
  var z: number = n + 719468
  var era: number = z / 146097
  var doe: number = z - era * 146097
  var yoe: number = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  var doy: number = doe - (365 * yoe + yoe / 4 - yoe / 100)
  var mp: number = (5 * doy + 2) / 153
  var d: number = doy - (153 * mp + 2) / 5 + 1
  var m: number = mp + (mp < 10 ? 3 : -9)
  return printf(DATE_FMT, yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
enddef

# FUNCTION: Return true when date is a real date, as 2021-11-01.
export def IsDate(date: string): bool
  return date =~# '^\d\{4}-\d\d-\d\d$' && DateOf(DayNum(date)) ==# date
enddef

# FUNCTION: Return the writing day at the time seconds, as 2021-11-01. A day
# starts at the hour of g:bartleby_day_starts_at.
export def DayOf(seconds: number): string
  return strftime(DAY_FMT, seconds - g:bartleby_day_starts_at * 3600)
enddef

##############################################################################
# SECTION: Counting and the history.
##############################################################################

# FUNCTION: Return the Manuscript of project, or null_object.
def Manuscript(project: PO.Project): BI.BinderItem
  var i: number = indexof(project.items, (_, item) => item.structureRole ==# CO.ROLE_MANUSCRIPT)
  return i < 0 ? null_object : project.items[i]
enddef

# FUNCTION: Return the words of the Manuscript of project now.
export def ManuscriptWords(project: PO.Project): number
  var manuscript: BI.BinderItem = Manuscript(project)
  return manuscript is null_object ? 0
    : WC.Totals([manuscript], project.BinderRoot())[manuscript.id]
enddef

# FUNCTION: Return the data of FILE_NAME of project, with every key. The
# file is made when goals are set or words are counted, so a new scrive and
# one from before the goals have none, and that is not worth a warning.
def Load(project: PO.Project): dict<any>
  var path: string = project.scriveDir .. '/' .. FILE_NAME
  var data: dict<any> = filereadable(path) ? PE.ReadJson(path) : {}
  return {
    goals: extend({session: 0, daily: 0}, get(data, 'goals', {})),
    tracker: get(data, 'tracker', {}),
    history: get(data, 'history', {}),
  }
enddef

def Save(): void
  PE.WriteJson(current.scriveDir .. '/' .. FILE_NAME, current.data)
enddef

# FUNCTION: Count the words of the open scrive again, at the time now, and
# make the status text. The first count of a day starts its history entry.
# A new session starts when another scrive opens.
export def Refresh(now: number = localtime()): void
  var project: PO.Project = ST.Get()
  if project is null_object
    current = {}
    return
  endif
  var total: number = ManuscriptWords(project)
  if empty(current) || current.scriveDir !=# project.scriveDir
    current = {scriveDir: project.scriveDir, data: Load(project), sessionStart: total,
      lastTotal: total}
  endif
  var day: string = DayOf(now)
  var history: dict<any> = current.data.history
  var changed: bool = !has_key(history, day)
  if changed
    # A day that starts while Vim is open starts from the last count.
    history[day] = {start: current.lastTotal, total: current.lastTotal}
  endif
  changed = changed || history[day].total != total
  history[day].total = total
  current.lastTotal = total
  current.day = day
  if changed
    Save()
  endif
  var text: string = StatusText()
  if text !=# get(current, 'text', '') || changed
    current.text = text
    Changed()
  endif
enddef

# FUNCTION: Draw the status lines again, and fire CHANGED_EVENT.
def Changed(): void
  redrawstatus!
  if exists('#User#' .. CHANGED_EVENT)
    execute 'doautocmd <nomodeline> User ' .. CHANGED_EVENT
  endif
enddef

# FUNCTION: Return the words written on day, the net change, which can be
# below 0.
def WordsOn(day: string): number
  var entry: dict<any> = get(current.data.history, day, {})
  return empty(entry) ? 0 : entry.total - entry.start
enddef

# FUNCTION: Return the words written this session and today.
export def Written(): dict<number>
  if empty(current)
    return {session: 0, today: 0}
  endif
  return {session: current.lastTotal - current.sessionStart, today: WordsOn(current.day)}
enddef

# FUNCTION: Return the goals of the open scrive: session and daily.
export def Goals(): dict<number>
  return empty(current) ? {session: 0, daily: 0} : copy(current.data.goals)
enddef

# FUNCTION: Return the tracker of the open scrive: target, start, and days,
# or an empty dict when it has none.
export def Tracker(): dict<any>
  return empty(current) ? {} : copy(current.data.tracker)
enddef

# FUNCTION: Set the goals and the tracker of the open scrive. A target of 0
# removes the tracker. Returns an error message, or an empty string.
export def SetGoals(session: number, daily: number, target: number, start: string,
    days: number): string
  if empty(current)
    return MC.NoScriveOpen()
  endif
  if session < 0 || daily < 0 || target < 0
    return MG.GoalsCannotBelow()
  endif
  if target > 0 && !IsDate(start)
    return MG.NotDateSuch(start)
  endif
  if target > 0 && days < 1
    return MG.TrackerNeedsLeast()
  endif
  current.data.goals = {session: session, daily: daily}
  current.data.tracker = target > 0 ? {target: target, start: start, days: days} : {}
  Save()
  current.text = StatusText()
  Changed()
  return ''
enddef

# FUNCTION: Return the days of the history of the open scrive, as date to
# words written, sorted by date.
export def History(): list<list<any>>
  if empty(current)
    return []
  endif
  return sort(keys(current.data.history))->mapnew((_, day) => [day, WordsOn(day)])
enddef

##############################################################################
# SECTION: The tracker, as in a NaNoWriMo sheet.
##############################################################################

# FUNCTION: Return the figures of the tracker on the day today: the day
# number, the days to go, the end date, the words written in the period,
# the words to have by now, the words needed each day to finish, today's
# share of them, the pace, the projected finish date, and whether the
# target is met. Empty when there is no tracker.
export def TrackerFigures(today: string): dict<any>
  var t: dict<any> = Tracker()
  if empty(t)
    return {}
  endif
  var start: number = DayNum(t.start)
  var now: number = DayNum(today)
  var dayNumber: number = now < start ? 0 : now - start + 1
  var written: number = 0
  var before: number = 0
  for [day, words] in History()
    var n: number = DayNum(day)
    if n >= start && n < start + t.days
      written += words
      before += n < now ? words : 0
    endif
  endfor
  var daysToGo: number = max([t.days - dayNumber, 0])
  var shouldHave: number = written < t.target
    ? float2nr(round(1.0 * min([dayNumber, t.days]) * t.target / t.days)) : t.target
  var pace: float = dayNumber > 0 && written > 0 ? 1.0 * written / dayNumber : 0.0
  # Today's share: what is left at the start of today, over the days left.
  var daysLeft: number = max([t.days - max([dayNumber, 1]) + 1, 1])
  return {
    dayNumber: dayNumber,
    daysToGo: daysToGo,
    end: DateOf(start + t.days - 1),
    written: written,
    shouldHave: shouldHave,
    difference: written - shouldHave,
    perDay: daysToGo > 0 ? float2nr(ceil(1.0 * max([t.target - written, 0]) / daysToGo)) : max([t.target - written, 0]),
    neededToday: dayNumber >= 1 && dayNumber <= t.days
      ? float2nr(ceil(1.0 * max([t.target - before, 0]) / daysLeft)) : 0,
    pace: float2nr(round(pace)),
    finish: pace > 0.0 ? DateOf(start + float2nr(ceil(t.target / pace)) - 1) : '',
    done: written >= t.target,
  }
enddef

##############################################################################
# SECTION: The status text.
##############################################################################

# FUNCTION: Return n with a comma between each 3 digits, as 50,000.
export def Thousands(n: number): string
  var digits: string = string(abs(n))
  var out: string = ''
  while strlen(digits) > 3
    out = ',' .. digits[-3 :] .. out
    digits = digits[: -4]
  endwhile
  return (n < 0 ? '-' : '') .. digits .. out
enddef

# FUNCTION: Return the status text: today's words against the daily goal,
# or against today's share of the tracker, and the words of this session
# against its goal. Goals that are not set do not show.
def StatusText(): string
  var goals: dict<number> = current.data.goals
  var written: dict<number> = Written()
  var parts: list<string> = []
  var daily: number = goals.daily
  if daily == 0
    daily = get(TrackerFigures(current.day), NEEDED_TODAY, 0)
  endif
  if daily > 0
    parts->add($'{MG.Today()} {Thousands(max([written.today, 0]))}/{Thousands(daily)}')
  endif
  if goals.session > 0
    parts->add($'{MG.Session()} {Thousands(max([written.session, 0]))}/{Thousands(goals.session)}')
  endif
  return join(parts, ' · ')
enddef

# FUNCTION: Return the status text for a status line, as for
# %{bartleby#progress#Status()}, in the window of bufNr: empty outside a
# scrive and in the panes of Bartleby, such as the Binder. It only reads
# the text that Refresh made.
export def Status(bufNr: number = bufnr()): string
  if empty(current) || ST.Get() is null_object || W.IsChromeBuf(bufNr)
    return ''
  endif
  return get(current, 'text', '')
enddef

# FUNCTION: Forget the progress of the scrive. The tests use it.
export def Forget(): void
  current = {}
enddef
