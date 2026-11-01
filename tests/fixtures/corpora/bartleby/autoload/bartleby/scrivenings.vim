vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# scrivenings.vim: a Scrivening shows the documents of a Manuscript folder,
# and of the folders inside it, in Binder order, in one buffer, so that
# they read and edit as one text. A title line starts each document, as in
# the line ── Chapter: 2 / Scene 1 ──, and a text property marks it, with
# the number of the document as its id, so that the line moves with edits
# and names the file of the lines below it.
#
# The title lines are protected: a change to one in Normal mode is undone,
# Backspace and Delete do not join text to one in Insert mode, and the
# cursor does not stay on one in Insert mode. Saving writes only the
# documents whose text changed, and writes nothing when a title line is
# damaged, so that no text goes to another document.
#
# A document opens in one place only. Opening a Scrivening saves and
# closes the documents of the folder that are open on their own, and while
# it is open, a document of the folder opened any other way shows in the
# Scrivening instead, at the same line.
#
# One Scrivening is open at a time.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/wordcount.vim' as WC
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/writing.vim' as MW
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

const COMMENT_FLAGS: string = 'b:'
const KEY_NAME_C_H: string = '<C-h>'
const KEY_NAME_C_W: string = '<C-w>'
const KEY_NAME_C_U: string = '<C-u>'
const KEYS_UP_UP: string = "\<Up>\<Up>"
const KEYS_DOWN_DOWN: string = "\<Down>\<Down>"

var log = L.New(expand('<sfile>:t'))

# The text property of a title line. Its id is the number of its document.
const PROP_TITLE: string = 'BartlebyScriveningTitle'
const TITLE_LEAD: string = '── '
const TITLE_TAIL: string = ' ──'
# The User event when the cursor enters another document of a Scrivening,
# for the Inspector to follow it.
export const SECTION_EVENT: string = 'BartlebyScriveningSection'

# The open Scrivening: its buffer, its folder, and for each document its
# id, file, title line, and text as last read or written. Empty when no
# Scrivening is open.
var current: dict<any> = {}

# FUNCTION: Return true when bufNr is the buffer of the open Scrivening.
export def IsScrivening(bufNr: number): bool
  return !empty(current) && current.bufnr == bufNr && bufexists(bufNr)
enddef

# FUNCTION: Return true when a Scrivening is open with unsaved changes.
export def IsModified(): bool
  return !empty(current) && bufexists(current.bufnr) && getbufvar(current.bufnr, '&modified')
enddef

# FUNCTION: Return the label of folder in a title line: its title, after
# Chapter or Part for those roles.
def FolderLabel(folder: BI.BinderItem): string
  if folder.structureRole ==# CO.ROLE_CHAPTER
    return MC.Chapter() .. ': ' .. folder.title
  elseif folder.structureRole ==# CO.ROLE_PART
    return MC.Part() .. ': ' .. folder.title
  endif
  return folder.title
enddef

# FUNCTION: Return the documents of folder and of the folders inside it, in
# Binder order, each with its label: the folders below folder, then its
# title, as in Chapter: 2 / Scene 1.
def DocsOf(folder: BI.BinderItem): list<list<any>>
  var found: list<list<any>> = []
  def Walk(items: list<BI.BinderItem>, labels: list<string>): void
    for item in items
      if item.IsDoc()
        found->add([item, join(labels + [item.title], ' / ')])
      else
        Walk(item.children, labels + [FolderLabel(item)])
      endif
    endfor
  enddef
  Walk(folder.children, [])
  return found
enddef

# FUNCTION: Return true when folder is the Manuscript or a folder inside
# it, where a Scrivening can open.
export def CanOpen(project: PO.Project, folder: BI.BinderItem): bool
  var row: T.Row = T.FindRowById(T.Flatten(project), folder.id)
  return row isnot null_object && folder.IsFolder() && row.topItem isnot null_object
    && row.topItem.structureRole ==# CO.ROLE_MANUSCRIPT
enddef

# FUNCTION: Open a Scrivening of folder, with the cursor offset lines into
# the document with docId, or into the document of the current buffer
# when it is one of the folder. Returns false, with a message, when it
# does not open.
export def Open(project: PO.Project, folder: BI.BinderItem, docId: string = '', offset: number = 0): bool
  if !CanOpen(project, folder)
    log.Info(MC.ScriveningOpensOnly())
    return false
  endif
  var docs: list<list<any>> = DocsOf(folder)
  if empty(docs)
    log.Info(MW.FolderHasNo())
    return false
  endif
  if !empty(current) && !Close()
    return false
  endif
  var root: string = project.BinderRoot()
  # The files as the scrive names them, because they are written by that
  # name, and the ids by the one spelling of a path, because the name that
  # Vim answers for the current buffer carries the separator of its own
  # system, see path.vim.
  var paths: list<string> = []
  var idByPath: dict<string> = {}
  for [doc, _] in docs
    var path: string = doc.AbsPath(root)
    paths->add(path)
    idByPath[PA.Canon(path)] = doc.id
  endfor
  # The document of the current buffer gives the place of the cursor.
  var cursorId: string = docId
  var cursorOffset: number = offset
  var here: string = PA.Canon(expand('%:p'))
  if cursorId ==# '' && has_key(idByPath, here)
    cursorId = idByPath[here]
    cursorOffset = line('.') - 1
  endif
  var members: list<number> = SaveMemberBufs(paths)
  if !has_key(idByPath, here)
    W.GoToEditorWin()
  endif
  hide enew
  setlocal buftype=acwrite bufhidden=hide noswapfile
  execute 'silent file ' .. fnameescape(CO.SCRIVENINGS_BUF)
  &l:filetype = project.DocExt() ==# CO.EXT_FOUNTAIN ? CO.FILETYPE_FOUNTAIN : CO.FILETYPE_MARKDOWN
  current = {bufnr: bufnr(), folderId: folder.id, section: -1}
  Build(project, docs)
  SetupBuf()
  for bufNr in members
    if bufexists(bufNr)
      execute 'silent! bwipe ' .. bufNr
    endif
  endfor
  GoToDoc(cursorId, cursorOffset)
  StartRedirect()
  # The buffer was entered before it was a Scrivening, so the features that
  # apply to documents on entry, such as Quill, did not see it as one.
  doautocmd <nomodeline> BufEnter
  return true
enddef

# FUNCTION: Save the changes of the documents in paths that are open in
# buffers, so that the Scrivening shows them. Returns their buffers.
def SaveMemberBufs(paths: list<string>): list<number>
  var found: list<number> = []
  var bufs: dict<number> = WC.LoadedBufs()
  for path in paths
    var bufNr: number = WC.LoadedBuf(bufs, path)
    if bufNr < 0
      continue
    endif
    var info: dict<any> = getbufinfo(bufNr)[0]
    if info.changed
      writefile(getbufline(info.bufnr, 1, '$'), path)
      setbufvar(info.bufnr, '&modified', 0)
    endif
    found->add(info.bufnr)
  endfor
  return found
enddef

# FUNCTION: Fill the Scrivening buffer with docs, a title line before each,
# and remember their files and texts. The filling cannot be undone. An
# empty document shows as one empty line, to type in.
def Build(project: PO.Project, docs: list<list<any>>): void
  var bufNr: number = current.bufnr
  var root: string = project.BinderRoot()
  var lines: list<string> = []
  var titleLines: list<number> = []
  current.ids = []
  current.paths = []
  current.titles = []
  current.saved = []
  for [doc, label] in docs
    var title: string = TITLE_LEAD .. label .. TITLE_TAIL
    var path: string = doc.AbsPath(root)
    var text: list<string> = filereadable(path) ? readfile(path) : []
    titleLines->add(len(lines) + 1)
    lines->add(title)
    lines += empty(text) ? [''] : text
    current.ids->add(doc.id)
    current.paths->add(path)
    current.titles->add(title)
    current.saved->add(text)
  endfor
  if empty(prop_type_get(PROP_TITLE))
    prop_type_add(PROP_TITLE, {highlight: 'Title'})
  endif
  var undolevels: number = getbufvar(bufNr, '&undolevels')
  setbufvar(bufNr, '&undolevels', -1)
  deletebufline(bufNr, 1, '$')
  setbufline(bufNr, 1, lines)
  for i in range(len(titleLines))
    prop_add(titleLines[i], 1, {type: PROP_TITLE, id: i + 1, length: strlen(current.titles[i]), bufnr: bufNr})
  endfor
  setbufvar(bufNr, '&undolevels', undolevels)
  setbufvar(bufNr, '&modified', 0)
enddef

# FUNCTION: Set the commands and keys of the Scrivening buffer: saving,
# the protection of the title lines, and the section events.
def SetupBuf(): void
  # Paragraph formatting never joins lines with different comment leaders,
  # so with the title mark as one, formatting, as in the auto mode of
  # Quill, leaves the title lines alone.
  &l:comments = COMMENT_FLAGS .. trim(TITLE_LEAD)
  augroup bartleby_scrivening
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> Write()
    autocmd TextChanged <buffer> Protect()
    autocmd InsertEnter <buffer> EnterInsert()
    autocmd CursorMovedI <buffer> LeaveTitleLine()
    autocmd CursorMoved,CursorMovedI <buffer> NotifySection()
    autocmd BufUnload <buffer> Discard()
  augroup END
  for key in ['<BS>', KEY_NAME_C_H, KEY_NAME_C_W, KEY_NAME_C_U]
    execute $'inoremap <buffer> <expr> {key} <SID>AtSectionStart() ? "" : "\{key}"'
  endfor
  inoremap <buffer> <expr> <Del> <SID>AtSectionEnd() ? "" : "\<Del>"
  MapArrows()
enddef

# FUNCTION: Map Up and Down in Insert mode in the Scrivening buffer. A move
# onto a title line goes past it. Any other move uses up and down, so
# that Quill, which moves by screen lines, calls this instead of mapping
# the arrow keys itself, and the title lines stay passable.
export def MapArrows(up: string = CO.KEY_UP, down: string = CO.KEY_DOWN): void
  b:bartleby_scrivening_arrows = [up, down]
  inoremap <buffer> <expr> <Up> <SID>KeyUp()
  inoremap <buffer> <expr> <Down> <SID>KeyDown()
enddef

# FUNCTION: Return the lines of each document, in order, or an empty list
# when a title line is missing, out of order, or changed. A document of
# one empty line is empty.
def Sections(): list<list<string>>
  var bufNr: number = current.bufnr
  var props: list<dict<any>> = prop_list(1, {bufnr: bufNr, end_lnum: -1, types: [PROP_TITLE]})
  var count: number = len(current.titles)
  if len(props) != count
    return []
  endif
  var lineCount: number = getbufinfo(bufNr)[0].linecount
  var sections: list<list<string>> = []
  for i in range(count)
    var title: dict<any> = props[i]
    if title.id != i + 1 || getbufline(bufNr, title.lnum)[0] !=# current.titles[i]
      return []
    endif
    var last: number = i + 1 < count ? props[i + 1].lnum - 1 : lineCount
    var lines: list<string> = title.lnum < last ? getbufline(bufNr, title.lnum + 1, last) : []
    sections->add(lines == [''] ? [] : lines)
  endfor
  return sections
enddef

# FUNCTION: Return the text of each document of the open Scrivening, by its
# file, as the buffer holds it, unsaved changes included and title lines
# left out. Empty when none is open, or when a title line is damaged.
export def SectionTexts(): dict<list<string>>
  if !IsOpen()
    return {}
  endif
  var sections: list<list<string>> = Sections()
  var texts: dict<list<string>> = {}
  for i in range(len(sections))
    texts[current.paths[i]] = sections[i]
  endfor
  return texts
enddef

# FUNCTION: Write each document whose text changed, for :w and auto-save.
# A damaged title line writes nothing, with an error.
def Write(): void
  var sections: list<list<string>> = Sections()
  if empty(sections)
    log.Error(MW.ScriveningNotSaved())
    return
  endif
  for i in range(len(sections))
    if sections[i] != current.saved[i]
      if writefile(sections[i], current.paths[i]) != 0
        log.Error(MW.CouldNotWritten(current.paths[i]))
        return
      endif
      current.saved[i] = sections[i]
    endif
  endfor
  setbufvar(current.bufnr, '&modified', 0)
enddef

# FUNCTION: Undo a change in Normal mode that damaged a title line.
def Protect(): void
  if !empty(Sections())
    return
  endif
  silent! undo
  log.Warn(MW.TitleLinesScrivening())
enddef

# FUNCTION: Return true when the text property of a title line is on lnum.
# A line outside the buffer, as below the last line, is not one.
def IsTitleLine(lnum: number): bool
  return lnum >= 1 && lnum <= line('$') && !empty(prop_list(lnum, {types: [PROP_TITLE]}))
enddef

# FUNCTION: Return true when the cursor is at the start of the first line
# of a document, where Backspace would join it to the title line.
def AtSectionStart(): bool
  return col('.') == 1 && IsTitleLine(line('.') - 1)
enddef

# FUNCTION: Return true when the cursor is at the end of the last line of a
# document, where Delete would join the next title line to it.
def AtSectionEnd(): bool
  return col('.') > strlen(getline('.')) && IsTitleLine(line('.') + 1)
enddef

# FUNCTION: Return true when the cursor is on the screen row of column col
# of its line, as for a line that wraps onto more rows.
def OnScreenRowOf(col: number): bool
  var winId: number = win_getid()
  var last: number = max([col([line('.'), '$']) - 1, 1])
  return screenpos(winId, line('.'), min([col, last])).row
    == screenpos(winId, line('.'), min([col('.'), last])).row
enddef

# FUNCTION: Return the keys for Up in Insert mode. From the first screen row
# of a line below a title line, Up goes past the title line, to the end of
# the document before. Nothing is above the first title line, so there Up
# does not move. Any other Up is the up of MapArrows.
def KeyUp(): string
  # A completion menu takes the plain key, which a move would close.
  if pumvisible()
    return CO.KEY_UP
  endif
  if !IsTitleLine(line('.') - 1) || !OnScreenRowOf(1)
    return b:bartleby_scrivening_arrows[0]
  endif
  return line('.') - 1 > 1 ? KEYS_UP_UP : ''
enddef

# FUNCTION: Return the keys for Down in Insert mode. From the last screen
# row of a line above a title line, Down goes past the title line, to the
# start of the next document. Any other Down is the down of MapArrows.
def KeyDown(): string
  if pumvisible()
    return CO.KEY_DOWN
  endif
  if !IsTitleLine(line('.') + 1) || !OnScreenRowOf(col([line('.'), '$']))
    return b:bartleby_scrivening_arrows[1]
  endif
  return KEYS_DOWN_DOWN
enddef

# FUNCTION: Start Insert mode off the title lines, toward the document
# below, as no move came before.
def EnterInsert(): void
  current.lastLine = 0
  LeaveTitleLine()
enddef

# FUNCTION: Move the cursor in Insert mode off a title line that another
# move put it on, such as a click, in the way it went: from below, to the
# end of the document before, or else to the start of the document below.
def LeaveTitleLine(): void
  var lnum: number = line('.')
  if IsTitleLine(lnum)
    var up: bool = get(current, 'lastLine', 0) > lnum && lnum > 1
    cursor(up ? lnum - 1 : lnum + 1, up ? col([lnum - 1, '$']) : 1)
  endif
  current.lastLine = line('.')
enddef

# FUNCTION: Return the number of the document at lnum, from 0, by the
# title line at or above it.
def SectionAt(lnum: number): number
  var title: dict<any> = prop_find({type: PROP_TITLE, lnum: lnum, col: 1, bufnr: current.bufnr}, 'b')
  if empty(title) || title.lnum > lnum
    title = prop_find({type: PROP_TITLE, lnum: lnum, col: col([lnum, '$']), bufnr: current.bufnr}, 'b')
  endif
  return empty(title) ? 0 : title.id - 1
enddef

# FUNCTION: Fire SECTION_EVENT when the cursor enters another document.
def NotifySection(): void
  var section: number = SectionAt(line('.'))
  if section != current.section
    current.section = section
    if exists('#User#' .. SECTION_EVENT)
      execute 'doautocmd <nomodeline> User ' .. SECTION_EVENT
    endif
  endif
enddef

# FUNCTION: Return the item of the document under the cursor in the
# Scrivening, or null_object outside it.
export def DocAtCursor(project: PO.Project): BI.BinderItem
  if !IsScrivening(bufnr())
    return null_object
  endif
  var row: T.Row = T.FindRowById(T.Flatten(project), current.ids[SectionAt(line('.'))])
  return row is null_object ? null_object : row.item
enddef

# FUNCTION: Return the item of the document the cursor is in: in a
# Scrivening the document under the cursor, or else the document of the
# current buffer. null_object when there is none.
export def DocHere(project: PO.Project): BI.BinderItem
  return IsScrivening(bufnr()) ? DocAtCursor(project) : project.FindItemByPath(expand('%:p'))
enddef

# FUNCTION: Return the line of the cursor inside its document, from 1, as
# if the document were alone in a buffer.
export def LineInDoc(): number
  var title: dict<any> = prop_find({type: PROP_TITLE, lnum: line('.'), col: col([line('.'), '$']),
    bufnr: current.bufnr}, 'b')
  return empty(title) ? line('.') : max([line('.') - title.lnum, 1])
enddef

# FUNCTION: Return the document at lnum of the Scrivening, as its id and
# the line inside it, from 0.
def PlaceAt(lnum: number): list<any>
  var section: number = SectionAt(lnum)
  var title: dict<any> = prop_find({type: PROP_TITLE, id: section + 1, both: true, lnum: 1, col: 1,
    bufnr: current.bufnr}, 'f')
  return [current.ids[section], empty(title) ? 0 : max([lnum - title.lnum - 1, 0])]
enddef

# FUNCTION: Return the line of the Scrivening that is offset lines into the
# document with id, or into the first document when id is not in it.
def LineOf(id: string, offset: number): number
  var i: number = max([index(current.ids, id), 0])
  var title: dict<any> = prop_find({type: PROP_TITLE, id: i + 1, both: true, lnum: 1,
    col: 1, bufnr: current.bufnr}, 'f')
  var start: number = empty(title) ? 1 : title.lnum + 1
  return min([start + offset, getbufinfo(current.bufnr)[0].linecount])
enddef

# FUNCTION: Put the cursor offset lines into the document with id.
def GoToDoc(id: string, offset: number): void
  cursor(LineOf(id, offset), 1)
  current.section = -1
  NotifySection()
enddef

# FUNCTION: Show the document with id in the Scrivening, offset lines into
# it, when the Scrivening holds it. Returns false when it does not.
export def ShowDoc(id: string, offset: number = 0): bool
  if empty(current) || index(current.ids, id) < 0
    return false
  endif
  var winId: number = bufwinid(current.bufnr)
  if winId != -1
    win_gotoid(winId)
  else
    W.GoToEditorWin()
    execute 'hide buffer ' .. current.bufnr
  endif
  GoToDoc(id, offset)
  return true
enddef

# FUNCTION: While a Scrivening is open, show a document of it that opens in
# a buffer of its own, by any command, in the Scrivening instead.
def StartRedirect(): void
  augroup bartleby_scrivening_redirect
    autocmd!
    autocmd BufEnter * Redirect()
  augroup END
enddef

def Redirect(): void
  if empty(current)
    return
  endif
  # By the one spelling of a path, see path.vim: current.paths holds what
  # the scrive stores, with forward slashes, while Vim answers with the
  # separator of its own system, so on Windows no document of the
  # Scrivening was ever recognised and none was redirected into it.
  # REFERENCE: https://github.com/Galvarcus/bartleby/issues/50
  var here: string = PA.Canon(expand('%:p'))
  var i: number = current.paths->indexof((_, p) => PA.Canon(p) ==# here)
  if i < 0
    return
  endif
  var bufNr: number = bufnr()
  var offset: number = line('.') - 1
  # A buffer cannot be wiped while Vim enters it.
  timer_start(0, (_) => RedirectNow(bufNr, current.ids[i], offset))
enddef

def RedirectNow(bufNr: number, id: string, offset: number): void
  if empty(current) || !bufexists(bufNr) || getbufvar(bufNr, '&modified')
    return
  endif
  var winId: number = bufwinid(bufNr)
  if winId != -1
    win_gotoid(winId)
    execute 'hide buffer ' .. current.bufnr
  endif
  execute 'silent! bwipe ' .. bufNr
  ShowDoc(id, offset)
enddef

# FUNCTION: Return true when a Scrivening is open.
export def IsOpen(): bool
  return !empty(current) && bufexists(current.bufnr)
enddef

# FUNCTION: Save and close the Scrivening. Each window that shows it then
# shows the document the cursor was in, at the same line. Returns false,
# and keeps it open, when it cannot be saved.
export def Close(): bool
  if empty(current)
    return true
  endif
  if IsModified()
    Write()
    if IsModified()
      return false
    endif
  endif
  var bufNr: number = current.bufnr
  var places: list<list<any>> = win_findbuf(bufNr)->mapnew((_, winId) => {
    var place: list<any> = PlaceAt(getcurpos(winId)[1])
    return [winId, current.paths[index(current.ids, place[0])], place[1]]
  })
  # Forgotten first, so that the documents do not open in it again.
  Forget()
  for [winId, path, offset] in places
    win_execute(winId, 'silent edit ' .. fnameescape(path))
    win_execute(winId, $'cursor({offset + 1}, 1)')
  endfor
  execute 'silent! bwipe! ' .. bufNr
  return true
enddef

# FUNCTION: Forget the Scrivening when its buffer unloads, as with :bd or
# :bunload, and wipe the buffer, so that its documents open on their own
# again and the empty buffer cannot be written.
def Discard(): void
  if empty(current)
    return
  endif
  var bufNr: number = current.bufnr
  Forget()
  # A buffer cannot be wiped while Vim unloads it.
  timer_start(0, (_) => {
    if bufexists(bufNr)
      execute 'silent! bwipe! ' .. bufNr
    endif
  })
enddef

# FUNCTION: Forget the Scrivening.
def Forget(): void
  current = {}
  augroup bartleby_scrivening_redirect
    autocmd!
  augroup END
enddef

# FUNCTION: Write the open Scrivening when it has changes, so that its
# documents on disk hold its text. Returns false when it cannot.
export def SaveIfModified(): bool
  if !IsModified()
    return true
  endif
  Write()
  return !IsModified()
enddef

# FUNCTION: Build the Scrivening again when the Binder changed its folder:
# documents added, moved, removed, or renamed, or with force, after files
# changed on disk. Unsaved text is written first. A folder that left the
# Manuscript closes it.
export def SyncWithTree(project: PO.Project, force: bool = false): void
  if empty(current)
    return
  endif
  var row: T.Row = T.FindRowById(T.Flatten(project), current.folderId)
  if row is null_object || !CanOpen(project, row.item)
    Close()
    return
  endif
  var docs: list<list<any>> = DocsOf(row.item)
  var root: string = project.BinderRoot()
  var ids: list<string> = docs->mapnew((_, d) => d[0].id)
  var paths: list<string> = docs->mapnew((_, d) => d[0].AbsPath(root))
  var titles: list<string> = docs->mapnew((_, d) => TITLE_LEAD .. d[1] .. TITLE_TAIL)
  if !force && ids == current.ids && paths == current.paths && titles == current.titles
    return
  endif
  if !SaveIfModified()
    return
  endif
  if empty(docs)
    Close()
    return
  endif
  # The cursor stays in its document, at the same line of it.
  var winId: number = bufwinid(current.bufnr)
  var place: list<any> = winId == -1 ? ['', 0] : PlaceAt(getcurpos(winId)[1])
  Build(project, docs)
  if winId != -1
    win_execute(winId, $'cursor({LineOf(place[0], place[1])}, 1)')
  endif
enddef
