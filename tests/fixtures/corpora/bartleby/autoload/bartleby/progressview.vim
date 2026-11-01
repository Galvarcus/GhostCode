vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# progressview.vim: the views of the writing goals of progress.vim. A form
# sets the session goal, the daily goal, and the tracker. A popup shows the
# progress as a NaNoWriMo sheet does: the figures of the tracker, then a
# row for each day, or without a tracker, the days of the history.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/progress.vim' as P
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/progress.vim' as MG
import 'bartleby/variables/constants.vim' as CO

const SESSION: string = 'session'
const DAILY: string = 'daily'
const TARGET: string = 'target'
const START: string = 'start'
const DAYS: string = 'days'
const CMD_PROGRESS_HEADER: string = 'BartlebyProgressHeader'

var log = L.New(expand('<sfile>:t'))

# The days of the history that the popup shows without a tracker.
const HISTORY_DAYS: number = 30
const POPUP_ZINDEX: number = 250

# FUNCTION: Show the form of the goals and the tracker of the open scrive,
# filled with them, and set them on Save.
export def EditGoals(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  P.Refresh()
  var goals: dict<number> = P.Goals()
  var tracker: dict<any> = P.Tracker()
  var Text = (n: number) => n > 0 ? string(n) : ''
  var fields: list<list<dict<any>>> = [
    [{name: SESSION, type: CO.TYPE_TEXT}, {name: DAILY, type: CO.TYPE_TEXT}],
    [{name: TARGET, type: CO.TYPE_TEXT}],
    [{name: START, type: CO.TYPE_TEXT}, {name: DAYS, type: CO.TYPE_TEXT}],
  ]
  var vals: dict<string> = {
    session: Text(goals.session),
    daily: Text(goals.daily),
    target: Text(get(tracker, 'target', 0)),
    start: get(tracker, 'start', P.DayOf(localtime())),
    days: string(get(tracker, 'days', 30)),
  }
  var form = IP.InputPopup.new(fields, vals, {
    title: MG.WritingGoalsEmpty(),
    labels: {
      session: MG.SessionGoal(),
      daily: MG.DailyGoal(),
      target: MG.TrackerTarget(),
      start: MG.StartDate(),
      days: MG.Days(),
    },
    widths: {session: 8, daily: 8, target: 8, start: 10, days: 4},
    submit_label: MC.Save(),
  })
  form.OnSubmit((v: dict<any>) => {
    var error: string = P.SetGoals(str2nr(v.session), str2nr(v.daily), str2nr(v.target),
      trim(v.start), str2nr(v.days))
    if error !=# ''
      log.Error(error)
    endif
  })
  form.Open()
enddef

# FUNCTION: Return text, padded with spaces to width.
def Pad(text: string, width: number): string
  return text .. repeat(' ', max([width - strdisplaywidth(text), 0]))
enddef

# FUNCTION: Return the lines of a table of rows of cells, each column as
# wide as its widest cell.
def Table(rows: list<list<string>>): list<string>
  var widths: list<number> = []
  for row in rows
    for i in range(len(row))
      if i >= len(widths)
        widths->add(0)
      endif
      widths[i] = max([widths[i], strdisplaywidth(row[i])])
    endfor
  endfor
  return rows->mapnew((_, row) => row->mapnew((i, cell) => Pad(cell, widths[i]))->join('  ')->trim('', 2))
enddef

# FUNCTION: Return the lines of the popup on the day today: the goals, the
# figures of the tracker, an empty line, and a table with a row for each
# day, after its header.
export def Lines(today: string): list<string>
  var goals: dict<number> = P.Goals()
  var written: dict<number> = P.Written()
  var T = P.Thousands
  var lines: list<string> = []
  var summary: list<list<string>> = []
  if goals.session > 0
    summary->add([MG.Session(), $'{T(max([written.session, 0]))} / {T(goals.session)}'])
  endif
  if goals.daily > 0
    summary->add([MG.Today(), $'{T(max([written.today, 0]))} / {T(goals.daily)}'])
  endif
  var tracker: dict<any> = P.Tracker()
  var f: dict<any> = P.TrackerFigures(today)
  if !empty(f)
    var gap: string = f.difference >= 0
      ? MC.Over(T(f.difference)) : MC.Under(T(-f.difference))
    summary += Table([
      [MC.Target(), T(tracker.target), MG.Day(), MG.Of(f.dayNumber, tracker.days),
        MG.Written(), T(f.written)],
      [MG.Start(), tracker.start, MG.DaysGo(), string(f.daysToGo),
        MG.ShouldHave(), T(f.shouldHave)],
      [MG.End(), f.end, MG.Track(), gap, MG.PerDay(), T(f.perDay)],
      [MG.Pace(), MG.ADay(T(f.pace)), MG.Finish(), f.finish ==# '' ? '-' : f.finish, '', ''],
    ])->mapnew((_, line) => [line])
    summary->add([f.done ? MG.DidWinner() : MG.CanDo()])
  endif
  lines += summary->mapnew((_, row) => len(row) == 1 ? row[0] : join(row, ': '))
  if !empty(lines)
    lines->add('')
  endif
  var history: dict<number> = {}
  for [day, words] in P.History()
    history[day] = words
  endfor
  var rows: list<list<string>> = []
  if !empty(f)
    rows->add([MG.Day(), MG.Date(), MC.Words(), MG.Total()])
    var start: number = P.DayNum(tracker.start)
    var total: number = 0
    for i in range(tracker.days)
      var day: string = P.DateOf(start + i)
      var future: bool = day > today
      total += get(history, day, 0)
      rows->add([string(i + 1), day, has_key(history, day) ? T(history[day]) : '',
        future ? '' : T(total)])
    endfor
  else
    rows->add([MG.Date(), MC.Words()])
    for [day, words] in P.History()[-HISTORY_DAYS :]
      rows->add([day, T(words)])
    endfor
  endif
  return lines + Table(rows)
enddef

# FUNCTION: Show the progress of the open scrive in a popup: j and k
# scroll, e edits the goals, q and Esc close.
export def Show(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  P.Refresh()
  var lines: list<string> = Lines(P.DayOf(localtime()))
  if empty(prop_type_get('BartlebyProgressHeader'))
    prop_type_add('BartlebyProgressHeader', {highlight: 'Title'})
  endif
  # The header of the table is the line after the first empty line, or
  # the first line when there is no summary.
  var header: number = index(lines, '') + 1
  var content: list<dict<any>> = lines->mapnew((i, line) => i == header && line !=# ''
    ? {text: line, props: [{col: 1, length: strlen(line), type: CMD_PROGRESS_HEADER}]}
    : {text: line})
  popup_create(content, {
    title: $' {MG.WritingProgress()}  (e: {MG.Goals()}, q: {MG.Close()}) ',
    border: [], padding: [0, 1, 0, 1], scrollbar: true, zindex: POPUP_ZINDEX,
    maxheight: max([&lines - 6, 5]), mapping: false,
    filter: (winid: number, key: string): bool => {
      if key ==# 'q' || key == CO.KEY_ESC
        popup_close(winid)
      elseif key ==# 'e'
        popup_close(winid)
        EditGoals()
      elseif key ==# 'j' || key == CO.KEY_DOWN
        popup_setoptions(winid, {firstline: popup_getoptions(winid).firstline + 1})
      elseif key ==# 'k' || key == CO.KEY_UP
        popup_setoptions(winid, {firstline: max([popup_getoptions(winid).firstline - 1, 1])})
      endif
      return true
    },
  })
enddef
