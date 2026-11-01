vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# outliner.vim: a flat, indented table of the whole subtree of one
# folder, one row per binder item, with the columns Title, Label, Status,
# Words, Target, and Keywords.
#
# A popup, not a buffer. An earlier version used a real buffer, which took
# the window that opens documents and caused many window bugs: the
# Outliner and a document competed for the same editor window. A popup
# takes no window, so there is nothing to compete for. The grid of
# buttonspopup.vim does not fit: its columns are equal buttons, not named
# table columns of different types, so the Outliner has its own popup.
#
# gs sorts the rows by a column. This changes only the view, not the
# binder or project.json: J and K in the Binder change the order. A sorted
# view cannot show the tree, so it has no indent. Tree Order restores it.
#
# l, s, and gs use PickOne from picker.vim, as the Binder does. The picker
# opens above this popup, with a higher zindex. This popup stays open and
# updates when the picker closes.
#
# Row is defined before the functions that use it because several of
# them name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined. A class used only inside a
# function body can come later.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/wordcount.vim' as WC
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/views.vim' as MV
import 'bartleby/variables/constants.vim' as CO

const HL_TITLE: string = 'Title'
const KEY_LABEL: string = 'Label'
const KEY_STATUS: string = 'Status'
const KEY_WORDS: string = 'Words'
const TYPE_OUTLINER_HEADER: string = 'OutlinerHeader'
const TYPE_OUTLINER_SEL: string = 'OutlinerSelected'

var log = L.New(expand('<sfile>:t'))

const TREE_ORDER: string = 'Tree Order'
const HEADERS: list<string> = ['Title', 'Label', 'Status', 'Words', 'Target', 'Keywords']
const SORT_KEYS: list<string> = [TREE_ORDER, 'Title', 'Label', 'Status', 'Words']
const MAX_VISIBLE_ROWS: number = 20
const OUTLINER_ZINDEX: number = 250

# CLASS: The column values of one row, already strings. FmtRow only
# pads them.
export class Row
  var item: BI.BinderItem
  var title: string
  var label: string
  var status: string
  var words: string
  var target: string
  var keywords: string
endclass

# FUNCTION: Return each column and sort key, as used in code, to its name
# in the message language, for the header and the sort picker.
def ColNames(): dict<string>
  return {
    [TREE_ORDER]: MV.TreeOrder(),
    Title: MV.Title(),
    Label: MC.Label(),
    Status: MC.Status(),
    Words: MC.Words(),
    Target: MC.Target(),
    Keywords: MC.Keywords(),
  }
enddef

def FlattenFolder(folder: BI.BinderItem): list<T.Row>
  var rows: list<T.Row> = []
  def Walk(items: list<BI.BinderItem>, depth: number): void
    for item in items
      rows->add(T.Row.new(item, depth, null_object))
      if item.IsFolder()
        Walk(item.children, depth + 1)
      endif
    endfor
  enddef
  Walk(folder.children, 0)
  return rows
enddef

def BuildRow(treeRow: T.Row, binderRoot: string, showIndent: bool, totals: dict<number>): Row
  var titleText: string = showIndent
    ? repeat('  ', treeRow.depth) .. treeRow.item.title
    : treeRow.item.title
  var words: string = string(get(totals, treeRow.item.id, 0))

  if !treeRow.item.IsDoc()
    return Row.new(treeRow.item, titleText, '-', '-', words, '-', '')
  endif

  var meta: D.DocMeta = treeRow.item.LoadMeta(binderRoot)
  var target: string = meta.wordCountTarget > 0 ? string(meta.wordCountTarget) : '-'
  return Row.new(treeRow.item, titleText, D.LabelName(meta.label), D.StatusName(meta.status), words, target,
    join(meta.keywords, ', '))
enddef

def SortRows(rows: list<Row>, key: string): list<Row>
  var sorted: list<Row> = copy(rows)
  if key ==# HL_TITLE
    sorted->sort((a, b) => a.title ==# b.title ? 0 : (a.title ># b.title ? 1 : -1))
  elseif key ==# KEY_LABEL
    sorted->sort((a, b) => a.label ==# b.label ? 0 : (a.label ># b.label ? 1 : -1))
  elseif key ==# KEY_STATUS
    sorted->sort((a, b) => a.status ==# b.status ? 0 : (a.status ># b.status ? 1 : -1))
  elseif key ==# KEY_WORDS
    sorted->sort((a, b) => str2nr(a.words) - str2nr(b.words))
  endif
  return sorted
enddef

def Pad(text: string, width: number): string
  return text .. repeat(' ', max([0, width - strdisplaywidth(text)]))
enddef

def ColWidths(rows: list<Row>): list<number>
  var names: dict<string> = ColNames()
  var widths: list<number> = HEADERS->mapnew((_, h) => strdisplaywidth(names[h]))
  for row in rows
    widths[0] = max([widths[0], strdisplaywidth(row.title)])
    widths[1] = max([widths[1], strdisplaywidth(row.label)])
    widths[2] = max([widths[2], strdisplaywidth(row.status)])
    widths[3] = max([widths[3], strdisplaywidth(row.words)])
    widths[4] = max([widths[4], strdisplaywidth(row.target)])
  endfor
  return widths
enddef

def FmtRow(widths: list<number>, title: string, label: string, status: string,
    words: string, target: string, keywords: string): string
  return Pad(title, widths[0]) .. '  ' .. Pad(label, widths[1]) .. '  '
    .. Pad(status, widths[2]) .. '  ' .. Pad(words, widths[3]) .. '  '
    .. Pad(target, widths[4]) .. '  ' .. keywords
enddef

class OutlinerPopup
  var project: PO.Project
  var folder: BI.BinderItem
  var sortKey: string = TREE_ORDER
  var rows: list<Row> = []
  var widths: list<number> = []
  var selectedIdx: number = 0
  var scrollOffset: number = 0
  var winid: number = -1
  var bufnr: number = -1
  var pendingG: bool = false

  def new(this.project, this.folder)
  enddef

  def Rebuild(): void
    var showIndent: bool = this.sortKey ==# TREE_ORDER
    var treeRows: list<T.Row> = FlattenFolder(this.folder)
    # Counted once for the whole folder, see wordcount.vim.
    var totals: dict<number> = WC.Totals(this.folder.children, this.project.BinderRoot())
    var built: list<Row> = treeRows->mapnew(
      (_, tr) => BuildRow(tr, this.project.BinderRoot(), showIndent, totals))
    this.rows = showIndent ? built : SortRows(built, this.sortKey)
    this.widths = ColWidths(this.rows)
    this.selectedIdx = min([this.selectedIdx, max([0, len(this.rows) - 1])])
  enddef

  def EnsurePropTypes(): void
    if empty(prop_type_get('OutlinerHeader'))
      prop_type_add('OutlinerHeader', {highlight: HL_TITLE})
    endif
    if empty(prop_type_get('OutlinerSelected'))
      prop_type_add('OutlinerSelected', {highlight: 'PmenuSel'})
    endif
  enddef

  def Open(): void
    this.Rebuild()
    this.EnsurePropTypes()

    this.bufnr = bufadd('')
    setbufvar(this.bufnr, '&buftype', 'nofile')
    setbufvar(this.bufnr, '&swapfile', false)
    setbufvar(this.bufnr, '&bufhidden', 'wipe')

    var width: number = max([WidthsSum(this.widths) + 10, 30])
    var height: number = min([max([len(this.rows), 1]), MAX_VISIBLE_ROWS]) + 2

    this.winid = popup_create(this.bufnr, {
      title: MV.Outliner(this.folder.title),
      border: [1, 1, 1, 1],
      padding: [0, 1, 0, 1],
      minwidth: width,
      maxwidth: width,
      minheight: height,
      maxheight: height,
      zindex: OUTLINER_ZINDEX,
      mapping: false,
      filter: (id, key) => this.Filter(id, key),
    })
    this.Render()
  enddef

  def Close(): void
    if this.winid != -1
      popup_close(this.winid)
    endif
  enddef

  def VisibleSlice(): list<number>
    var visibleRows: number = MAX_VISIBLE_ROWS
    if this.selectedIdx < this.scrollOffset
      this.scrollOffset = this.selectedIdx
    elseif this.selectedIdx >= this.scrollOffset + visibleRows
      this.scrollOffset = this.selectedIdx - visibleRows + 1
    endif
    var last: number = min([len(this.rows), this.scrollOffset + visibleRows])
    return [this.scrollOffset, last]
  enddef

  def Render(): void
    if this.bufnr == -1
      return
    endif
    var shown: list<string> = HEADERS->mapnew((_, h) => ColNames()[h])
    var header: string = FmtRow(this.widths, shown[0], shown[1], shown[2],
      shown[3], shown[4], shown[5])
    var lines: list<string> = [header, repeat('-', strdisplaywidth(header))]

    var [first: number, last: number] = this.VisibleSlice()
    for i in range(first, last - 1)
      var row: Row = this.rows[i]
      lines->add(FmtRow(this.widths, row.title, row.label, row.status, row.words,
        row.target, row.keywords))
    endfor
    if empty(this.rows)
      lines->add(MV.Empty())
    endif

    setbufline(this.bufnr, 1, lines)
    if len(getbufline(this.bufnr, len(lines) + 1, '$')) > 0
      deletebufline(this.bufnr, len(lines) + 1, '$')
    endif

    prop_remove({type: TYPE_OUTLINER_HEADER, bufnr: this.bufnr}, 1, len(lines))
    prop_remove({type: TYPE_OUTLINER_SEL, bufnr: this.bufnr}, 1, len(lines))
    prop_add(1, 1, {type: TYPE_OUTLINER_HEADER, bufnr: this.bufnr, length: strlen(header)})
    if !empty(this.rows)
      var selLnum: number = 3 + (this.selectedIdx - first)
      prop_add(selLnum, 1, {
        type: TYPE_OUTLINER_SEL, bufnr: this.bufnr, length: strlen(lines[selLnum - 1]),
      })
    endif
  enddef

  def SelRow(): Row
    return empty(this.rows) ? null_object : this.rows[this.selectedIdx]
  enddef

  def OpenSelDoc(): void
    var row: Row = this.SelRow()
    if row is null_object || !row.item.IsDoc()
      return
    endif
    var path: string = row.item.AbsPath(this.project.BinderRoot())
    if !filereadable(path)
      log.Error(MC.MissingFileDisk(path))
      return
    endif
    this.Close()
    W.GoToEditorWin()
    execute 'edit ' .. fnameescape(path)
  enddef

  def PickLabel(): void
    var row: Row = this.SelRow()
    if row is null_object || !row.item.IsDoc()
      return
    endif
    var item: BI.BinderItem = row.item
    var curMeta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
    PI.PickOne(MC.Label(), CO.LABELS, (choice: string) => {
      var meta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
      meta.SetLabel(choice)
      meta.Save(item.MetaPath(this.project.BinderRoot()))
      this.Rebuild()
      this.Render()
    }, curMeta.label, D.LabelNames())
  enddef

  def PickStatus(): void
    var row: Row = this.SelRow()
    if row is null_object || !row.item.IsDoc()
      return
    endif
    var item: BI.BinderItem = row.item
    var curMeta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
    PI.PickOne(MC.Status(), CO.STATUSES, (choice: string) => {
      var meta: D.DocMeta = item.LoadMeta(this.project.BinderRoot())
      meta.SetStatus(choice)
      meta.Save(item.MetaPath(this.project.BinderRoot()))
      this.Rebuild()
      this.Render()
    }, curMeta.status, D.StatusNames())
  enddef

  def PickSort(): void
    PI.PickOne(MV.SortBy(), SORT_KEYS, (choice: string) => {
      this.sortKey = choice
      this.Rebuild()
      this.Render()
    }, this.sortKey, ColNames())
  enddef

  def ShowHelp(): void
    H.Show(MV.Outliner2(), [
      ['<CR>', MV.OpenDocUnder()],
      ['l', MC.SetLabel()],
      ['s', MC.SetStatus()],
      ['gs', MV.Sort()],
      ['q', MV.CloseOutliner()],
      ['?', MC.Help()],
    ])
  enddef

  def Filter(winid: number, key: string): bool
    if this.pendingG
      this.pendingG = false
      if key ==# 's'
        this.PickSort()
      endif
      return true
    endif

    if key ==# 'j' || key ==# CO.KEY_DOWN
      this.selectedIdx = min([max([len(this.rows) - 1, 0]), this.selectedIdx + 1])
      this.Render()
    elseif key ==# 'k' || key ==# CO.KEY_UP
      this.selectedIdx = max([0, this.selectedIdx - 1])
      this.Render()
    elseif key ==# CO.KEY_CR
      this.OpenSelDoc()
    elseif key ==# 'l'
      this.PickLabel()
    elseif key ==# 's'
      this.PickStatus()
    elseif key ==# 'g'
      this.pendingG = true
    elseif key ==# '?'
      this.ShowHelp()
    elseif key ==# 'q' || key ==# CO.KEY_ESC
      this.Close()
    endif
    return true
  enddef
endclass

def WidthsSum(widths: list<number>): number
  var total: number = 0
  for w in widths
    total += w
  endfor
  return total + (len(widths) - 1) * 2
enddef

export def Show(project: PO.Project, folder: BI.BinderItem): void
  var popup: OutlinerPopup = OutlinerPopup.new(project, folder)
  popup.Open()
enddef
