vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/progress.vim:
# the messages of goals and progress.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/progress.vim' as MG
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: progress.vim
##############################################################################

export def GoalsCannotBelow(): string
  return IN.T("goals cannot be below 0")
enddef

export def NotDateSuch(start: any): string
  return printf(IN.T("%s is not a date such as 2021-11-01"), start)
enddef

export def TrackerNeedsLeast(): string
  return IN.T("a tracker needs at least 1 day")
enddef

export def Today(): string
  return IN.T("Today")
enddef

export def Session(): string
  return IN.T("Session")
enddef

##############################################################################
# SECTION: progressview.vim
##############################################################################

export def WritingGoalsEmpty(): string
  return IN.T(" Writing goals. 0 or empty is off ")
enddef

export def SessionGoal(): string
  return IN.T("Session goal")
enddef

export def DailyGoal(): string
  return IN.T("Daily goal")
enddef

export def TrackerTarget(): string
  return IN.T("Tracker target")
enddef

export def StartDate(): string
  return IN.T("Start date")
enddef

export def Days(): string
  return IN.T("Days")
enddef

export def Day(): string
  return IN.T("Day")
enddef

export def Of(dayNumber: any, days: any): string
  return printf(IN.T("%d of %d"), dayNumber, days)
enddef

export def Written(): string
  return IN.T("Written")
enddef

export def Start(): string
  return IN.T("Start")
enddef

export def DaysGo(): string
  return IN.T("Days to go")
enddef

export def ShouldHave(): string
  return IN.T("Should have")
enddef

export def End(): string
  return IN.T("End")
enddef

export def Track(): string
  return IN.T("On track")
enddef

export def PerDay(): string
  return IN.T("Per day")
enddef

export def Pace(): string
  return IN.T("Pace")
enddef

export def ADay(amt: any): string
  return printf(IN.T("%s a day"), amt)
enddef

export def Finish(): string
  return IN.T("Finish")
enddef

export def DidWinner(): string
  return IN.T("You did it! Winner!")
enddef

export def CanDo(): string
  return IN.T("You can do this!")
enddef

export def Date(): string
  return IN.T("Date")
enddef

export def Total(): string
  return IN.T("Total")
enddef

export def WritingProgress(): string
  return IN.T("Writing progress")
enddef

export def Goals(): string
  return IN.T("goals")
enddef

export def Close(): string
  return IN.T("close")
enddef
