vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# corkboard.vim: a grid of index cards for the documents directly in one
# folder, built on PopupBtnMenu from buttonspopup.vim. Each card is a
# box with the title on its own line and the synopsis wrapped below it,
# see wrap.vim. buttonspopup.vim draws a label with line breaks as a box
# instead of a bracketed line.
#
# Picking a card calls back with its document, and the caller decides
# what to do, see OpenCorkboard in binder.vim, which opens it in the
# editor. e edits the synopsis of the selected card, and J and K move the
# card among its siblings. Both close the popup and show it again,
# because buttonspopup.vim cannot update its buttons in place.
# opts.button.selected keeps the same card selected.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/mutate.vim' as MU
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/buttonspopup.vim' as BP
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/wrap.vim' as WR
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/views.vim' as MV

const PATH_H_J_K_L: string = ' / h j k l'

var log = L.New(expand('<sfile>:t'))

const CARD_CONTENT_WIDTH: number = 24
const CARD_SPACING: number = 2
const MAX_SYNOPSIS_LINES: number = 3
# Width of one card on screen, with its border and padding: the content
# plus 2 border characters and 2 spaces, see RenderBtn in
# buttonspopup.vim.
const CARD_TOTAL_WIDTH: number = CARD_CONTENT_WIDTH + 4

def Noop(): void
enddef

# FUNCTION: Return how many card columns, CARD_SPACING apart, fit in the
# terminal, so the grid is never wider than the screen. An 80-column
# terminal fits 2 columns of the default card width. MARGIN leaves room
# for the popup border and padding and a little space at the screen edge.
def MaxCols(): number
  const MARGIN: number = 4
  var available: number = &columns - MARGIN
  var maxFit: number = (available + CARD_SPACING) / (CARD_TOTAL_WIDTH + CARD_SPACING)
  return max([1, maxFit])
enddef

# FUNCTION: Return the card label: the title on its own line, then up to
# MAX_SYNOPSIS_LINES wrapped lines of synopsis, joined by line breaks for
# the box drawing in buttonspopup.vim. A longer synopsis ends its last
# line with an ellipsis.
def CardLabel(item: BI.BinderItem, binderRoot: string): string
  var meta: D.DocMeta = item.LoadMeta(binderRoot)
  var cardLines: list<string> = [item.title]
  if meta.synopsis !=# ''
    var wrapped: list<string> = WR.Wrap(meta.synopsis, CARD_CONTENT_WIDTH)
    if len(wrapped) > MAX_SYNOPSIS_LINES
      wrapped = wrapped[0 : MAX_SYNOPSIS_LINES - 1]
      wrapped[-1] = wrapped[-1] .. '…'
    endif
    cardLines += wrapped
  endif
  return join(cardLines, "\n")
enddef

def EditSynopsis(project: PO.Project, folder: BI.BinderItem, doc: BI.BinderItem,
    OnDocumentPicked: func(BI.BinderItem)): void
  var meta: D.DocMeta = doc.LoadMeta(project.BinderRoot())
  IP.PromptText(MC.Synopsis(), meta.synopsis, (newSynopsis: string) => {
    if newSynopsis !=# meta.synopsis
      meta.SetSynopsis(newSynopsis)
      meta.Save(doc.MetaPath(project.BinderRoot()))
    endif
    Show(project, folder, OnDocumentPicked, doc.id)
  }, () => {
    Show(project, folder, OnDocumentPicked, doc.id)
  })
enddef

def Reorder(project: PO.Project, folder: BI.BinderItem, doc: BI.BinderItem,
    delta: number, OnDocumentPicked: func(BI.BinderItem)): void
  # Build a T.Row by hand. MoveWithinSiblings reads only item and ownerItem,
  # so there is no need to flatten the whole scrive to reorder one folder.
  var row: T.Row = T.Row.new(doc, 0, folder)
  if MU.MoveWithinSiblings(project, row, delta)
    project.Save()
  else
    log.Info(MV.AlreadyEndFolder())
  endif
  Show(project, folder, OnDocumentPicked, doc.id)
enddef

# FUNCTION: Handle the Corkboard keys that the base popup does not know.
# Return true when the key is handled.
def HandleExtraKey(project: PO.Project, folder: BI.BinderItem, docs: list<BI.BinderItem>,
    OnDocumentPicked: func(BI.BinderItem), id: number, selectedIdx: number, key: string): bool
  var doc: BI.BinderItem = docs[selectedIdx]
  if key ==# 'e'
    popup_close(id, -1)
    EditSynopsis(project, folder, doc, OnDocumentPicked)
    return true
  elseif key ==# 'J'
    popup_close(id, -1)
    Reorder(project, folder, doc, 1, OnDocumentPicked)
    return true
  elseif key ==# 'K'
    popup_close(id, -1)
    Reorder(project, folder, doc, -1, OnDocumentPicked)
    return true
  elseif key ==# '?'
    ShowHelp()
    return true
  endif
  return false
enddef

def ShowHelp(): void
  H.Show(MV.Corkboard(), [
    [MV.Arrows() .. PATH_H_J_K_L, MV.MoveBetweenCards()],
    ['<CR> / <Space>', MV.OpenSelDoc()],
    ['e', MV.EditSynopsis()],
    ['J / K', MV.MoveCardLater()],
    ['<Esc>', MC.Close()],
    ['?', MC.Help()],
  ])
enddef

# FUNCTION: Show the documents directly in folder as a card grid.
# OnDocumentPicked receives the document that is activated with Enter,
# Space, or a click. It is not called on cancel. preferredId selects a
# card again after e, J, or K closes and reopens the Corkboard.
export def Show(project: PO.Project, folder: BI.BinderItem,
    OnDocumentPicked: func(BI.BinderItem), preferredId: string = ''): void
  # Copy first: filter changes its list in place, and folder.children is
  # the live tree. Filtering it directly would delete every child that is
  # not a document from the binder.
  var docs: list<BI.BinderItem> = copy(folder.children)->filter((_, c) => c.IsDoc())
  if empty(docs)
    log.Info(MV.HasNoDocs(folder.title))
    return
  endif

  var buttons: list<BP.Btn> = docs->mapnew((_, doc) =>
    BP.Btn.new(CardLabel(doc, project.BinderRoot()), Noop, doc))

  var initialIdx: number = 0
  for i in range(len(docs))
    if docs[i].id ==# preferredId
      initialIdx = i
    endif
  endfor

  var menu: BP.PopupBtnMenu = BP.PopupBtnMenu.new(buttons, {
    popup: {title: $' {folder.title} '},
    button: {
      columns: min([len(docs), 3, MaxCols()]),
      spacing: CARD_SPACING,
      width: CARD_CONTENT_WIDTH,
      selected: initialIdx,
    },
    on_key: (id: number, selectedIdx: number, key: string): bool =>
      HandleExtraKey(project, folder, docs, OnDocumentPicked, id, selectedIdx, key),
    callback: (selected: any) => {
      if selected != null
        OnDocumentPicked(selected.data)
      endif
    },
  })
  menu.Show()
enddef
