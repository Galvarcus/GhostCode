vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/fixtures.vim: shared test data, built in memory. BuildProject uses
# InitNew, SeedTree, and AddChild, the construction API that
# templates.vim uses, instead of reading a JSON fixture from disk. This
# keeps Tier 1 tests free of the filesystem, and the fixture stays
# readable Vim9 code instead of JSON that must be kept in step by hand.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import 'Logger/messages.vim' as LM
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return a Novel project with the five structural folders, and
# a Manuscript with 2 chapters of 1 scene each: enough to test nesting,
# owners, and sibling order, and no larger.
export def BuildProject(): PO.Project
  var project = PO.Project.new($'{TEMP_DIR}/bartleby-test-fixture.bartleby')
  project.InitNew('Fixture Project', CO.TYPE_NOVEL)

  var frontMatter = BI.BinderItem.NewFolder('Front Matter', CO.ROLE_FRONT_MATTER)
  var manuscript = BI.BinderItem.NewFolder('Manuscript', CO.ROLE_MANUSCRIPT)
  var backMatter = BI.BinderItem.NewFolder('Back Matter', CO.ROLE_BACK_MATTER)
  var characters = BI.BinderItem.NewFolder('Characters', CO.ROLE_CHARS)
  var research = BI.BinderItem.NewFolder('Research', CO.ROLE_RESEARCH)

  var chapter1 = BI.BinderItem.NewFolder('1', CO.ROLE_CHAPTER)
  chapter1.AddChild(BI.BinderItem.NewDocument('Scene 1', 'chapter-1/scene-01.md'))
  var chapter2 = BI.BinderItem.NewFolder('2', CO.ROLE_CHAPTER)
  chapter2.AddChild(BI.BinderItem.NewDocument('Scene 1', 'chapter-2/scene-01.md'))
  manuscript.AddChild(chapter1)
  manuscript.AddChild(chapter2)

  project.SeedTree([frontMatter, manuscript, backMatter, characters, research])
  return project
enddef

# FUNCTION: Write lines to the real file of item under the binder root of
# project, for tests of code that reads document text from disk, such as
# ReadDocLines in compile.vim. Creates the folder when relPath has one,
# as in chapter-1/scene-01.md. The caller cleans up, see
# CleanupProjectFiles.
export def WriteDocContent(project: PO.Project, item: BI.BinderItem, lines: list<string>): void
  var path = item.AbsPath(project.BinderRoot())
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(lines, path)
enddef

# The font that the Book compiles of the smoke suite ask fontspec for.
# It is exported because the compile leg of CI reads it as well, through
# .github/scripts/smoke-font.vim: the leg asserts that the family is
# usable before the suites run, and a family named twice could be
# registered in one place and asked for in another.
export const SMOKE_FONT: string = 'DejaVu Serif'

# The file that Step appends to, under the folder that a run starts in.
const PROGRESS: string = 'tests/progress.log'

# The folder that holds every fixture project of a run, under the
# temporary folder of this Vim, which it removes when it ends, and not
# under /tmp, which Windows reads as a folder of the current drive. See
# TempPath for why the spelling matters.

# FUNCTION: Return the temporary folder of this Vim, spelled as Vim
# answers elsewhere. tempname gives the 8.3 short name on Windows, such as
# C:\Users\RUNNER~1\AppData\Local\Temp, while a buffer name and getcwd
# give the long one, and fnamemodify(':p') leaves a short name short, so a
# path built from tempname never matched one that Vim gave back. Only the
# folder itself can answer: getcwd inside it is the long name. On Unix the
# same trouble is a symbolic link, /var/folders for /private/var/folders,
# which resolve answers.
def LongTempDir(): string
  var dir: string = fnamemodify(tempname(), ':h')
  mkdir(dir, 'p')
  if !has('win32')
    return resolve(dir)
  endif
  var cwd: string = getcwd()
  noautocmd execute 'lcd ' .. fnameescape(dir)
  var long: string = substitute(getcwd(), '\\', '/', 'g')
  noautocmd execute 'lcd ' .. fnameescape(cwd)
  return long
enddef

# Once, as this file loads, while no test is running and no window of a
# test can mind the lcd above.
const TEMP_DIR: string = LongTempDir()

# FUNCTION: Return the last message that Bartleby logged, for an
# assertion about a feature that refused to start: the refusal says why in
# the log and nowhere else, and a message reaches nothing in silent ex
# mode. Empty when nothing is logged.
export def LastLog(): string
  var history: list<any> = LM.History()
  return empty(history) ? '' : join(history[-1].lines, ' ')
enddef

# FUNCTION: Return a temporary path, as tempname does, under TEMP_DIR, so
# that a test which compares a path it built against one from Vim compares
# one spelling. A short name also holds a tilde, which a pattern reads as
# the last substitution, and that threw E33 in the templates.
export def TempPath(): string
  return $'{TEMP_DIR}/{fnamemodify(tempname(), ":t")}'
enddef

# FUNCTION: Record that a run reached what, with the time. It is the only
# way to tell where a run stopped when it writes no result: a message
# reaches nothing in silent ex mode, and a run that is killed, by a
# watchdog or by the limit of a job, prints nothing of its own. Call Step
# with 'start' first, which begins the file again.
export def Step(what: string): void
  writefile([$'{strftime("%H:%M:%S")} {what}'], PROGRESS, what ==# 'start' ? '' : 'a')
enddef

# FUNCTION: Return path with forward slashes, which Vim takes on every
# system. A backslash of Windows is an escape in a string and in the set
# command, and a test that starts a second Vim passes paths through both.
export def Slashed(path: string): string
  return substitute(path, '\\', '/', 'g')
enddef

# FUNCTION: Run cmd, which starts a second Vim, and return what it wrote.
# Its input comes from the empty device, because a Vim in silent ex mode
# reads its input to the end, and the console that Windows gives a job
# never ends, so the second Vim would never return and the job would run
# until its own limit. The timeout stops a Vim that hangs for another
# reason; it is a program of POSIX, and the timeout of Windows only waits,
# so there the limit of the job is the only one.
export def Spawn(cmd: string): string
  if has('win32')
    return system($'{cmd} < NUL')
  endif
  return system($'timeout 60 {cmd} < /dev/null')
enddef

# FUNCTION: Make link a symbolic link to target, and return true when the
# system allowed it: Windows has no ln, and its mklink needs a privilege
# that the user may not hold, so a test skips itself when this fails.
# target must exist, because getftype answers nothing for a link whose
# target does not, and this would report no link at all.
export def MakeLink(target: string, link: string): bool
  if has('win32')
    system($'mklink{isdirectory(target) ? " /D" : ""} {shellescape(link)} {shellescape(target)}')
  else
    system($'ln -s {shellescape(target)} {shellescape(link)}')
  endif
  return getftype(link) ==# 'link'
enddef

# FUNCTION: Return the Logger folder of the runtimepath of this Vim, for a
# test that starts a second Vim and must give it Logger. The path is
# deps/Logger in CI and wherever the developer keeps it otherwise, so a
# test that names deps/Logger itself fails outside CI.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/41
export def LoggerDir(): string
  for dir in split(&runtimepath, ',')
    if fnamemodify(dir, ':t') ==# 'Logger'
      # Absolute, because CI puts deps/Logger on the runtimepath as a
      # relative path and a second Vim need not start in this folder.
      return substitute(Slashed(fnamemodify(dir, ':p')), '/$', '', '')
    endif
  endfor
  return ''
enddef

# FUNCTION: Remove the whole folder of a fixture project on disk, its
# binder root and everything in it. Call it at the end of every test that
# used WriteDocContent.
export def CleanupProjectFiles(project: PO.Project): void
  delete(project.scriveDir, 'rf')
enddef
