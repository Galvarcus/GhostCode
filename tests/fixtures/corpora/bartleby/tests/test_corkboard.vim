vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_corkboard.vim: the Corkboard of corkboard.vim shows a card for
# each document of a folder, with its title and at most three lines of its
# synopsis. Enter picks a card, and J moves it later in the folder. A
# folder without documents shows nothing and keeps its folders: once, the
# Corkboard removed them from the Binder.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/corkboard.vim' as CB
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as FI

# FUNCTION: Return the fixture project, with a second scene in its first
# chapter, both on disk, the first with a long synopsis.
def ProjectWithCards(): dict<any>
  var project = FI.BuildProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  chapter.AddChild(BI.BinderItem.NewDocument('Scene 2', 'chapter-1/scene-02.md'))
  var first = chapter.ChildAt(0)
  var second = chapter.ChildAt(1)
  FI.WriteDocContent(project, first, ['Text.'])
  FI.WriteDocContent(project, second, ['Text.'])
  var meta = first.LoadMeta(project.BinderRoot())
  meta.SetSynopsis(repeat('A long synopsis that runs on and on. ', 6))
  meta.Save(first.MetaPath(project.BinderRoot()))
  return {project: project, chapter: chapter, first: first, second: second, picked: []}
enddef

# FUNCTION: Return the text of the open popup, or an empty string.
def PopupText(): string
  var ids: list<number> = popup_list()
  return empty(ids) ? '' : join(getbufline(winbufnr(ids[0]), 1, '$'), "\n")
enddef

def Close(fx: dict<any>): void
  popup_clear(true)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_cards_show_the_title_and_at_most_three_lines_of_synopsis(): void
  var fx = ProjectWithCards()
  CB.Show(fx.project, fx.chapter, (doc) => {
    fx.picked->add(doc.id)
  })
  var text: string = PopupText()
  assert_match('Scene 1', text)
  assert_match('Scene 2', text)
  assert_match('A long synopsis', text)
  assert_match('…', text)
  Close(fx)
enddef

def Test_a_folder_without_documents_shows_nothing_and_keeps_its_folders(): void
  var fx = ProjectWithCards()
  var manuscript = fx.project.ChildAt(1)
  CB.Show(fx.project, manuscript, (doc) => {
    fx.picked->add(doc.id)
  })
  assert_equal([], popup_list())
  assert_equal(2, manuscript.ChildCount())
  Close(fx)
enddef

def Test_enter_picks_the_card_that_is_shown_selected(): void
  var fx = ProjectWithCards()
  CB.Show(fx.project, fx.chapter, (doc) => {
    fx.picked->add(doc.id)
  }, fx.second.id)
  if empty(popup_list())
    assert_report('the Corkboard did not open')
  else
    feedkeys("\<CR>", 'xt')
  endif
  assert_equal([fx.second.id], fx.picked)
  Close(fx)
enddef

def Test_j_moves_the_card_later_in_the_folder(): void
  var fx = ProjectWithCards()
  CB.Show(fx.project, fx.chapter, (doc) => {
    fx.picked->add(doc.id)
  }, fx.first.id)
  if empty(popup_list())
    assert_report('the Corkboard did not open')
  else
    feedkeys('J', 'xt')
  endif
  assert_equal([fx.second.id, fx.first.id], fx.chapter.children->mapnew((_, c) => c.id))
  Close(fx)
enddef

export def RunAll(): void
  Test_cards_show_the_title_and_at_most_three_lines_of_synopsis()
  Test_a_folder_without_documents_shows_nothing_and_keeps_its_folders()
  Test_enter_picks_the_card_that_is_shown_selected()
  Test_j_moves_the_card_later_in_the_folder()
enddef
