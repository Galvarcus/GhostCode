vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# table.vim: pipe tables in documents. A popup form creates a table below
# the cursor, or changes the shape of the table under it, and Format lines
# up its columns, after the form and when you leave insert mode. Quill uses
# FormatExpr, so that its wrapping does not join or break the rows. Pandoc
# reads the tables, and tools/latex loads the packages that a PDF needs. A
# screenplay has none.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/writing.vim' as MW
import 'bartleby/variables/constants.vim' as CO

# The alignments of a column, as its separator cell gives them: ---, :---,
# ---:, and :---:. KEEP is no alignment: the form uses it to keep each.
const DEFAULT: string = 'default'
const LEFT: string = 'left'
const RIGHT: string = 'right'
const CENTER: string = 'center'
const KEEP: string = 'keep'
# A cell of the separator row, the second row of a table.
const SEP_CELL_PAT: string = '^:\?-\+:\?$'
# A bar that is not escaped, between two cells.
const BAR_PAT: string = '\\\@<!|'
# A caption, the paragraph after a table: Table: text, or : text.
const CAPTION_PAT: string = '^\s*\%(Table\)\?:\s'
const CAPTION_LEAD: string = 'Table: '
# The fewest dashes in a separator cell that Pandoc accepts.
const MIN_WIDTH: number = 3
const MAX_COLS: number = 20
const MAX_ROWS: number = 100
const NEW_COLS: number = 3
const NEW_ROWS: number = 2
# The form: its field names, and the width of its text fields.
const COLS: string = 'cols'
const ROWS: string = 'rows'
const HEADER: string = 'header'
const ALIGN: string = 'align'
const CAPTION: string = 'caption'
const NUM_WIDTH: number = 4
const CAPTION_WIDTH: number = 30

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Return the cells of a table row: the text between the bars that
# are not escaped, trimmed. An escaped bar, \|, stays in its cell.
export def Cells(line: string): list<string>
  var text: string = substitute(trim(line), '^|', '', '')
  text = substitute(text, '\\\@<!|$', '', '')
  return split(text, BAR_PAT, true)->mapnew((_, c) => trim(c))
enddef

def AlignOf(cell: string): string
  var left: bool = cell =~# '^:'
  var right: bool = cell =~# ':$'
  return left && right ? CENTER : (right ? RIGHT : (left ? LEFT : DEFAULT))
enddef

def SepCell(align: string, width: number): string
  if align ==# LEFT
    return ':' .. repeat('-', width - 1)
  elseif align ==# RIGHT
    return repeat('-', width - 1) .. ':'
  elseif align ==# CENTER
    return ':' .. repeat('-', width - 2) .. ':'
  endif
  return repeat('-', width)
enddef

def Pad(cell: string, width: number, align: string): string
  var gap: number = width - strdisplaywidth(cell)
  if align ==# RIGHT
    return repeat(' ', gap) .. cell
  elseif align ==# CENTER
    return repeat(' ', gap / 2) .. cell .. repeat(' ', gap - gap / 2)
  endif
  return cell .. repeat(' ', gap)
enddef

# FUNCTION: Return a table as lines: rows, the header first, each a cell for
# each of aligns, with indent before each line. Each column is as wide as
# its widest cell, by display width, and the separator row follows the
# header.
def Lines(rows: list<list<string>>, aligns: list<string>, indent: string): list<string>
  var widths: list<number> = aligns->mapnew((_, _) => MIN_WIDTH)
  for r in rows
    for c in range(len(aligns))
      widths[c] = max([widths[c], strdisplaywidth(r[c])])
    endfor
  endfor
  var out: list<string> = []
  for i in range(len(rows))
    var cells: list<string> = range(len(aligns))->mapnew((_, c) => Pad(rows[i][c], widths[c], aligns[c]))
    out->add(indent .. '| ' .. join(cells, ' | ') .. ' |')
    if i ==# 0
      var seps: list<string> = range(len(aligns))->mapnew((_, c) => SepCell(aligns[c], widths[c]))
      out->add(indent .. '| ' .. join(seps, ' | ') .. ' |')
    endif
  endfor
  return out
enddef

# FUNCTION: Return the table in lines, from its header to its last row, as
# {rows, aligns, indent}: the header and the data rows, each with a cell
# for every column, and the alignment of each column.
def Parse(lines: list<string>): dict<any>
  var cells: list<list<string>> = lines->mapnew((_, l) => Cells(l))
  var width: number = max(cells->mapnew((_, r) => len(r)))
  var aligns: list<string> = cells[1]->mapnew((_, c) => AlignOf(c))
  aligns += repeat([DEFAULT], width - len(aligns))
  var rows: list<list<string>> = ([cells[0]] + cells[2 :])->mapnew((_, r) => r + repeat([''], width - len(r)))
  return {rows: rows, aligns: aligns, indent: matchstr(lines[0], '^\s*')}
enddef

# FUNCTION: Return the lines of a table, lined up, see Lines.
export def Format(lines: list<string>): list<string>
  var t: dict<any> = Parse(lines)
  return Lines(t.rows, t.aligns, t.indent)
enddef

def IsSep(line: string): bool
  var cells: list<string> = Cells(line)
  return !empty(cells) && empty(cells->copy()->filter((_, c) => c !~# SEP_CELL_PAT))
enddef

# FUNCTION: Return true when lines hold a table: a row with a separator row
# after it.
export def HasTable(lines: list<string>): bool
  for i in range(max([len(lines) - 1, 0]))
    if lines[i] =~# CO.TABLE_ROW_PAT && IsSep(lines[i + 1])
      return true
    endif
  endfor
  return false
enddef

# FUNCTION: Return the first and last line of the table around line lnum,
# or [0, 0]. A table is a run of rows whose second row is a separator row.
export def Bounds(lnum: number): list<number>
  if getline(lnum) !~# CO.TABLE_ROW_PAT
    return [0, 0]
  endif
  var first: number = lnum
  while first > 1 && getline(first - 1) =~# CO.TABLE_ROW_PAT
    first -= 1
  endwhile
  var last: number = lnum
  while last < line('$') && getline(last + 1) =~# CO.TABLE_ROW_PAT
    last += 1
  endwhile
  return last > first && IsSep(getline(first + 1)) ? [first, last] : [0, 0]
enddef

# FUNCTION: Return the line of the caption of the table that ends at line
# last, after one blank line, or 0.
def CaptionLnum(last: number): number
  return last + 2 <= line('$') && getline(last + 1) !~ '\S' && getline(last + 2) =~# CAPTION_PAT ? last + 2 : 0
enddef

def CaptionLines(caption: string): list<string>
  return caption ==# '' ? [] : ['', CAPTION_LEAD .. caption]
enddef

# FUNCTION: Return the lines of a new table: header cells Column 1 and on,
# or empty ones without a header, rows of empty cells, the alignment of
# every column, and the caption, if any, after a blank line.
export def Build(cols: number, nRows: number, header: bool, align: string, caption: string): list<string>
  var head: list<string> = range(1, cols)->mapnew((_, n) => header ? MW.ColumnN(n) : '')
  var rows: list<list<string>> = [head] + range(nRows)->mapnew((_, _) => repeat([''], cols))
  return Lines(rows, repeat([align], cols), '') + CaptionLines(caption)
enddef

def Filled(cells: list<string>): number
  return len(cells->copy()->filter((_, c) => c !=# ''))
enddef

# FUNCTION: Return the table in lines with a new shape, and the number of
# cells with text that it drops. Rows and columns are added and dropped at
# the end. Turning the header off moves its text down as the first row, so
# that none is lost. A new header, and new header cells, get Column n. align
# is for every column, or KEEP to keep the alignment of each.
export def Reshape(lines: list<string>, cols: number, nRows: number, header: bool, align: string): list<any>
  var t: dict<any> = Parse(lines)
  var head: list<string> = t.rows[0]
  var data: list<list<string>> = t.rows[1 :]
  var hadHeader: bool = Filled(head) > 0
  if !header && hadHeader
    data = [head] + data
    head = repeat([''], len(head))
  endif
  var useHeader: bool = header
  var kept: list<list<string>> = slice(data, 0, nRows)
  var lost: number = 0
  for r in slice(data, nRows)
    lost += Filled(r)
  endfor
  for r in [head] + kept
    lost += Filled(slice(r, cols))
  endfor
  head = range(cols)->mapnew((_, c) => c < len(head) && (head[c] !=# '' || !useHeader) ? head[c]
    : (useHeader ? MW.ColumnN(c + 1) : ''))
  kept = kept->mapnew((_, r) => range(cols)->mapnew((_, c) => get(r, c, '')))
  kept += range(nRows - len(kept))->mapnew((_, _) => repeat([''], cols))
  var aligns: list<string> = align ==# KEEP
    ? range(cols)->mapnew((_, c) => get(t.aligns, c, LEFT)) : repeat([align], cols)
  return [Lines([head] + kept, aligns, t.indent), lost]
enddef

def AlignNames(): dict<string>
  return {[LEFT]: MW.Left(), [CENTER]: MW.Center(), [RIGHT]: MW.Right()}
enddef

# FUNCTION: Open the table form: for the table under the cursor, to change
# its shape, or for a new table below the cursor line. A screenplay has no
# tables.
export def Edit(): void
  if &filetype ==# CO.FILETYPE_FOUNTAIN
    log.Info(MW.NoTables())
    return
  endif
  var names: dict<string> = AlignNames()
  var [first, last] = Bounds(line('.'))
  var vals: dict<string> = {cols: string(NEW_COLS), rows: string(NEW_ROWS),
    header: MC.Yes(), align: names[LEFT], caption: ''}
  var options: list<string> = [names[LEFT], names[CENTER], names[RIGHT]]
  if first > 0
    var t: dict<any> = Parse(getline(first, last))
    vals.cols = string(len(t.aligns))
    vals.rows = string(len(t.rows) - 1)
    vals.header = Filled(t.rows[0]) > 0 ? MC.Yes() : MC.No()
    var uniform: bool = empty(t.aligns->copy()->filter((_, a) => a !=# t.aligns[0]))
    if uniform
      vals.align = names[t.aligns[0] ==# DEFAULT ? LEFT : t.aligns[0]]
    else
      options->add(MW.AsIs())
      vals.align = MW.AsIs()
    endif
    var cap: number = CaptionLnum(last)
    vals.caption = cap > 0 ? substitute(getline(cap), CAPTION_PAT, '', '') : ''
  endif
  var form = IP.InputPopup.new([
    [{name: COLS, type: CO.TYPE_TEXT}, {name: ROWS, type: CO.TYPE_TEXT}],
    [{name: HEADER, type: CO.TYPE_CHOICE, options: [MC.Yes(), MC.No()]}],
    [{name: ALIGN, type: CO.TYPE_CHOICE, options: options}],
    [{name: CAPTION, type: CO.TYPE_TEXT}],
  ], vals, {
    title: MW.Table(),
    labels: {cols: MW.Columns(), rows: MW.Rows(), header: MW.HeaderRow(),
      align: MW.Alignment(), caption: MW.Caption()},
    widths: {cols: NUM_WIDTH, rows: NUM_WIDTH, caption: CAPTION_WIDTH},
    submit_label: first > 0 ? MC.Save() : MW.Insert(),
  })
  form.OnSubmit((v: dict<any>) => {
    Submit(first, last, v)
  })
  form.Open()
enddef

# FUNCTION: Make or reshape the table from the values of the form. first is
# the first line of the table under the cursor, or 0 for a new one.
export def Submit(first: number, last: number, v: dict<any>): void
  var cols: number = str2nr(v.cols)
  var nRows: number = str2nr(v.rows)
  if cols < 1 || cols > MAX_COLS || nRows < 1 || nRows > MAX_ROWS
    log.Error(MW.BadShape(MAX_COLS, MAX_ROWS))
    return
  endif
  var header: bool = v.header ==# MC.Yes()
  var align: string = KEEP
  for [key, name] in items(AlignNames())
    if v.align ==# name
      align = key
    endif
  endfor
  var caption: string = trim(v.caption)
  if first ==# 0
    Insert(Build(cols, nRows, header, align, caption))
    return
  endif
  var [lines, lost] = Reshape(getline(first, last), cols, nRows, header, align)
  var Apply = () => {
    var cap: number = CaptionLnum(last)
    deletebufline('%', first, cap > 0 ? cap : last)
    append(first - 1, lines + CaptionLines(caption))
  }
  if lost > 0
    DP.Confirm(MW.DropCells(lost), Apply)
  else
    Apply()
  endif
enddef

# FUNCTION: Put the lines of a new table below the cursor line, with a blank
# line between it and any text, and the cursor in the first cell under the
# header.
def Insert(lines: list<string>): void
  var lnum: number = line('.')
  var before: list<string> = getline(lnum) =~ '\S' ? [''] : []
  var after: list<string> = lnum < line('$') && getline(lnum + 1) =~ '\S' ? [''] : []
  append(lnum, before + lines + after)
  cursor(lnum + len(before) + 3, 3)
enddef

# FUNCTION: Return the number of the cell that byte column col of line is
# in, counting the cell after the first bar as 1.
def CellAt(line: string, col: number): number
  return len(split(strpart(line, 0, col - 1), BAR_PAT, true)) - 1
enddef

# FUNCTION: Return the byte column of the text of cell n of line, after its
# bar and space.
def ColOfCell(line: string, n: number): number
  var from: number = 0
  var at: number = -1
  for _ in range(n)
    at = match(line, BAR_PAT, from)
    if at < 0
      return 1
    endif
    from = at + 1
  endfor
  return at + 3
enddef

# FUNCTION: Line up the table around line lnum, and keep the cursor in its
# cell. Return false when lnum is not in a table.
export def FormatAt(lnum: number): bool
  var [first, last] = Bounds(lnum)
  if first ==# 0
    return false
  endif
  var lines: list<string> = getline(first, last)
  var out: list<string> = Format(lines)
  if out ==# lines
    return true
  endif
  var cur: number = line('.')
  var cell: number = cur >= first && cur <= last ? CellAt(getline(cur), col('.')) : -1
  setline(first, out)
  if cell > 0
    cursor(cur, ColOfCell(getline(cur), cell))
  endif
  return true
enddef

# FUNCTION: Line up the table under the cursor, for :BartlebyTableFormat.
export def FormatCmd(): void
  if !FormatAt(line('.'))
    log.Info(MW.NoTableHere())
  endif
enddef

# FUNCTION: Line up the table under the cursor when you leave insert mode,
# in any buffer but a screenplay, unless g:bartleby_table_autoformat is
# false. It is read here, so that a change takes effect at once.
export def OnInsertLeave(): void
  if g:bartleby_table_autoformat && &modifiable && &filetype !=# CO.FILETYPE_FOUNTAIN
      && getline('.') =~# CO.TABLE_ROW_PAT
    FormatAt(line('.'))
  endif
enddef

# FUNCTION: Return true when the paragraph around line lnum, between blank
# lines, holds a table row. Autoformat would join that paragraph into one
# line, and it does not use formatexpr, so Quill keeps it off there.
export def InPara(lnum: number): bool
  var first: number = lnum
  while first > 1 && getline(first - 1) =~ '\S'
    first -= 1
  endwhile
  var last: number = lnum
  while last < line('$') && getline(last + 1) =~ '\S'
    last += 1
  endwhile
  return !empty(getline(first, last)->filter((_, l) => l =~# CO.TABLE_ROW_PAT))
enddef

# FUNCTION: The formatexpr that Quill sets. While you type, text that holds
# a table row is left alone, so that wrapping at textwidth does not break a
# row, and gq lines up the table. Other text gets the formatting of Vim.
# Autoformat does not use formatexpr, see InPara.
export def FormatExpr(): number
  var lnums: list<number> = range(v:lnum, v:lnum + max([v:count, 1]) - 1)
  var rows: list<number> = lnums->copy()->filter((_, l) => getline(l) =~# CO.TABLE_ROW_PAT)
  if empty(rows)
    return 1
  endif
  if mode() !~# '^[iR]'
    for l in rows
      FormatAt(l)
    endfor
  endif
  return 0
enddef
