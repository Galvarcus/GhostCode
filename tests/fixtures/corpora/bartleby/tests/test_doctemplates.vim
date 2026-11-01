vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_doctemplates.vim: templates for new documents. Finding them for
# the folder of a new document, your own beside Bartleby's, filling in
# their placeholders, and asking for one in the Binder.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/doctemplates.vim' as DT
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI

const BUILTIN: string = fnamemodify(expand('<script>'), ':p:h:h') .. '/templates'

def Names(found: list<dict<string>>): list<string>
  return found->mapnew((_, t) => t.name)
enddef

def RowOf(project: any, item: any): any
  return T.FindRowById(T.Flatten(project), item.id)
enddef

def Cleanup(project: any): void
  popup_clear()
  FI.CleanupProjectFiles(project)
enddef

def Test_a_name_comes_from_the_file_name(): void
  assert_equal('Character sheet', DT.Label('character-sheet'))
  assert_equal('Research note', DT.Label('research_note'))
  assert_equal('Place', DT.Label('place'))
enddef

def Test_bartleby_has_templates_for_characters_and_research(): void
  for ext in ['.md', '.fountain']
    assert_equal(['Character sheet'], Names(DT.List('characters', ext, [BUILTIN])), ext)
    assert_equal(['Place', 'Research note'], Names(DT.List('research', ext, [BUILTIN])), ext)
    assert_equal([], DT.List('manuscript', ext, [BUILTIN]), ext)
  endfor
enddef

def Test_your_templates_add_to_and_replace_bartlebys(): void
  var dir: string = FI.TempPath()
  mkdir(dir .. '/characters', 'p')
  writefile(['mine'], dir .. '/characters/character-sheet.md')
  writefile(['villain'], dir .. '/characters/villain.md')
  var found: list<dict<string>> = DT.List('characters', '.md', [BUILTIN, dir])
  delete(dir, 'rf')
  assert_equal(['Character sheet', 'Villain'], Names(found))
  assert_match('^' .. PA.Canon(dir), PA.Canon(found[0].path))
enddef

def Test_placeholders_are_filled_and_unknown_ones_stay(): void
  assert_equal(['# Mara by Joe', '## Appearance', '{{unknown}}', '[[Name]]'],
    DT.Fill(['# {{title}} by {{author}}', '## {{t:Appearance}}', '{{unknown}}', '[[{{t:Name}}]]'],
      {title: 'Mara', author: 'Joe'}))
enddef

def Test_a_template_is_filled_for_its_scrive(): void
  var project = FI.BuildProject()
  var lines: list<string> = DT.Lines(BUILTIN .. '/research/research-note.md', project, 'Maps')
  assert_equal('## Source', get(lines, 0, ''))
  assert_true(index(lines, strftime('%Y-%m-%d')) >= 0)
  Cleanup(project)
enddef

# FUNCTION: The templates of the nearest folder around a new document whose
# role has any: inside a folder for the folder itself, beside a document
# for its folder, and through a folder of no role to the one above it.
def Test_the_folder_of_a_new_document_decides(): void
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  var research = project.ChildAt(4)
  assert_equal(['Character sheet'], Names(DT.ForRow(project, RowOf(project, chars))))
  var mara = BI.BinderItem.NewDocument('Mara', 'characters/mara.md')
  chars.AddChild(mara)
  assert_equal(['Character sheet'], Names(DT.ForRow(project, RowOf(project, mara))))
  var maps = BI.BinderItem.NewFolder('Maps')
  research.AddChild(maps)
  assert_equal(['Place', 'Research note'], Names(DT.ForRow(project, RowOf(project, maps))))
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  assert_equal([], DT.ForRow(project, RowOf(project, scene)))
  Cleanup(project)
enddef

def Test_adding_where_templates_apply_asks_first(): void
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  var before: number = len(popup_list())
  B.AddDocAsked(project, RowOf(project, chars), 'Mara')
  assert_equal(before + 1, len(popup_list()))
  assert_equal(0, len(chars.children))
  Cleanup(project)
enddef

def Test_adding_where_none_apply_adds_at_once(): void
  var project = FI.BuildProject()
  var chapter = project.ChildAt(1).ChildAt(0)
  var before: number = len(popup_list())
  B.AddDocAsked(project, RowOf(project, chapter.ChildAt(0)), 'Scene 2')
  assert_equal(before, len(popup_list()))
  assert_equal(['Scene 1', 'Scene 2'], chapter.children->mapnew((_, c) => c.title))
  assert_equal(PA.Canon(chapter.ChildAt(1).AbsPath(project.BinderRoot())), PA.Canon(expand('%:p')))
  silent! :%bwipe!
  Cleanup(project)
enddef

def Test_a_new_document_holds_its_template(): void
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  var item = B.AddDocNear(project, RowOf(project, chars), 'Mara', ['## Age'])
  assert_equal(['## Age'], readfile(item.AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

# FUNCTION: A document made from a link gets the first template, without a
# question, so that following a link stays one step.
def Test_a_document_from_a_link_gets_the_first_template(): void
  var project = FI.BuildProject()
  var lines: list<string> = DT.FirstLines(project, RowOf(project, project.ChildAt(3)), 'Mara')
  assert_equal('## Role in the story', get(lines, 0, ''))
  assert_equal([], DT.FirstLines(project, RowOf(project, project.ChildAt(1)), 'Scene'))
  Cleanup(project)
enddef

# FUNCTION: Following a link to a missing title from a character sheet, and
# answering yes, makes a character sheet.
def Test_following_a_link_makes_a_document_from_the_template(): void
  var project = FI.BuildProject()
  ST.Set(project)
  var chars = project.ChildAt(3)
  var mara = BI.BinderItem.NewDocument('Mara', 'characters/mara.md')
  chars.AddChild(mara)
  FI.WriteDocContent(project, mara, ['Sister of [[Nobody]].'])
  execute 'edit! ' .. fnameescape(mara.AbsPath(project.BinderRoot()))
  cursor(1, 15)
  LK.Follow()
  popup_close(popup_list()[-1], 1)
  var made = chars.children->copy()->filter((_, c) => c.title ==# 'Nobody')
  assert_equal(1, len(made))
  if !empty(made)
    assert_equal('## Role in the story', get(readfile(made[0].AbsPath(project.BinderRoot())), 0, ''))
  endif
  silent! :%bwipe!
  ST.Set(null_object)
  Cleanup(project)
enddef

# FUNCTION: A chapter has no templates of its own, so a scene in it gets
# those of the Manuscript around it.
def Test_a_role_without_templates_falls_back_to_the_one_above(): void
  var dir: string = FI.TempPath()
  mkdir(dir .. '/manuscript', 'p')
  writefile(['## Goal'], dir .. '/manuscript/scene.md')
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var found: list<dict<string>> = DT.ForRow(project, RowOf(project, scene), [BUILTIN, dir])
  delete(dir, 'rf')
  assert_equal(['Scene'], Names(found))
  Cleanup(project)
enddef

# FUNCTION: Enter takes the template that the picker shows first, and the
# new document opens in the edit window with it.
def Test_a_document_from_the_picker_opens_with_its_template(): void
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  B.AddDocAsked(project, RowOf(project, chars), 'Mara')
  feedkeys("\<CR>", 'xt')
  assert_equal(['Mara'], chars.children->mapnew((_, c) => c.title))
  if !empty(chars.children)
    assert_equal(PA.Canon(chars.ChildAt(0).AbsPath(project.BinderRoot())), PA.Canon(expand('%:p')))
    assert_equal('## Role in the story', getline(1))
  endif
  silent! :%bwipe!
  Cleanup(project)
enddef

export def RunAll(): void
  Test_a_name_comes_from_the_file_name()
  Test_bartleby_has_templates_for_characters_and_research()
  Test_your_templates_add_to_and_replace_bartlebys()
  Test_placeholders_are_filled_and_unknown_ones_stay()
  Test_a_template_is_filled_for_its_scrive()
  Test_the_folder_of_a_new_document_decides()
  Test_adding_where_templates_apply_asks_first()
  Test_adding_where_none_apply_adds_at_once()
  Test_a_new_document_holds_its_template()
  Test_a_document_from_a_link_gets_the_first_template()
  Test_following_a_link_makes_a_document_from_the_template()
  Test_a_role_without_templates_falls_back_to_the_one_above()
  Test_a_document_from_the_picker_opens_with_its_template()
enddef
