vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# compile.vim: compiles a scrive into one output file. Three kinds:
#   Manuscript  Submission PDF, through Pandoc with pdflatex and
#               tools/latex/manuscript.tex, a template for the sffms class.
#   Book        PDF, HTML, EPUB, or Markdown for readers. PDF uses xelatex
#               and tools/latex/book.tex. HTML and EPUB use Pandoc's own
#               writers and tools/css/book.css.
#   Screenplay  PDF, HTML, or FDX through screenplain, not Pandoc.
#               screenplain has no font option, so
#               g:bartleby_compile_screenplay_font has no effect yet.
#
# Bartleby joins the included documents in binder order and runs the
# converter with the right template. It converts no formats itself.
#
# CompileTarget is defined before the functions that use it because many
# of them name it in their parameter or return type. Vim9 resolves a
# signature when the function is defined, so a class named there must
# already exist. A class used only inside a function body can come later.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/slug.vim' as SU
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'dist/vim9.vim' as DV
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/compile.vim' as MK
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/table.vim' as TB
import autoload 'bartleby/texcheck.vim' as TX
import 'bartleby/variables/constants.vim' as CO

const FMT_HTML: string = 'HTML'
const FMT_EPUB: string = 'EPUB'
const FMT_MARKDOWN: string = 'Markdown'
const FMT_FDX: string = 'FDX'
const FMT_PDF: string = 'PDF'
const PATH_COMPILE_TARGETS: string = '/compile/targets'
const EXT_JSON: string = '.json'
# What job_status answers for a job that never started.
const JOB_FAIL: string = 'fail'
# What each of the two names in a log file name may take: 255 bytes for
# the component, less the timestamp, the two separators and .json.
const LOG_NAME_BYTES: number = 116

# What a whole path may hold. MS-Windows refuses one over 260 characters
# unless the writer has turned long paths on, and the limit of a single
# component does not catch it: a name inside that limit, under a folder
# of ordinary depth, is still over this. The few bytes under 260 are
# margin, because the name of a definition is not the name of its
# target and a shorter one costs nothing. Elsewhere a component is what
# binds first, so this number only has to be past it.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/61
const MAX_PATH_BYTES: number = has('win32') ? 255 : 1023
# The longest suffix that a name in use takes, see FreeTargetPath.
const SUFFIX_ROOM: string = '-99'
const FILE_JSON: string = '*.json'
const SPACING_DOUBLE: string = 'Double'
const SPACING_SINGLE: string = 'Single'
const PATH_COMPILE_OUTPUT: string = '/compile/output'
const PATH_TOOLS_LATEX_MANUSCRIPT_TEX: string = '/tools/latex/manuscript.tex'
const PATH_TOOLS_LATEX_BOOK_TEX: string = '/tools/latex/book.tex'
const PATH_TOOLS_CSS_BOOK_CSS: string = '/tools/css/book.css'
const PATH_TOOLS_PANDOC_TABLES: string = '/tools/pandoc/tables.lua'
# The styles of table lines and headers, and their fallbacks, as in
# tools/pandoc/tables.lua and tools/cheatsheet/build_cheatsheet.py.
const LINE_NONE: string = 'none'
const TABLE_LINES: list<string> = [LINE_NONE, 'single']
const LINE_FALLBACK: string = 'single'
const HEADER_SMALLCAPS: string = 'smallcaps'
const TABLE_HEADERS: list<string> = ['bold', 'italic', HEADER_SMALLCAPS, 'plain']
const HEADER_FALLBACK: string = 'bold'
# The table lines of HTML and EPUB.
const CSS_BORDER: string = 'table { border: 1px solid #333; }'
const CSS_VLINES: string = 'th + th, td + td { border-left: 1px solid #999; }'
const ARG_NOVEL: string = '--metadata=isnovel:true'
const COURIER: string = 'courier'
const ARG_COURIER: string = '--metadata=usecourier:true'
const ARG_SINGLE: string = '--metadata=singlespaced:true'
const EXT_LOG: string = '.log'
const FLAG_STANDALONE: string = '--standalone'
const FLAG_TOC: string = '--toc'
const ARG_CHAPTERS: string = '--top-level-division=chapter'
# The engines of the templates: Pandoc's default for a Manuscript, and
# xelatex for a Book. extra_args can name another.
const ARG_ENGINE: string = '--pdf-engine'
const PDFLATEX: string = 'pdflatex'
const XELATEX: string = 'xelatex'
const ARG_XELATEX: string = $'{ARG_ENGINE}={XELATEX}'
const A4: string = 'a4'
const LETTER: string = 'letter'
const ACTION_EDIT: string = 'Edit'
const ACTION_DELETE: string = 'Delete'
const ACTION_RUN: string = 'Run'

var log = L.New(expand('<sfile>:t'))
var compilescriptpath: string = expand('<sfile>:p')
var pandoc_bin: string = g:bartleby_compile_pandoc_bin
var screenplain_bin: string = g:bartleby_compile_screenplain_bin
var compile_lang: string = g:bartleby_compile_lang
var papersize: string = g:bartleby_compile_papersize
var toc: bool = g:bartleby_compile_toc
var standalone: bool = g:bartleby_compile_standalone
var manuscript_font: string = g:bartleby_compile_manuscript_font
var book_font: string = g:bartleby_compile_book_font
var manuscript_double_spaced: bool = g:bartleby_compile_manuscript_double_spaced
var indent_paras: bool = g:bartleby_compile_indent_paragraphs
var book_chapter_style: string = g:bartleby_compile_book_chapter_style
var book_part_style: string = g:bartleby_compile_book_part_style
var extra_args: list<string> = g:bartleby_compile_extra_args
var table_border: string = g:bartleby_compile_table_border
var table_vlines: string = g:bartleby_compile_table_vlines
var table_header: string = g:bartleby_compile_table_header
var log_retention: number = g:bartleby_compile_log_retention

# The compiles that are running, by the output folder and the work name
# that all of their paths are built from, so that a second run cannot
# start while the first is reading and writing the files the two would
# share. The name of a target is the wrong key: a rename frees the stem
# of its definition and the renamed target takes it back, and one name
# in two scrives shares no path at all. A session that ends takes the
# list with it.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/60
var running: dict<bool> = {}

const KIND_MANUSCRIPT: string = 'Manuscript'
const KIND_BOOK: string = 'Book'
const KIND_SCREENPLAY: string = 'Screenplay'
const KINDS: list<string> = [KIND_MANUSCRIPT, KIND_BOOK, KIND_SCREENPLAY]
# The picker option that starts a new target, shown translated.
const NEW_TARGET: string = '+ New Target'

const KIND_FMTS: dict<list<string>> = {
  Manuscript: ['PDF'],
  Book: ['PDF', FMT_HTML, FMT_EPUB, FMT_MARKDOWN],
  Screenplay: ['PDF', FMT_HTML, FMT_FDX],
}
const PANDOC_EXT: dict<string> = {PDF: 'pdf', HTML: 'html', EPUB: 'epub', Markdown: 'md'}
const SCREENPLAY_EXT: dict<string> = {PDF: 'pdf', HTML: 'html', FDX: 'fdx'}
# What a format of neither table compiles to, which only a damaged
# definition carries.
const EXT_DEFAULT: string = 'pdf'

# CLASS: A saved compile preset: kind, format, font, cover image,
# spacing, separator, and the included documents.

export class CompileTarget
  var name: string = ''
  var kind: string = KIND_MANUSCRIPT
  var format: string = 'PDF'
  var font: string = ''
  var coverImage: string = ''
  var doubleSpaced: bool = true
  var separator: string = '* * *'
  var includedIds: list<string> = []

  static def FromDict(src: dict<any>): CompileTarget
    var t: CompileTarget = CompileTarget.new()
    t.name = get(src, 'name', '')
    t.kind = get(src, 'kind', KIND_MANUSCRIPT)
    t.format = get(src, 'format', FMT_PDF)
    t.font = get(src, 'font', '')
    t.coverImage = get(src, 'coverImage', '')
    t.doubleSpaced = get(src, 'doubleSpaced', true)
    t.separator = get(src, 'separator', '* * *')
    t.includedIds = get(src, 'includedIds', [])
    return t
  enddef

  def ToDict(): dict<any>
    return {name: this.name, kind: this.kind, format: this.format, font: this.font,
      coverImage: this.coverImage, doubleSpaced: this.doubleSpaced,
      separator: this.separator, includedIds: this.includedIds}
  enddef
endclass

def TargetsDir(project: PO.Project): string
  return project.scriveDir .. PATH_COMPILE_TARGETS
enddef

# FUNCTION: Return the slug of a target's name, or UNTITLED when the slug
# is empty. The engines read every path this names, so it stays ASCII,
# and an empty slug made the definition of such a target .json, which the
# glob that lists them never returned.
def SlugName(name: string, max: number = SU.MAX_BYTES): string
  var slug: string = SU.Slugify(name, max)
  return slug ==# '' ? SU.Capped(CO.UNTITLED, max) : slug
enddef

def TargetFiles(project: PO.Project): list<string>
  var dir: string = TargetsDir(project)
  if !isdirectory(dir)
    return []
  endif
  # nosuf true, so that a wildignore of the writer cannot hide a target.
  return globpath(dir, FILE_JSON, true, true)
enddef

def NameOf(path: string): string
  return CompileTarget.FromDict(PE.ReadJson(path)).name
enddef

# FUNCTION: Return the path of the definition that carries name, or an
# empty string when none does. A target is the name the writer gave it
# and the file is only where its settings live, because two names reduce
# to one slug often enough: every name in a script of its own reduces to
# untitled, and the second save took the file of the first.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/58
def PathOf(project: PO.Project, name: string): string
  # A damaged definition decodes to an empty dictionary and so carries
  # no name. Nothing it holds is a target.
  if name ==# ''
    return ''
  endif
  for path in TargetFiles(project)
    if NameOf(path) ==# name
      return path
    endif
  endfor
  return ''
enddef

# FUNCTION: Return what the name of a definition may take under dir: the
# room the path leaves after the folder, the suffix a name in use takes,
# the extension, and what a write appends while it works, which is
# longer than the path it leaves. The name of a definition is not the
# name of its target, which is stored inside the file, so a shorter file
# name costs nothing but the look of it. The prefix of the device guard
# is reserved as well, because a name cut to the last bytes of the room
# can be a device name and the guard then takes four bytes more, which
# this limit leaves over on MS-Windows alone: elsewhere it is the limit
# the system enforces, and the write of a guarded name failed on it.
export def PathRoom(dir: string): number
  return MAX_PATH_BYTES - strlen(
    $'{dir}/{SU.DEVICE_PREFIX}{SUFFIX_ROOM}{EXT_JSON}{PE.TMP_SUFFIX}')
enddef

# FUNCTION: Return the first of <slug>.json, <slug>-2.json and so on
# that nothing holds, for a name that no definition carries yet. Held
# rather than readable, because a folder of that name holds it too, as
# does a file that cannot be read.
def FreeTargetPath(project: PO.Project, name: string): string
  var dir: string = TargetsDir(project)
  # Within the room this path leaves, and never to nothing, because a
  # definition named only .json is one that the glob cannot list.
  var slug: string = SlugName(name, max([PathRoom(dir), 1]))
  var base: string = $'{dir}/{slug}'
  var path: string = base .. EXT_JSON
  var n: number = 2
  while getftype(path) !=# ''
    path = $'{base}-{n}{EXT_JSON}'
    n += 1
  endwhile
  return path
enddef

# FUNCTION: Return the name that the working files of a target carry:
# the stem of its definition, which holds one target since #58, or the
# slug of its name while it has none. It stays ASCII, because a TeX
# engine is unreliable with a path outside ASCII, and it has to differ
# between two targets whose names reduce to one slug, which every name
# in a script of its own does.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/60
export def WorkName(project: PO.Project, target: CompileTarget): string
  var path: string = PathOf(project, target.name)
  return path ==# '' ? SlugName(target.name) : fnamemodify(path, ':t:r')
enddef

# FUNCTION: Return the name of every target of project, once each.
# Nothing here writes a second definition of one name, but a conflicted
# copy of a sync client or a file restored into the folder does, and then
# the name no longer tells the two apart: the second is left out and
# reported, so that the writer can move the file rather than meet a
# target that cannot be opened or deleted.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/63
export def ListTargets(project: PO.Project): list<string>
  var names: list<string> = []
  var seen: dict<string> = {}
  for path in TargetFiles(project)
    var name: string = NameOf(path)
    # A definition that carries no name is damaged, see PathOf, and a
    # picker that offered it would offer a target that runs on nothing.
    if name ==# ''
      continue
    endif
    if has_key(seen, name)
      # Which file is in use, because the writer acts on that one and
      # the glob decides it: every separator a sync client puts before
      # its own suffix sorts below the dot of .json, so a conflicted
      # copy wins over the file the writer made. By name alone, so that
      # the line fits a screen and no hit-enter prompt covers the list.
      log.Warn(MK.TargetNameTwice(name,
        fnamemodify(seen[name], ':t'), fnamemodify(path, ':t')))
      continue
    endif
    seen[name] = path
    names->add(name)
  endfor
  # A person reads this in the picker, and the order of the files is not
  # one: the definition of a name whose slug is taken goes to a suffixed
  # file, so the target saved second was listed first.
  #
  # Folded, because a file name is the slug of a name, so the order this
  # replaces was already the order of the names with their case folded,
  # and a comparison by byte would put every capital first. Sorted by
  # byte before that, because a folded comparison is stable and so two
  # names that differ only in case would keep the order of their files,
  # which is the order this is here to stop depending on.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/62
  return sort(sort(names), 'i')
enddef

export def LoadTarget(project: PO.Project, name: string): CompileTarget
  var path: string = PathOf(project, name)
  return path ==# '' ? null_object : CompileTarget.FromDict(PE.ReadJson(path))
enddef

# FUNCTION: Write target, over the definition of its own name when one is
# stored, so that saving a name twice is an edit of that target. Answers
# whether it wrote, so that nothing compiles a target that is not on
# disk. The reason a write failed is reported by persist.vim.
export def SaveTarget(project: PO.Project, target: CompileTarget): bool
  var path: string = PathOf(project, target.name)
  return PE.WriteJson(path ==# '' ? FreeTargetPath(project, target.name) : path,
    target.ToDict())
enddef

# FUNCTION: Remove the definition that carries name, and answer whether
# it is gone, so that no caller reports a deletion that did not happen.
# Each cause is reported here, where it is known: a caller of this cannot
# tell a name nothing carried from a file it could not unlink, and the
# writer who asked was told the target was not there either way.
export def DeleteTarget(project: PO.Project, name: string): bool
  var path: string = PathOf(project, name)
  if path ==# ''
    log.Warn(MK.NothingToDelete(name))
    return false
  endif
  if delete(path) != 0
    log.Error(MK.DeleteFailed(path))
    return false
  endif
  # A name two files carried survives its own deletion, with the
  # settings of the file that was left out of the list.
  if PathOf(project, name) !=# ''
    log.Warn(MK.NameStillInUse(name))
  endif
  return true
enddef

# Contents selection: a tree buffer with a checkbox per document. It is
# separate from the settings popup, and all documents are included by
# default.

# Lines above the tree: the header and the project title. Every mapping
# from a cursor line to a row subtracts this.
const SELECT_HEADER_LINES: number = 2
# Only these top-level folders go into a compile, see ConcatenateManuscript
# and ConcatenateBook, so only their contents are listed.
const COMPILE_ROLES: list<string> = [
  CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT, CO.ROLE_BACK_MATTER,
]

class SelectState
  var project: PO.Project
  var rows: list<T.Row>
  var included: dict<bool>
  var OnDone: func(list<string>)

  def new(this.project, this.rows, this.included, this.OnDone)
  enddef
endclass

# FUNCTION: Return the Front Matter, Manuscript, and Back Matter folders
# and everything under them, in tree order. Characters, Research, and
# custom top-level folders are left out.
def SelectableRows(project: PO.Project): list<T.Row>
  var rows: list<T.Row> = []
  var inCompileRoot: bool = false
  for row in T.Flatten(project)
    if row.depth == 0
      inCompileRoot = index(COMPILE_ROLES, row.item.structureRole) >= 0
    endif
    if inCompileRoot
      rows->add(row)
    endif
  endfor
  return rows
enddef

def AllDocIds(project: PO.Project): list<string>
  return SelectableRows(project)
    ->filter((_, row) => row.item.IsDoc())
    ->mapnew((_, row) => row.item.id)
enddef

def RenderSelectLines(rows: list<T.Row>, included: dict<bool>): list<string>
  return rows->mapnew((_, row) => {
    var box: string = row.item.IsDoc()
      ? (get(included, row.item.id, false) ? '[x]' : '[ ]') : '   '
    var marker: string = row.item.IsFolder() ? '▸ ' : '· '
    # A trailing slash marks a folder, for the Directory highlight in
    # syntax/bartleby-compile-select.vim. Display only.
    var title: string = row.item.IsFolder() ? row.item.title .. '/' : row.item.title
    return repeat('  ', row.depth) .. box .. ' ' .. marker .. title
  })
enddef

def ToggleInclude(rows: list<T.Row>, included: dict<bool>, idx: number): void
  var item: BI.BinderItem = rows[idx].item
  if item.IsDoc()
    included[item.id] = !get(included, item.id, false)
    return
  endif
  var descendantIds: list<string> = []
  var i: number = idx + 1
  while i < len(rows) && rows[i].depth > rows[idx].depth
    if rows[i].item.IsDoc()
      descendantIds->add(rows[i].item.id)
    endif
    i += 1
  endwhile
  if empty(descendantIds)
    return
  endif
  var turnOn: bool = !get(included, descendantIds[0], false)
  for id in descendantIds
    included[id] = turnOn
  endfor
enddef

def RedrawSelect(): void
  var state: SelectState = b:bartleby_compile_select
  setlocal modifiable
  deletebufline('%', 1, '$')
  setline(1, [printf('*** %s ***', MC.Compile()), state.project.name]
    + RenderSelectLines(state.rows, state.included))
  setlocal nomodifiable
enddef

def DoToggle(): void
  var state: SelectState = b:bartleby_compile_select
  var lnum: number = line('.')
  var idx: number = lnum - 1 - SELECT_HEADER_LINES
  if idx < 0 || idx >= len(state.rows)
    return
  endif
  ToggleInclude(state.rows, state.included, idx)
  RedrawSelect()
  cursor(lnum, 1)
enddef

def DoConfirm(): void
  var state: SelectState = b:bartleby_compile_select
  var ids: list<string> = AllDocIds(state.project)->copy()
    ->filter((_, id) => get(state.included, id, false))
  var Cb: func(list<string>) = state.OnDone
  close
  Cb(ids)
enddef

export def SelectContents(project: PO.Project, preselected: list<string>,
    OnDone: func(list<string>)): void
  var included: dict<bool> = {}
  if empty(preselected)
    for id in AllDocIds(project)
      included[id] = true
    endfor
  else
    for id in preselected
      included[id] = true
    endfor
  endif

  execute 'vertical topleft :40split ' .. CO.COMPILE_SELECT_BUF
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable
  # Long titles wrap at word boundaries. shift:6 starts each wrapped line
  # under the title text, after the checkbox and marker.
  setlocal wrap linebreak breakindent breakindentopt=shift:6
  setlocal nonumber norelativenumber nofoldenable
  setlocal winfixwidth
  vertical resize 40
  setlocal filetype=bartleby-compile-select
  b:bartleby_compile_select = SelectState.new(project, SelectableRows(project), included, OnDone)

  RedrawSelect()
  cursor(SELECT_HEADER_LINES + 1, 1)
  nnoremap <buffer> <silent> x <ScriptCmd>DoToggle()<CR>
  nnoremap <buffer> <silent> <CR> <ScriptCmd>DoConfirm()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>close<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowSelectHelp()<CR>
enddef

# FUNCTION: Return each compile kind, as stored in a target, to its name
# in the message language.
def KindNames(): dict<string>
  return {
    [KIND_MANUSCRIPT]: MC.Manuscript(),
    [KIND_BOOK]: MK.Book(),
    [KIND_SCREENPLAY]: MC.Screenplay(),
  }
enddef

def ShowSelectHelp(): void
  H.Show(MK.CompileSelectContents(), [
    ['x', MK.ToggleInclusionFolders()],
    ['<CR>', MK.ConfirmSelContinue()],
    ['q', MC.Cancel()],
    ['?', MC.Help()],
  ])
enddef

# FUNCTION: Return the default font for a compile kind.

def DefaultFont(kind: string): string
  return kind ==# KIND_BOOK ? book_font : manuscript_font
enddef

# FUNCTION: Return true when saving a target under name would replace
# the definition of another target. A target saved under its own name is
# an edit of itself, which replaces nothing.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/59
export def Replaces(project: PO.Project, name: string,
    existing: CompileTarget): bool
  return (existing is null_object || existing.name !=# name)
    && LoadTarget(project, name) isnot null_object
enddef

# FUNCTION: Remove the definition of the name that target was renamed
# from, and save target over any definition of its own name.
# FUNCTION: Save target, and remove the definition of the name it was
# renamed from once it is written. In that order, because a delete that
# ran first and a write that then failed, on a full disk, left the
# writer with neither definition. The new one carries a suffixed stem
# while both are on disk, which no reader of a definition minds.
export def SaveOver(project: PO.Project, target: CompileTarget,
    existing: CompileTarget): bool
  if !SaveTarget(project, target)
    return false
  endif
  if existing isnot null_object && existing.name !=# target.name
    DeleteTarget(project, existing.name)
  endif
  return true
enddef

# FUNCTION: Save target and compile it, and compile nothing that a save
# did not write. Exported so that a test can reach the gate without
# driving the popups of the wizard.
export def SaveAndRun(project: PO.Project, target: CompileTarget,
    existing: CompileTarget): void
  if !SaveOver(project, target, existing)
    log.Error(MK.NotCompiled(target.name))
    return
  endif
  Execute(project, target)
enddef

# FUNCTION: Show the settings form: name, font, cover image for Book, and
# separator for all kinds except Screenplay. existing is null_object for a
# new target. For an edited target, it fills every field, and a changed
# name deletes the old definition once the question of a name another
# target carries is answered.
def FinishWizard(project: PO.Project, kind: string, format: string,
    doubleSpaced: bool, ids: list<string>, existing: CompileTarget): void
  var fields: list<list<string>> = [['name'], ['font']]
  if kind ==# KIND_BOOK
    fields->add(['coverimage'])
  endif
  if kind !=# KIND_SCREENPLAY
    fields->add(['separator'])
  endif
  var defaults: dict<any> = existing is null_object
    ? {font: DefaultFont(kind), separator: '* * *'}
    : {name: existing.name, font: existing.font, coverimage: existing.coverImage,
       separator: existing.separator}
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(fields), defaults,
    {title: printf(CO.TITLE_FMT, MK.CompileSettings()), labels: {
      name: MK.Name(), font: MK.Font(), coverimage: MK.CoverImg(),
      separator: MK.Sep()},
      complete: {coverimage: CO.COMPLETE_FILE}})
  form.OnSubmit((vals: dict<any>) => {
    var name: string = get(vals, 'name', '')
    if name ==# ''
      log.Error(MK.CompileTargetName())
      return
    endif
    var v: dict<any> = {}
    v.name = name
    v.kind = kind
    v.format = format
    v.font = get(vals, 'font', '')
    v.coverImage = get(vals, 'coverimage', '')
    v.doubleSpaced = doubleSpaced
    v.separator = get(vals, 'separator', '* * *')
    v.includedIds = ids
    var target: CompileTarget = CompileTarget.FromDict(v)
    if Replaces(project, name, existing)
      # What was kept, because Enter answers no here while every other
      # step of the wizard takes Enter for the answer that goes on, so a
      # writer may reach this without meaning to answer at all.
      DP.Confirm(MK.ReplaceCompileTarget(name), () => {
        SaveAndRun(project, target, existing)
      }, false, () => {
        log.Info(MK.KeptCompileTarget(name))
      })
      return
    endif
    SaveAndRun(project, target, existing)
  })
  form.Open()
enddef

# FUNCTION: Run the compile wizard: contents selection first, then kind,
# format, spacing for Manuscript, and the settings form. Each picker
# starts on the existing value when a target is edited.
def RunTargetForm(project: PO.Project, existing: CompileTarget): void
  var preselected: list<string> = existing is null_object ? [] : existing.includedIds
  var kindDefault: string = existing is null_object ? KIND_MANUSCRIPT : existing.kind
  SelectContents(project, preselected, (ids: list<string>) => {
    PI.PickOne(MK.CompileKind(), KINDS, (kind: string) => {
      var fmts: list<string> = get(KIND_FMTS, kind, [])
      var fmtDefault: string = (existing isnot null_object && existing.kind ==# kind)
        ? existing.format : fmts[0]
      PI.PickOne(MK.Fmt(), fmts, (format: string) => {
        if kind ==# KIND_MANUSCRIPT
          var spacingDefault: string = existing isnot null_object
            ? (existing.doubleSpaced ? SPACING_DOUBLE : SPACING_SINGLE)
            : (manuscript_double_spaced ? SPACING_DOUBLE : SPACING_SINGLE)
          PI.PickOne(MK.LineSpacing(), [SPACING_DOUBLE, SPACING_SINGLE], (spacing: string) => {
            FinishWizard(project, kind, format, spacing ==# SPACING_DOUBLE, ids, existing)
          }, spacingDefault, {[SPACING_DOUBLE]: MK.Double(), [SPACING_SINGLE]: MK.Single()})
        else
          FinishWizard(project, kind, format, true, ids, existing)
        endif
      }, fmtDefault)
    }, kindDefault, KindNames())
  })
enddef

def DeleteTargetConfirm(project: PO.Project, target: CompileTarget): void
  DP.Confirm(MK.DeleteCompileTarget(target.name), () => {
    if DeleteTarget(project, target.name)
      log.Info(MK.DeletedCompileTarget(target.name))
    endif
  })
enddef

##############################################################################
# SECTION: Execution.
##############################################################################

def OutputDir(project: PO.Project): string
  return project.scriveDir .. PATH_COMPILE_OUTPUT
enddef

def PluginRoot(): string
  return fnamemodify(compilescriptpath, ':h:h:h')
enddef

def ManuscriptTmplPath(): string
  return PluginRoot() .. PATH_TOOLS_LATEX_MANUSCRIPT_TEX
enddef

def BookTmplPath(): string
  return PluginRoot() .. PATH_TOOLS_LATEX_BOOK_TEX
enddef

def BookCssPath(): string
  return PluginRoot() .. PATH_TOOLS_CSS_BOOK_CSS
enddef

# FUNCTION: Return the table options of a compile of kind: border, vlines,
# and header, each the setting, or its fallback where the setting is
# unknown or kind cannot show it. An unknown line is single, so that none
# is lost to a misspelled name. An unknown header is bold, and so is small
# caps in a Manuscript, whose typewriter font has none.
export def TableOpts(kind: string, border: string, vlines: string, header: string): dict<string>
  var head: string = index(TABLE_HEADERS, header) >= 0 ? header : HEADER_FALLBACK
  if head ==# HEADER_SMALLCAPS && kind ==# KIND_MANUSCRIPT
    head = HEADER_FALLBACK
  endif
  return {
    border: index(TABLE_LINES, border) >= 0 ? border : LINE_FALLBACK,
    vlines: index(TABLE_LINES, vlines) >= 0 ? vlines : LINE_FALLBACK,
    header: head,
  }
enddef

# FUNCTION: Return the CSS of the table lines in opts, see TableOpts, for
# HTML and EPUB. Pandoc styles the header, see tools/pandoc/tables.lua.
export def TableCss(opts: dict<string>): list<string>
  return (opts.border !=# LINE_NONE ? [CSS_BORDER] : []) + (opts.vlines !=# LINE_NONE ? [CSS_VLINES] : [])
enddef

# FUNCTION: Return the Pandoc arguments for the tables of target: the
# filter, and the options in its metadata.
def TableArgs(opts: dict<string>): list<string>
  return [$'--lua-filter={PluginRoot()}{PATH_TOOLS_PANDOC_TABLES}',
    $'--metadata=table-header:{opts.header}',
    $'--metadata=table-border:{opts.border}',
    $'--metadata=table-vlines:{opts.vlines}']
enddef

# FUNCTION: Write the CSS that the settings add to book.css: the font, and
# the table lines, and return its path.
def WriteOverrideCss(outDir: string, font: string, opts: dict<string>): string
  var path: string = outDir .. '/.override.css'
  writefile([$'body {{ font-family: {font}, Georgia, serif; }}'] + TableCss(opts), path)
  return path
enddef

# FUNCTION: Turn level 2 and deeper headings into plain text, for
# Manuscript only. sffms has a bug: its ulem-based redefinition breaks a
# plain section command, with a Runaway argument error, also without this
# template or Pandoc. A manuscript has no subheadings anyway: scenes use
# the separator. Book does not use sffms and keeps its subheadings.
def FlattenSubheadings(lines: list<string>): list<string>
  return lines->mapnew((_, line) => substitute(line, '^#\{2,\}\s*', '', ''))
enddef

export def ConcatenateDocs(project: PO.Project, target: CompileTarget, separator: string): list<string>
  # Only the folders that compile, so that an included document that was
  # moved to the Trash is left out.
  var rows: list<T.Row> = SelectableRows(project)->filter((_, row) => row.item.IsDoc()
    && index(target.includedIds, row.item.id) >= 0)
  var lines: list<string> = []
  for i in range(len(rows))
    var path: string = rows[i].item.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Warn(MK.SkippingMissingFile(path))
      continue
    endif
    if i > 0
      lines += separator ==# '' ? [''] : ['', separator, '']
    endif
    # Links read as their text, but in a screenplay [[ ]] is a Fountain note.
    lines += target.kind ==# KIND_SCREENPLAY ? readfile(path) : LK.Plain(readfile(path))
  endfor
  return lines
enddef

def ReadDocLines(item: BI.BinderItem, binderRoot: string): list<string>
  var path: string = item.AbsPath(binderRoot)
  if !filereadable(path)
    log.Warn(MK.SkippingMissingFile(path))
    return []
  endif
  return LK.Plain(readfile(path))
enddef

# FUNCTION: Return true when lines start with a Markdown heading. Such a
# block marks its own start, so no separator goes before it. Plain prose,
# such as a scene, needs one.
def StartsWithHeading(lines: list<string>): bool
  return !empty(lines) && lines[0] =~# '^#\s'
enddef

def JoinSiblingBlocks(blocks: list<list<string>>, separator: string): list<string>
  var lines: list<string> = []
  var first: bool = true
  for block in blocks
    if empty(block)
      continue
    endif
    if !first
      lines += StartsWithHeading(block) || separator ==# '' ? [''] : ['', separator, '']
    endif
    lines += block
    first = false
  endfor
  return lines
enddef

# FUNCTION: Build Manuscript text. A Chapter folder becomes a heading with
# the folder title, never taken from the file content, followed by its
# scenes with separators between them. Other folders, Part included, add
# no heading: sffms has no safe level below chapter, and a manuscript
# shows no parts. A document directly in a folder is included unchanged.
def WalkManuscript(items: list<BI.BinderItem>, target: CompileTarget,
    binderRoot: string, separator: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDoc()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# CO.ROLE_CHAPTER
      var body: list<string> = WalkManuscript(item.children, target, binderRoot, separator)
      if !empty(body)
        blocks->add([$'# {item.title}', ''] + body)
      endif
    else
      blocks->add(WalkManuscript(item.children, target, binderRoot, separator))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# FUNCTION: Return true when an included item under items is a Part folder.
# This decides whether a Book uses level 1 for parts and level 2 for
# chapters, or level 1 for chapters.
def HasIncludedPart(items: list<BI.BinderItem>, includedIds: list<string>): bool
  for item in items
    if item.IsFolder()
      if item.structureRole ==# CO.ROLE_PART
        return true
      endif
      if HasIncludedPart(item.children, includedIds)
        return true
      endif
    endif
  endfor
  return false
enddef

# FUNCTION: Build Book text with real part and chapter divisions. book.tex
# has no sffms limit on depth. partLevel and chapterLevel are one or two
# number signs: a chapter is level 1 without parts and level 2 with them.
def WalkBook(items: list<BI.BinderItem>, target: CompileTarget, binderRoot: string,
    separator: string, partLevel: string, chapterLevel: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDoc()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# CO.ROLE_PART
      var body: list<string> = WalkBook(item.children, target, binderRoot, separator,
        partLevel, chapterLevel)
      if !empty(body)
        blocks->add([$'{partLevel} {item.title}', ''] + body)
      endif
    elseif item.structureRole ==# CO.ROLE_CHAPTER
      var body: list<string> = WalkBook(item.children, target, binderRoot, separator,
        partLevel, chapterLevel)
      if !empty(body)
        blocks->add([$'{chapterLevel} {item.title}', ''] + body)
      endif
    else
      blocks->add(WalkBook(item.children, target, binderRoot, separator, partLevel, chapterLevel))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# FUNCTION: Build Front Matter or Back Matter text, for Manuscript and
# Book. Each document gets its own unnumbered heading, the Pandoc {-}
# attribute, which LaTeX shows as an unnumbered chapter. Front and back
# matter are separate pieces, such as a dedication and acknowledgments,
# not one block. Nested folders are walked but get no heading.
def WalkFrontOrBackMatter(items: list<BI.BinderItem>, target: CompileTarget,
    binderRoot: string, separator: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDoc()
      if index(target.includedIds, item.id) >= 0
        blocks->add(['# ' .. item.title .. ' {-}', ''] + ReadDocLines(item, binderRoot))
      endif
    else
      blocks->add(WalkFrontOrBackMatter(item.children, target, binderRoot, separator))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# FUNCTION: Return the top-level item with the given role. Front Matter,
# Manuscript, and Back Matter are always top-level, so a flat scan is
# enough.
def FindTopLevelItem(items: list<BI.BinderItem>, role: string): BI.BinderItem
  for item in items
    if item.structureRole ==# role
      return item
    endif
  endfor
  return null_object
enddef

# FUNCTION: Return a Pandoc raw LaTeX block, copied to the LaTeX output
# unchanged. This is how the frontmatter, mainmatter, and backmatter
# commands of the book class get into a compile built from Markdown.
def RawLatex(cmd: string): list<string>
  return ['```{=latex}', cmd, '```', '']
enddef

export def ConcatenateManuscript(project: PO.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_BACK_MATTER)
  var binderRoot: string = project.BinderRoot()

  if frontMatter isnot null_object
    blocks->add(WalkFrontOrBackMatter(frontMatter.children, target, binderRoot, target.separator))
  endif
  if manuscript isnot null_object
    blocks->add(WalkManuscript(manuscript.children, target, binderRoot, target.separator))
  endif
  if backMatter isnot null_object
    blocks->add(WalkFrontOrBackMatter(backMatter.children, target, binderRoot, target.separator))
  endif
  return JoinSiblingBlocks(blocks, target.separator)
enddef

export def ConcatenateBook(project: PO.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_BACK_MATTER)
  var binderRoot: string = project.BinderRoot()
  var hasPart: bool = manuscript isnot null_object
    && HasIncludedPart(manuscript.children, target.includedIds)
  var partLevel: string = '#'
  var chapterLevel: string = hasPart ? '##' : '#'

  var frontBody: list<string> = frontMatter isnot null_object
    ? WalkFrontOrBackMatter(frontMatter.children, target, binderRoot, target.separator) : []
  if !empty(frontBody)
    blocks->add(RawLatex('\frontmatter') + frontBody)
  endif

  var mainBody: list<string> = manuscript isnot null_object
    ? WalkBook(manuscript.children, target, binderRoot, target.separator, partLevel, chapterLevel)
    : []
  if !empty(mainBody)
    blocks->add((empty(frontBody) ? [] : RawLatex('\mainmatter')) + mainBody)
  endif

  var backBody: list<string> = backMatter isnot null_object
    ? WalkFrontOrBackMatter(backMatter.children, target, binderRoot, target.separator) : []
  if !empty(backBody)
    blocks->add(RawLatex('\backmatter') + backBody)
  endif

  # No separator here, unlike every other JoinSiblingBlocks call. These
  # three blocks are structural transitions: frontmatter, mainmatter, and
  # backmatter already start new pages, so a scene separator between them
  # would be a stray mark. StartsWithHeading cannot detect this, because
  # each block starts with a raw LaTeX line, not a heading.
  return JoinSiblingBlocks(blocks, '')
enddef

# FUNCTION: Join the nonempty parts with sep. Empty parts leave no stray
# separator.
def JoinNonEmpty(parts: list<string>, sep: string): string
  return join(parts->copy()->filter((_, p) => p !=# ''), sep)
enddef

# FUNCTION: Return City, State, Country Zip. Missing parts are left out,
# with no stray comma or space.
def CityStateLine(info: PR.ProjInfo): string
  var cityState: string = JoinNonEmpty([info.city, info.state], ', ')
  var cityStateCountry: string = JoinNonEmpty([cityState, info.countrycode], ', ')
  return JoinNonEmpty([cityStateCountry, info.zip], ' ')
enddef

def CountWords(lines: list<string>): number
  return len(split(join(lines, ' ')))
enddef

# FUNCTION: Convert a numbering style to the two booleans that book.tex
# uses: whether to show the word Chapter or Part, and whether to spell
# the number with fmtcount. Styles: numeral, spelled, bare-numeral, and
# bare-spelled.
def BookNumStyleArgs(prefix: string, style: string): list<string>
  var bare: string = style =~# '^bare' ? 'true' : 'false'
  var spelled: string = style =~# 'spelled' ? 'true' : 'false'
  return [$'--metadata={prefix}bare:{bare}', $'--metadata={prefix}spelled:{spelled}']
enddef

# FUNCTION: Return the Pandoc metadata arguments for a Manuscript, which
# only sffms uses. usecourier maps the target font to the Courier switch
# of sffms, which does not use fontspec, so other font names do not
# apply. manuscript.tex explains more.
def ManuscriptMetadataArgs(project: PO.Project, target: CompileTarget,
    mdLines: list<string>): list<string>
  var args: list<string> = [$'--metadata=wordcount:{CountWords(mdLines)}']
  if project.projectType ==# CO.TYPE_NOVEL || project.projectType ==# CO.TYPE_NOVEL_PARTS
    args->add(ARG_NOVEL)
  endif
  if target.font =~? COURIER
    args->add(ARG_COURIER)
  endif
  if !target.doubleSpaced
    args->add(ARG_SINGLE)
  endif
  return args
enddef

def PandocMetadataArgs(project: PO.Project): list<string>
  var info: PR.ProjInfo = PR.Resolve(project)
  var args: list<string> = [$'--metadata=title:{project.name}']
  if info.EffectiveAuthor() !=# ''
    args->add($'--metadata=author:{info.EffectiveAuthor()}')
  endif
  # realname, the full legal name, is for the contact block on
  # the title page. author is the byline, which may be a pen name.
  if info.FullName() !=# ''
    args->add($'--metadata=realname:{info.FullName()}')
  endif
  # The surname heads every manuscript page, as surname / TITLE / page.
  if info.surname !=# ''
    args->add($'--metadata=surname:{info.surname}')
  endif
  if info.address !=# ''
    args->add($'--metadata=address:{info.address}')
  endif
  var cityStateLine: string = CityStateLine(info)
  if cityStateLine !=# ''
    args->add($'--metadata=citystateline:{cityStateLine}')
  endif
  if info.phonenumber !=# ''
    args->add($'--metadata=phonenumber:{info.phonenumber}')
  endif
  if info.email !=# ''
    args->add($'--metadata=email:{info.email}')
  endif
  return args
enddef

# FUNCTION: Return what the name of an artifact may take under dir with
# ext. It reserves what PathRoom reserves, although an artifact takes no
# suffix, because a budget computed to the byte against a limit that no
# test on a writer's own system can reach has twice been wrong.
export def OutputRoom(dir: string, ext: string): number
  return MAX_PATH_BYTES
    - strlen($'{dir}/{SU.DEVICE_PREFIX}{SUFFIX_ROOM}.{ext}{PE.TMP_SUFFIX}')
enddef

# FUNCTION: Return the extension of the file that target compiles to.
def ExtOf(target: CompileTarget): string
  return get(target.kind ==# KIND_SCREENPLAY ? SCREENPLAY_EXT : PANDOC_EXT,
    target.format, EXT_DEFAULT)
enddef

# FUNCTION: Return the path that the output of a target belongs at: its
# own folder, under the name the writer gave the target, with ext. The
# engines compile to a slug, because a TeX engine is unreliable with a
# path outside ASCII, so the name is taken afterwards, by a rename. The
# name is budgeted against the whole path, never to nothing, as the name
# of a definition is.
export def FinalPath(path: string, name: string, ext: string): string
  var dir: string = fnamemodify(path, ':h')
  var safe: string = SU.Safe(name, max([OutputRoom(dir, ext), 1]))
  return safe ==# '' ? path : $'{dir}/{safe}.{ext}'
enddef

# FUNCTION: Return the path that the artifact of target belongs at: the
# name the writer gave the target, or the path the engine wrote when the
# name of another target reaches the same file. A volume holds one of
# those two names at a time and nothing on disk says which target owns
# the file, so neither takes it: the compile of one target deleted the
# finished file of the other and renamed its own over it. The engine's
# path holds one target alone, see WorkName.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/64
export def ArtifactPath(project: PO.Project, target: CompileTarget,
    outputPath: string, ext: string): string
  var final: string = FinalPath(outputPath, target.name, ext)
  if final ==# outputPath
    return outputPath
  endif
  var tail: string = fnamemodify(final, ':t')
  # What this file system does with the name, because the answer pairs
  # with a real file, see Folded in path.vim.
  var wanted: string = PA.Folded(tail)
  for path in TargetFiles(project)
    var other: CompileTarget = CompileTarget.FromDict(PE.ReadJson(path))
    # A definition that carries no name is damaged, see PathOf, and a
    # target is the name the writer gave it, so a second file of that
    # name is the same target, see ListTargets. A target that compiles
    # to another extension writes another file.
    if other.name ==# '' || other.name ==# target.name || ExtOf(other) !=# ext
      continue
    endif
    # The file that the other target takes, and the file that its engine
    # writes, under the stem of its definition: a name that is a slug
    # already reaches such a stem, and a rename onto a file that an
    # engine is still writing loses the text of both targets.
    var taken: string = fnamemodify(FinalPath(outputPath, other.name, ext), ':t')
    var written: string = $'{fnamemodify(path, ":t:r")}.{ext}'
    if PA.Folded(taken) ==# wanted || PA.Folded(written) ==# wanted
      log.Warn(MK.ArtifactNameShared(tail, other.name,
        fnamemodify(outputPath, ':t')))
      return outputPath
    endif
  endfor
  return final
enddef

# FUNCTION: Give the output the name of its target, then offer to open
# it. A rename that fails leaves the artifact where the engine wrote it
# and offers that, because the compile itself succeeded.
def Finish(target: CompileTarget, outputPath: string, finalPath: string): void
  var final: string = finalPath
  if final !=# outputPath
    # A recompile overwrites its output, so the rename does too. The
    # second test keeps a rename that only changes case from deleting the
    # file it is about to move, where one name reaches both. It folds
    # whatever this system does, because fileignorecase answers for the
    # platform rather than for the volume.
    if filereadable(final) && tolower(final) !=# tolower(outputPath)
      delete(final)
    endif
    if rename(outputPath, final) != 0
      log.Warn(MK.RenameFailed(outputPath, fnamemodify(final, ':t')))
      final = outputPath
    endif
  endif
  OfferToOpen(target, final)
enddef

# FUNCTION: Ask whether to open the compiled file, with yes as the
# default. Markdown opens in a new tab, so that no scrive window is
# replaced. Every other format opens in the system viewer with Vim's
# dist#vim9#Open, the function behind :Open.
def OfferToOpen(target: CompileTarget, outputPath: string): void
  log.Info(MK.Compiled(fnamemodify(outputPath, ":~")))
  DP.Confirm(MK.CompiledOpen(target.name), () => {
    if target.format ==# FMT_MARKDOWN
      execute 'tabedit ' .. fnameescape(outputPath)
    else
      DV.Open(outputPath)
    endif
  }, true)
enddef

# FUNCTION: Take key out of the compiles that are running.
def Ended(key: string): void
  if has_key(running, key)
    remove(running, key)
  endif
enddef

# FUNCTION: Run a compile command, under key, which no other run may hold
# while this one has it. On success, offer to open the output. On
# failure, write the command's error output to logBase .. '.log' and
# offer to open that log in a new tab. Pandoc writes its own log only on
# success, so this failure log is the only record of what went wrong.
def RunJob(label: string, cmd: list<string>, target: CompileTarget,
    outputPath: string, finalPath: string, logBase: string, key: string): void
  var errLines: list<string> = []
  log.Info(MK.Compiling(target.name, label))
  var job: job = job_start(cmd, {
    err_cb: (_, line) => errLines->add(line),
    exit_cb: (_, status) => {
      Ended(key)
      if status ==# 0
        Finish(target, outputPath, finalPath)
      else
        log.Error(MK.ExitedStatus(cmd[0], status, join(errLines, " | ")))
        OfferFailureLog(target, WriteFailureLog(logBase .. EXT_LOG, cmd, status, errLines))
      endif
    },
  })
  # Held only once the job is running. A job that never started calls no
  # exit callback, so a key set before this would stay and refuse every
  # later compile of that target.
  if job_status(job) !=# JOB_FAIL
    running[key] = true
  endif
enddef

# FUNCTION: Write a failed command, its exit status, and its error output
# to path, and return path.
def WriteFailureLog(path: string, cmd: list<string>, status: number,
    errLines: list<string>): string
  var lines: list<string> = [
    MK.Cmd(join(cmd, " ")),
    MK.ExitStatus(status),
    '',
  ]
  # Answers with nothing when it could not write, so that the offer to
  # open the log is not made for a file that is not there. A throw here
  # would leave the exit callback of the job, which nothing catches.
  if writefile(lines + (empty(errLines) ? [MK.NoErrOutput()] : errLines),
      path) != 0
    return ''
  endif
  return path
enddef

# FUNCTION: Ask whether to open the failure log, with yes as the default.
# It opens in a new tab, so that no scrive window is replaced.
def OfferFailureLog(target: CompileTarget, path: string): void
  if path ==# ''
    return
  endif
  DP.Confirm(MK.CompilingFailedOpen(target.name), () => {
    execute 'tabedit ' .. fnameescape(path)
  }, true)
enddef

def ExecuteScreenplay(project: PO.Project, target: CompileTarget,
    work: string, key: string): void
  if !executable(screenplain_bin)
    log.Error(MK.ScreenplainNotFound(screenplain_bin))
    return
  endif
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = ExtOf(target)
  var outputPath: string = $'{outDir}/{work}.{ext}'
  var fountainPath: string = $'{outDir}/.{work}-src.fountain'
  writefile(ConcatenateDocs(project, target, ''), fountainPath)
  RunJob($'{target.kind}/{target.format}', [screenplain_bin, fountainPath, outputPath],
    target, outputPath, ArtifactPath(project, target, outputPath, ext),
    NewLogBase(project, work), key)
enddef

def BuildDocLines(project: PO.Project, target: CompileTarget): list<string>
  if target.kind ==# KIND_MANUSCRIPT
    return FlattenSubheadings(ConcatenateManuscript(project, target))
  elseif target.kind ==# KIND_BOOK
    return ConcatenateBook(project, target)
  else
    return ConcatenateDocs(project, target, target.separator)
  endif
enddef

# FUNCTION: Return a cover image path as a full path, or an empty string for
# none. fnamemodify, not expand, so that a name such as cover[1].png is never
# read as a pattern. A path that starts with ~/ is in the home folder, and a
# relative one is from the current directory, which Pandoc runs in.
export def CoverPath(path: string): string
  return path ==# '' ? '' : fnamemodify(path, ':p')
enddef

# FUNCTION: Return true when the target uses its cover image: a Book in PDF
# or EPUB. The other formats leave it out.
def UsesCover(target: CompileTarget): bool
  return target.kind ==# KIND_BOOK && (target.format ==# FMT_PDF || target.format ==# FMT_EPUB)
enddef

# FUNCTION: Return true when TeX can make the PDF of target: it has the
# engine, and every class and package that the template needs, see
# texcheck.vim. Otherwise log what is missing, which LaTeX reports only as
# an error in its log, and return false. An engine that extra_args names is
# not checked.
def TexReady(target: CompileTarget, docLines: list<string>, lang: string): bool
  var isMs: bool = target.kind ==# KIND_MANUSCRIPT
  var engine: string = isMs ? PDFLATEX : XELATEX
  var ownEngine: bool = !empty(extra_args->copy()->filter((_, a) => a =~# '^' .. ARG_ENGINE))
  if !ownEngine && !executable(engine)
    log.Error(MK.EngineNotFound(engine))
    return false
  endif
  var tmpl: list<string> = readfile(isMs ? ManuscriptTmplPath() : BookTmplPath())
  var missing: list<string> = TX.Missing(tmpl, {tables: TB.HasTable(docLines), lang: lang !=# ''})
  if !empty(missing)
    log.Error(MK.MissingTex(target.kind, join(missing, ', ')))
    return false
  endif
  return true
enddef

def ExecutePandoc(project: PO.Project, target: CompileTarget,
    work: string, key: string): void
  var cover: string = UsesCover(target) ? CoverPath(target.coverImage) : ''
  # Check before Pandoc runs, which would fail on the missing file with a
  # less helpful message.
  if cover !=# '' && !filereadable(cover)
    log.Error(MK.CoverNotFound(cover))
    return
  endif
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = ExtOf(target)
  var outputPath: string = $'{outDir}/{work}.{ext}'

  if target.format ==# FMT_MARKDOWN
    writefile(BuildDocLines(project, target), outputPath)
    Finish(target, outputPath, ArtifactPath(project, target, outputPath, ext))
    return
  endif

  if !executable(pandoc_bin)
    log.Error(MK.PandocNotFound(pandoc_bin))
    return
  endif

  var mdPath: string = $'{outDir}/.{work}-src.md'
  var docLines: list<string> = BuildDocLines(project, target)
  writefile(docLines, mdPath)

  var tblOpts: dict<string> = TableOpts(target.kind, table_border, table_vlines, table_header)
  var args: list<string> = [mdPath, '-o', outputPath] + PandocMetadataArgs(project) + TableArgs(tblOpts)
  if standalone
    args->add(FLAG_STANDALONE)
  endif
  if toc
    args->add(FLAG_TOC)
  endif

  if target.kind ==# KIND_MANUSCRIPT
    # Pandoc's default engine, pdflatex. manuscript.tex explains why.
    args->add($'--template={ManuscriptTmplPath()}')
    # Required. Pandoc cannot tell that the custom sffms class is based on
    # report, so without this it maps level 1 headings to sections, sffms
    # chapter styling does not apply, and its numbering collides with the
    # heading text.
    args->add(ARG_CHAPTERS)
    args += ManuscriptMetadataArgs(project, target, docLines)
  elseif target.kind ==# KIND_BOOK
    args->add($'--variable=mainfont:{target.font}')
    if target.format ==# FMT_PDF
      args->add(ARG_XELATEX)
      args->add($'--template={BookTmplPath()}')
      var hasPart: bool = HasIncludedPart(project.items->copy()->filter((_, item) => item.structureRole !=# CO.ROLE_TRASH),
        target.includedIds)
      args->add($'--top-level-division={hasPart ? "part" : "chapter"}')
      args->add($'--variable=indentparagraphs:{indent_paras ? "true" : "false"}')
      args += BookNumStyleArgs(CO.ROLE_CHAPTER, book_chapter_style)
      args += BookNumStyleArgs(CO.ROLE_PART, book_part_style)
      if cover !=# ''
        args->add($'--variable=cover-image:{cover}')
      endif
    else
      args->add($'--css={BookCssPath()}')
      args->add($'--css={WriteOverrideCss(outDir, target.font, tblOpts)}')
      if target.format ==# FMT_EPUB && cover !=# ''
        args->add($'--epub-cover-image={cover}')
      endif
    endif
  endif
  # The language of the text, for Pandoc: the lang attribute in HTML, the
  # EPUB language, and LaTeX templates that use $lang$. An empty setting
  # means the pandoc_lang of the language file.
  var lang: string = compile_lang ==# '' ? LA.Get('pandoc_lang', '') : compile_lang
  if lang !=# ''
    args->add($'--metadata=lang:{lang}')
  endif
  args->add($'--metadata=papersize:{PaperSize()}')
  args += extra_args
  if target.format ==# FMT_PDF && !TexReady(target, docLines, lang)
    return
  endif
  var logBase: string = NewLogBase(project, work)
  args->add($'--log={logBase}.json')

  RunJob($'{target.kind}/{target.format}', [pandoc_bin] + args, target, outputPath,
    ArtifactPath(project, target, outputPath, ext), logBase, key)
enddef

# FUNCTION: Return the paper size for PDF: g:bartleby_compile_papersize
# when set, else the papersize of the language file. letter and a4 are the
# sizes that sffms supports, so any other value warns and uses letter.
def PaperSize(): string
  var size: string = papersize ==# '' ? LA.Get('papersize', 'letter') : papersize
  if index(['letter', A4], size) < 0
    log.Warn(MK.UnknownPaperSize(size))
    return LETTER
  endif
  return size
enddef

# FUNCTION: Return a new timestamped log path for this run, without an
# extension:
#   ~/.bartleby/logs/<scrive>_<target>_<YYYYmmdd-HHMMSS>
# Pandoc writes .json there through its log option, but only on success.
# On failure, RunJob writes .log there with the error output. Keep the
# newest g:bartleby_compile_log_retention logs per scrive and target,
# this run included, and delete the rest. 0 keeps every log.
# FUNCTION: Return what every log name of one target in one scrive
# begins with. Both names are budgeted, because the component holds two
# of them and a path component holds 255 bytes, which the timestamp and
# the longest extension written beside it, .json, share. Unbudgeted, a
# scrive of an ordinary name and a target at the cap gave a name the
# system refused, so pandoc wrote no log at all and the compile failed
# with nothing from Bartleby to say why. Taken apart from the name it
# begins so that a test can measure it without trimming the writer's
# own logs.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/61
export def LogPrefix(scriveDir: string, work: string): string
  return SU.Slugify(fnamemodify(scriveDir, ':t:r'), LOG_NAME_BYTES)
    .. '_' .. SU.Safe(work, LOG_NAME_BYTES) .. '_'
enddef

def NewLogBase(project: PO.Project, work: string): string
  var logDir: string = expand('~/.bartleby/logs')
  if !isdirectory(logDir)
    mkdir(logDir, 'p')
  endif
  var prefix: string = LogPrefix(project.scriveDir, work)
  if log_retention > 0
    # nosuf true, or a wildignore of the writer leaves the logs untrimmed.
    var older: list<string> = sort(glob($'{logDir}/{prefix}[0-9]*.*', true, true))
    var excess: number = len(older) - (log_retention - 1)
    if excess > 0
      for path in older[0 : excess - 1]
        delete(path)
      endfor
    endif
  endif
  return $'{logDir}/{prefix}{strftime("%Y%m%d-%H%M%S")}'
enddef

export def Execute(project: PO.Project, target: CompileTarget): void
  var work: string = WorkName(project, target)
  var key: string = $'{OutputDir(project)}/{work}'
  # A second run under one key would rewrite the file its engine is
  # still reading and write over the file that engine is producing.
  if has_key(running, key)
    log.Warn(MK.AlreadyCompiling(target.name))
    return
  endif
  if target.kind ==# KIND_SCREENPLAY
    ExecuteScreenplay(project, target, work, key)
  else
    ExecutePandoc(project, target, work, key)
  endif
enddef

# FUNCTION: Pick a saved target and run it, or build a new one. The entry
# point of :BartlebyCompile.

export def Run(project: PO.Project): void
  var names: list<string> = ListTargets(project)
  var options: list<string> = names + [NEW_TARGET]
  PI.PickOne(MC.Compile(), options, (choice: string) => {
    if choice ==# NEW_TARGET
      RunTargetForm(project, null_object)
      return
    endif
    var target: CompileTarget = LoadTarget(project, choice)
    if target is null_object
      log.Error(MK.TargetNotFound(choice))
      return
    endif
    PI.PickOne(MK.Msg(choice), [ACTION_RUN, ACTION_EDIT, ACTION_DELETE], (action: string) => {
      if action ==# ACTION_RUN
        Execute(project, target)
      elseif action ==# ACTION_EDIT
        RunTargetForm(project, target)
      elseif action ==# ACTION_DELETE
        DeleteTargetConfirm(project, target)
      endif
    }, '', {[ACTION_RUN]: MK.Run(), [ACTION_EDIT]: MK.Edit(), [ACTION_DELETE]: MK.Delete()})
  }, '', {[NEW_TARGET]: MK.NewTarget()})
enddef
