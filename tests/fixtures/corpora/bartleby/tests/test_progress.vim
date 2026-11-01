vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_progress.vim: the writing goals of progress.vim and their
# views. Days count by the calendar and start at the set hour. The words
# written are the net change of the Manuscript, unsaved text included and
# the title lines of a Scrivening left out. A day starts from the last
# count, the goals and the history are kept in progress.json, and the
# tracker gives the figures of a NaNoWriMo sheet. Times are given to
# Refresh, so that a test does not wait for a day to end.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/progress.vim' as P
import autoload 'bartleby/progressview.vim' as PV
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/wordcount.vim' as WC
import 'Logger/messages.vim' as LM
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the fixture project, current, with its two scenes and a
# research note on disk, and no progress yet.
def NewProject(): dict<any>
  P.Forget()
  WC.ClearCache()
  var project = FI.BuildProject()
  var scene1 = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(project, scene1, ['one two three'])
  FI.WriteDocContent(project, scene2, ['four five'])
  ST.Set(project)
  return {project: project, scene1: scene1, scene2: scene2,
    path1: scene1.AbsPath(project.BinderRoot())}
enddef

def Close(fx: dict<any>): void
  SV.Close()
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  P.Forget()
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: Write the words of the sheet example to the history: 1,300 on
# each of the first 8 days of November 2021, and 1,600 on the 9th.
def SheetHistory(fx: dict<any>): void
  var file: string = fx.project.scriveDir .. '/progress.json'
  var data: dict<any> = json_decode(join(readfile(file), ''))
  data.history = {}
  for i in range(9)
    data.history[P.DateOf(P.DayNum('2021-11-01') + i)] = {start: 0, total: i < 8 ? 1300 : 1600}
  endfor
  writefile([json_encode(data)], file)
  P.Forget()
  P.Refresh()
enddef

def Test_dates_count_by_the_calendar(): void
  assert_equal([0, 11016, 18932], ['1970-01-01', '2000-02-29', '2021-11-01']->mapnew((_, d) => P.DayNum(d)))
  for d in ['1999-12-31', '2000-03-01', '2024-02-29', '2026-10-09']
    assert_equal(d, P.DateOf(P.DayNum(d)))
  endfor
  assert_equal([true, false, false], [P.IsDate('2024-02-29'), P.IsDate('2021-02-29'), P.IsDate('11/01/2021')])
enddef

def Test_a_day_starts_at_the_set_hour(): void
  if !exists('*strptime')
    return
  endif
  var twoAm: number = strptime('%Y-%m-%d %H:%M', '2021-11-02 02:00')
  assert_equal('2021-11-02', P.DayOf(twoAm))
  g:bartleby_day_starts_at = 4
  assert_equal('2021-11-01', P.DayOf(twoAm))
  g:bartleby_day_starts_at = 0
enddef

def Test_the_manuscript_counts_with_its_unsaved_text(): void
  var fx = NewProject()
  AddResearchNote(fx.project)
  assert_equal(5, P.ManuscriptWords(fx.project))
  execute 'silent edit ' .. fnameescape(fx.path1)
  setline(1, 'one two three and four more')
  assert_equal(8, P.ManuscriptWords(fx.project))
  set nomodified
  bwipe!
  # In a Scrivening, its unsaved text counts, and its title lines do not.
  SV.Open(fx.project, fx.project.ChildAt(1))
  setline(2, 'one two three and four more')
  assert_equal(8, P.ManuscriptWords(fx.project))
  set nomodified
  Close(fx)
enddef

# FUNCTION: Add a note with words to the Research folder of project, which
# must not count.
def AddResearchNote(project: any): void
  var research = project.ChildAt(4)
  var note = bartleby#binderitem#BinderItem.NewDocument('Note', 'research/note.md')
  research.AddChild(note)
  FI.WriteDocContent(project, note, ['many words that do not count'])
enddef

def Test_today_is_the_net_change(): void
  var fx = NewProject()
  P.Refresh()
  FI.WriteDocContent(fx.project, fx.scene1, ['one two three four five six seven'])
  P.Refresh()
  assert_equal(4, P.Written().today)
  FI.WriteDocContent(fx.project, fx.scene1, ['one'])
  P.Refresh()
  assert_equal(-2, P.Written().today)
  P.SetGoals(0, 100, 0, '', 0)
  assert_equal('Today 0/100', P.Status())
  Close(fx)
enddef

def Test_a_new_day_starts_from_the_last_count(): void
  var fx = NewProject()
  var day1: number = localtime()
  P.Refresh(day1)
  FI.WriteDocContent(fx.project, fx.scene1, ['one two three four'])
  P.Refresh(day1)
  assert_equal(1, P.Written().today)
  P.Refresh(day1 + 86400)
  assert_equal(0, P.Written().today)
  FI.WriteDocContent(fx.project, fx.scene1, ['one two three four five'])
  P.Refresh(day1 + 86400)
  assert_equal([1, 1], [P.Written().today, P.History()[0][1]])
  # The session counts across days.
  assert_equal(2, P.Written().session)
  Close(fx)
enddef

def Test_goals_and_history_survive_a_restart(): void
  var fx = NewProject()
  P.Refresh()
  P.SetGoals(500, 1000, 0, '', 0)
  FI.WriteDocContent(fx.project, fx.scene1, ['one two three four'])
  P.Refresh()
  P.Forget()
  P.Refresh()
  assert_equal({session: 500, daily: 1000}, P.Goals())
  # Today still counts from its start, a new session from now.
  assert_equal([1, 0], [P.Written().today, P.Written().session])
  Close(fx)
enddef

# FUNCTION: A scrive has no progress.json until it has goals or a history,
# as a new scrive and one from before the goals. That is not a problem, so
# nothing is logged.
def Test_a_scrive_without_progress_data_logs_no_warning(): void
  var fx = NewProject()
  assert_false(filereadable(fx.project.scriveDir .. '/progress.json'))
  LM.Clear()
  P.Refresh()
  var logged: list<string> = LM.History()->mapnew((_, m) => join(m.lines, ' '))
  assert_equal([], logged, 'something was logged')
  Close(fx)
enddef

def Test_goals_are_checked(): void
  var fx = NewProject()
  P.Refresh()
  assert_match('not a date', P.SetGoals(0, 0, 50000, '2021-02-29', 30))
  assert_match('at least 1 day', P.SetGoals(0, 0, 50000, '2021-11-01', 0))
  assert_match('below 0', P.SetGoals(-1, 0, 0, '', 0))
  assert_equal([{session: 0, daily: 0}, {}], [P.Goals(), P.Tracker()])
  Close(fx)
enddef

# FUNCTION: The figures of the tracker match those of the NaNoWriMo sheet:
# 50,000 words from 2021-11-01 in 30 days, 12,000 written by day 10.
def Test_the_tracker_matches_the_sheet(): void
  var fx = NewProject()
  P.Refresh()
  P.SetGoals(0, 0, 50000, '2021-11-01', 30)
  SheetHistory(fx)
  var f = P.TrackerFigures('2021-11-10')
  assert_equal([10, 20, '2021-11-30', 12000, 16667, -4667, 1900, 1200, '2021-12-12', false],
    [f.dayNumber, f.daysToGo, f.end, f.written, f.shouldHave, f.difference, f.perDay, f.pace,
    f.finish, f.done])
  # Today's share: what was left at its start, over the days left.
  assert_equal(1810, f.neededToday)
  Close(fx)
enddef

def Test_the_status_shows_only_the_goals_that_are_set(): void
  var fx = NewProject()
  P.Refresh()
  assert_equal('', P.Status())
  P.SetGoals(500, 1000, 0, '', 0)
  assert_equal('Today 0/1,000 · Session 0/500', P.Status())
  assert_equal('', P.Status(bufadd(CO.BINDER_BUF)))
  Close(fx)
enddef

def Test_the_popup_shows_the_sheet(): void
  var fx = NewProject()
  P.Refresh()
  P.SetGoals(0, 0, 50000, '2021-11-01', 30)
  SheetHistory(fx)
  var lines: list<string> = PV.Lines('2021-11-10')
  assert_match('Should have  16,667', join(lines, "\n"))
  assert_match('4,667 under', join(lines, "\n"))
  assert_match('You can do this!', join(lines, "\n"))
  var header: number = index(lines, '') + 1
  assert_match('^Day  Date', lines[header])
  assert_equal('9    2021-11-09  1,600  12,000', lines[header + 9])
  # Today has no words yet, and the total so far. Later days are empty.
  assert_equal('10   2021-11-10         12,000', lines[header + 10])
  assert_equal('11   2021-11-11', lines[header + 11])
  Close(fx)
enddef

def Test_the_inspector_shows_the_goals(): void
  var fx = NewProject()
  P.Refresh()
  P.SetGoals(500, 0, 0, '', 0)
  execute 'silent edit ' .. fnameescape(fx.path1)
  I.Toggle()
  var lines: list<string> = getbufline(CO.INSPECTOR_BUF, 1, '$')
  assert_equal(['::Goals::', 'Session: 0 / 500'], lines[-2 :])
  # e on a goal line opens the form of the goals.
  win_gotoid(bufwinid(CO.INSPECTOR_BUF))
  cursor(line('$'), 1)
  feedkeys('e', 'xt')
  assert_false(empty(popup_list()), 'e on a goal line opened nothing')
  popup_clear(true)
  I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  Close(fx)
enddef

# FUNCTION: Run a real Vim with the plugin and the statusline set to
# statusline, and return the statusline after startup and after a new
# scrive opens.
def StatuslineAfterOpen(statusline: string): list<string>
  var log: string = FI.Slashed(tempname())
  var script: string = FI.Slashed(tempname())
  var root: string = FI.Slashed(tempname())
  var plugin: string = FI.Slashed(fnamemodify(expand('<script>'), ':p:h:h'))
  writefile([
    'vim9script',
    'import autoload "bartleby.vim" as BA',
    'import "bartleby/variables/constants.vim" as CO',
    $'g:bartleby_binder_root = "{root}"',
    $'&g:statusline = {string(statusline)}',
    'runtime plugin/bartleby.vim',
    'doautocmd VimEnter',
    'var atStart: string = &g:statusline',
    'BA.CreateScrive("Status", CO.TYPE_NOVEL)',
    $'writefile([atStart, &g:statusline], "{log}")',
    'qa!',
  ], script)
  FI.Spawn($'{v:progpath} -es -u NONE -N --cmd "set rtp+={plugin},{FI.LoggerDir()}" -S {script}')
  var result: list<string> = filereadable(log) ? readfile(log) : ['no result', '']
  delete(log)
  delete(script)
  delete(root, 'rf')
  return result
enddef

# FUNCTION: The status line waits for a scrive, so that Vim loads
# bartleby.vim at startup only for Bartleby.
def Test_the_status_line_is_added_only_when_it_has_no_setting(): void
  var blank: list<string> = StatuslineAfterOpen('')
  assert_equal('', blank[0])
  assert_match('bartleby#progress#Status', blank[1])
  assert_equal(['%f mine', '%f mine'], StatuslineAfterOpen('%f mine'))
enddef

export def RunAll(): void
  Test_dates_count_by_the_calendar()
  Test_a_day_starts_at_the_set_hour()
  Test_the_manuscript_counts_with_its_unsaved_text()
  Test_today_is_the_net_change()
  Test_a_new_day_starts_from_the_last_count()
  Test_goals_and_history_survive_a_restart()
  Test_a_scrive_without_progress_data_logs_no_warning()
  Test_goals_are_checked()
  Test_the_tracker_matches_the_sheet()
  Test_the_status_shows_only_the_goals_that_are_set()
  Test_the_popup_shows_the_sheet()
  Test_the_inspector_shows_the_goals()
  Test_the_status_line_is_added_only_when_it_has_no_setting()
enddef
