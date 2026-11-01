vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_links.vim: links between documents. Finding the link under the
# cursor, matching its title, gf, creating a missing document, updating the
# links when a document is renamed, how compile shows them, and the titles
# offered after [[, the highlighting of good and broken links, and links
# to a heading, as [[Mara#Backstory]].
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby.vim' as BA
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import 'Logger/messages.vim' as LM
import './fixtures.vim' as FI
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: The fixture project, with a document titled Mara in Characters,
# and a file on disk for each document.
def Project(): any
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  chars.AddChild(BI.BinderItem.NewDocument('Mara', 'characters/mara.md'))
  for item in [Scene(project, 0), Scene(project, 1), chars.ChildAt(0)]
    FI.WriteDocContent(project, item, ['text'])
  endfor
  return project
enddef

# FUNCTION: The document Scene 1 of chapter n + 1. Both are titled Scene 1.
def Scene(project: any, n: number): any
  return project.ChildAt(1).ChildAt(n).ChildAt(0)
enddef

def Edit(project: any, item: any, lines: list<string>): void
  FI.WriteDocContent(project, item, lines)
  execute 'edit! ' .. fnameescape(item.AbsPath(project.BinderRoot()))
enddef

def Cleanup(project: any): void
  popup_clear()
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

def Test_a_link_is_found_anywhere_on_its_brackets(): void
  var line: string = 'See [[Mara]] now'
  for col in [5, 6, 8, 11, 12]
    assert_equal({target: 'Mara', text: 'Mara'}, LK.At(line, col), $'col {col}')
  endfor
  assert_equal({}, LK.At(line, 4))
  assert_equal({}, LK.At(line, 13))
enddef

def Test_a_link_with_its_own_text_and_two_links_on_a_line(): void
  var line: string = '[[A]] and [[Mara|the captain]]'
  assert_equal({target: 'A', text: 'A'}, LK.At(line, 2))
  assert_equal({target: 'Mara', text: 'the captain'}, LK.At(line, 20))
  assert_equal({target: 'Mara', text: 'Mara'}, LK.At('[[ Mara ]]', 4))
enddef

def Test_a_title_matches_exactly_or_else_without_case(): void
  var project = Project()
  assert_equal(['Mara'], LK.Find(project, 'Mara')->mapnew((_, d) => d.title))
  assert_equal(['Mara'], LK.Find(project, 'mara')->mapnew((_, d) => d.title))
  assert_equal(2, len(LK.Find(project, 'Scene 1')))
  assert_equal([], LK.Find(project, 'Nobody'))
  Cleanup(project)
enddef

def Test_a_document_in_the_trash_is_not_a_target(): void
  var project = Project()
  var rows = T.Flatten(project)
  TR.MoveToTrash(project, T.FindRowById(rows, project.ChildAt(3).ChildAt(0).id))
  assert_equal([], LK.Find(project, 'Mara'))
  Cleanup(project)
enddef

def Test_gf_on_a_link_opens_its_document(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['She met [[Mara]] at dawn.'])
  cursor(1, 12)
  LK.Follow()
  assert_match('characters/mara\.md$', PA.Canon(expand('%:p')))
  Cleanup(project)
enddef

def Test_gf_on_a_title_that_two_documents_share_offers_a_choice(): void
  var project = Project()
  ST.Set(project)
  Edit(project, project.ChildAt(3).ChildAt(0), ['See [[Scene 1]].'])
  cursor(1, 8)
  var before: number = len(popup_list())
  LK.Follow()
  assert_equal(before + 1, len(popup_list()))
  Cleanup(project)
enddef

def Test_gf_on_a_missing_title_offers_to_create_it(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See [[Nobody]].'])
  cursor(1, 8)
  var before: number = len(popup_list())
  LK.Follow()
  assert_equal(before + 1, len(popup_list()))
  Cleanup(project)
enddef

def Test_a_created_document_goes_next_to_the_current_one(): void
  var project = Project()
  var scene = Scene(project, 0)
  var item = B.AddDocNear(project, T.FindRowById(T.Flatten(project), scene.id), 'Nobody')
  assert_equal(['Scene 1', 'Nobody'], project.ChildAt(1).ChildAt(0).children->mapnew((_, c) => c.title))
  assert_true(filereadable(item.AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

# FUNCTION: Off a link, gf does what it does without Bartleby: it opens the
# file named under the cursor.
def Test_gf_off_a_link_opens_the_file_under_the_cursor(): void
  var file: string = FI.TempPath()
  writefile(['x'], file)
  enew!
  setline(1, file)
  # Vim's own gf will not leave a modified buffer without 'hidden'.
  setlocal nomodified
  cursor(1, 2)
  LK.Follow()
  assert_equal(PA.Canon(file), PA.Canon(expand('%:p')))
  silent! :%bwipe!
  delete(file)
enddef

def Test_a_rename_points_links_at_the_new_title_and_keeps_their_text(): void
  var [out, count] = LK.Retitle(['[[Mara]] and [[mara|her]] but [[Marat]]'], 'Mara', 'Mara Jones')
  assert_equal(['[[Mara Jones|Mara]] and [[Mara Jones|her]] but [[Marat]]'], out)
  assert_equal(2, count)
enddef

def Test_a_rename_updates_open_buffers_and_closed_files(): void
  var project = Project()
  FI.WriteDocContent(project, Scene(project, 1), ['Ask [[Mara]].'])
  Edit(project, Scene(project, 0), ['See [[Mara]].'])
  project.ChildAt(3).ChildAt(0).Rename('Mara Jones')
  assert_equal(2, LK.Retarget(project, 'Mara', 'Mara Jones'))
  assert_equal(['See [[Mara Jones|Mara]].'], getline(1, '$'))
  assert_equal(['Ask [[Mara Jones|Mara]].'], readfile(Scene(project, 1).AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

def Test_counting_links_changes_nothing(): void
  var project = Project()
  FI.WriteDocContent(project, Scene(project, 1), ['Ask [[Mara]].'])
  assert_equal(1, LK.Retarget(project, 'Mara', 'Mara Jones', false))
  assert_equal(['Ask [[Mara]].'], readfile(Scene(project, 1).AbsPath(project.BinderRoot())))
  Cleanup(project)
enddef

# FUNCTION: A link reads as its text in a Manuscript or a Book. In a
# screenplay [[ ]] is a Fountain note, which the screenplay compiler drops.
def Test_compile_shows_links_as_their_text_except_in_a_screenplay(): void
  var project = Project()
  var scene = Scene(project, 0)
  FI.WriteDocContent(project, scene, ['She met [[Mara|the captain]].'])
  var play = C.CompileTarget.FromDict({name: 'P', kind: 'Screenplay', format: 'PDF', includedIds: [scene.id]})
  var book = C.CompileTarget.FromDict({name: 'B', kind: 'Book', format: 'HTML', includedIds: [scene.id]})
  assert_equal(['She met [[Mara|the captain]].'], C.ConcatenateDocs(project, play, ''))
  assert_true(index(C.ConcatenateBook(project, book), 'She met the captain.') >= 0)
  Cleanup(project)
enddef

def Test_gf_is_mapped_to_follow_a_link(): void
  assert_equal('<Plug>(BartlebyFollowLink)', maparg('gf', 'n'))
enddef

# FUNCTION: Record the entries of the completion menu as [abbr, menu,
# word]. A test calls it from insert mode, while the menu is open.
def g:TLinksCapture(): void
  g:tlinks_items = complete_info(['items']).items->mapnew((_, i) => [i.abbr, i.menu, i.word])
enddef

# FUNCTION: Type keys in insert mode at the end of line 1: [[, the offer
# of the titles, then keys. Return the menu entries and the line.
def Offer(keys: string): list<any>
  g:tlinks_items = []
  feedkeys("A[[\<Cmd>call bartleby#links#CompleteTitles()\<CR>"
    .. "\<Cmd>call TLinksCapture()\<CR>" .. keys .. "\<Esc>", 'xt')
  return [g:tlinks_items, getline(1)]
enddef

# FUNCTION: Two documents titled Scene 1 are both offered, told apart by
# their folders.
def Test_double_brackets_offer_the_titles_with_their_folders(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See '])
  var copt: string = &completeopt
  var offer: list<any> = Offer('')
  assert_equal([['Scene 1', 'Manuscript / 1', 'Scene 1]]'], ['Scene 1', 'Manuscript / 2', 'Scene 1]]'],
    ['Mara', 'Characters', 'Mara]]']], offer[0])
  assert_equal(copt, &completeopt)
  Cleanup(project)
enddef

def Test_a_document_in_the_trash_is_not_offered(): void
  var project = Project()
  ST.Set(project)
  var rows = T.Flatten(project)
  TR.MoveToTrash(project, T.FindRowById(rows, project.ChildAt(3).ChildAt(0).id))
  Edit(project, Scene(project, 0), ['See '])
  assert_equal(['Scene 1', 'Scene 1'], Offer('')[0]->mapnew((_, i) => i[0]))
  Cleanup(project)
enddef

# FUNCTION: Picking an entry is Vim's own, and the tests run with no
# popup menu, so check the text that each entry inserts.
def Test_a_title_ends_the_link_unless_brackets_follow(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See '])
  assert_equal('Mara]]', Offer('')[0][-1][2])
  setline(1, 'See ]]')
  cursor(1, 4)
  g:tlinks_items = []
  feedkeys("a[[\<Cmd>call bartleby#links#CompleteTitles()\<CR>\<Cmd>call TLinksCapture()\<CR>\<Esc>", 'xt')
  assert_equal('Mara', g:tlinks_items[-1][2])
  Cleanup(project)
enddef

def Test_bracket_is_mapped_only_in_documents_of_a_scrive_in_prose(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['text'])
  BA.EnterLinkDoc()
  assert_match('CompleteTitles', maparg('[', 'i'))
  assert_match('CompleteHeadings', maparg('#', 'i'))
  enew!
  BA.EnterLinkDoc()
  assert_equal('', maparg('[', 'i'))
  project.InitNew(project.name, CO.TYPE_SCREENPLAY)
  execute 'edit! ' .. fnameescape(Scene(project, 1).AbsPath(project.BinderRoot()))
  BA.EnterLinkDoc()
  assert_equal('', maparg('[', 'i'))
  Cleanup(project)
enddef

# FUNCTION: Quill maps the arrow keys and Enter in insert mode. While the
# title menu shows, they must move in it and pick, so each map gives the
# plain key then. The tests run with no popup menu, so check the maps,
# and that Enter still splits the line with no menu.
def Test_quill_keys_pass_to_the_title_menu(): void
  enew!
  setline(1, 'See')
  # Soft wrap maps the same keys, and leaves autoformat off, which would
  # join the new line back.
  Q.Init('soft')
  for key in ['<Up>', '<Down>', '<CR>']
    var m: dict<any> = maparg(key, 'i', false, true)
    assert_true(get(m, 'expr', false), key)
    assert_match('^pumvisible()', get(m, 'rhs', ''), key)
  endfor
  feedkeys("A\<CR>x\<Esc>", 'xt')
  assert_equal(['See', 'x'], getline(1, '$'))
  Q.Init('off')
  silent! :%bwipe!
enddef

# FUNCTION: Return the link properties of the current buffer, as [lnum,
# col, length, type].
def LinkProps(): list<any>
  if empty(prop_type_get('BartlebyLink'))
    return []
  endif
  return prop_list(1, {end_lnum: -1, types: ['BartlebyLink', 'BartlebyLinkBroken']})
    ->mapnew((_, p) => [p.lnum, p.col, p.length, p.type])
enddef

# FUNCTION: A link is good when gf finds its document, exactly or without
# case. A missing title, or one only in the Trash, is broken.
def Test_links_are_highlighted_good_or_broken(): void
  var project = Project()
  project.ChildAt(4).AddChild(BI.BinderItem.NewDocument('Ghost', 'research/ghost.md'))
  TR.MoveToTrash(project, T.FindRowById(T.Flatten(project), project.ChildAt(4).ChildAt(0).id))
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See [[Mara]] and [[mara|her]].', '[[Nobody]] then [[Ghost]]', 'None here.'])
  BA.EnterLinkDoc()
  assert_equal([[1, 5, 8, 'BartlebyLink'], [1, 18, 12, 'BartlebyLink'],
    [2, 1, 10, 'BartlebyLinkBroken'], [2, 17, 9, 'BartlebyLinkBroken']], LinkProps())
  assert_equal('SpellBad', hlget('BartlebyLinkBroken')[0].linksto)
  assert_equal('Underlined', hlget('BartlebyLink')[0].linksto)
  Cleanup(project)
enddef

def Test_a_rename_updates_the_link_highlights(): void
  var project = Project()
  ST.Set(project)
  Edit(project, Scene(project, 0), ['See [[Mara]].'])
  BA.EnterLinkDoc()
  assert_equal('BartlebyLink', LinkProps()[0][3])
  project.ChildAt(3).ChildAt(0).Rename('Mara Jones')
  LK.RefreshWindows(project)
  assert_equal('BartlebyLinkBroken', LinkProps()[0][3])
  Cleanup(project)
enddef

def Test_a_scrivening_keeps_its_title_properties(): void
  var project = Project()
  FI.WriteDocContent(project, Scene(project, 1), ['Meet [[Mara]].'])
  ST.Set(project)
  SV.Open(project, project.ChildAt(1))
  var titles: number = len(prop_list(1, {end_lnum: -1}))
  BA.EnterLinkDoc()
  assert_equal(1, len(LinkProps()))
  assert_equal(titles + 1, len(prop_list(1, {end_lnum: -1})))
  set nomodified
  SV.Close()
  Cleanup(project)
enddef

def Test_a_screenplay_note_is_not_a_link(): void
  var project = Project()
  project.InitNew(project.name, CO.TYPE_SCREENPLAY)
  ST.Set(project)
  Edit(project, Scene(project, 0), ['[[Mara]]'])
  BA.EnterLinkDoc()
  assert_equal([], LinkProps())
  Cleanup(project)
enddef

# FUNCTION: A scrive reached through a symlink: Vim names a buffer by the
# resolved path, and AbsPath does not resolve. Unsaved text in an open
# buffer must still count, for the links to a document and for a rename.
# The fixture is under /tmp, which is a symlink only on macOS, so this
# test makes one of its own.
def Test_open_buffers_count_behind_a_symlink(): void
  var real: string = FI.TempPath()
  mkdir(real, 'p')
  var link: string = $'{real}-link'
  if !FI.MakeLink(real, link)
    echomsg 'SKIP: the system made no symbolic link'
    delete(real, 'rf')
    return
  endif
  var project = PO.Project.new($'{link}/fixture.bartleby')
  project.InitNew('Linked', CO.TYPE_NOVEL)
  var manuscript = BI.BinderItem.NewFolder('Manuscript', CO.ROLE_MANUSCRIPT)
  var chars = BI.BinderItem.NewFolder('Characters', CO.ROLE_CHARS)
  var mara = BI.BinderItem.NewDocument('Mara', 'characters/mara.md')
  var scene = BI.BinderItem.NewDocument('Scene', 'manuscript/scene.md')
  manuscript.AddChild(scene)
  chars.AddChild(mara)
  project.SeedTree([manuscript, chars])
  FI.WriteDocContent(project, mara, ['Mara.'])
  FI.WriteDocContent(project, scene, ['Nothing yet.'])
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(scene.AbsPath(project.BinderRoot()))
  setline(1, 'See [[Mara]].')
  assert_equal(['Scene'], LK.LinkedFrom(project, mara)->mapnew((_, d) => d.title))
  assert_equal(1, LK.Retarget(project, 'Mara', 'Mara Jones', false))
  set nomodified
  # A Scrivening saves the open documents it shows, and closes their
  # buffers.
  var scenePath: string = scene.AbsPath(project.BinderRoot())
  setline(1, 'Changed.')
  SV.Open(project, manuscript)
  assert_equal(['Changed.'], readfile(scenePath))
  assert_equal(-1, bufnr(scenePath))
  set nomodified
  SV.Close()
  silent! :%bwipe!
  ST.Set(null_object)
  delete(link)
  delete(real, 'rf')
enddef

# FUNCTION: The fixture project, where Mara has two headings, Departure
# is Scene 1 of chapter 2 with one, and a document is titled Chapter #3.
def HeadingProject(): any
  var project = Project()
  FI.WriteDocContent(project, project.ChildAt(3).ChildAt(0), ['# Mara', 'Intro.', '', '## Backstory ##', 'Born.'])
  Scene(project, 1).Rename('Departure')
  FI.WriteDocContent(project, Scene(project, 1), ['Leaving.', '## Platform', 'Steam.'])
  var chapter3 = BI.BinderItem.NewDocument('Chapter #3', 'research/chapter-3.md')
  project.ChildAt(4).AddChild(chapter3)
  FI.WriteDocContent(project, chapter3, ['Three.'])
  ST.Set(project)
  return project
enddef

def Test_a_target_splits_into_title_and_heading(): void
  var sets: dict<dict<bool>> = {exact: {'Chapter #3': true}, lower: {'chapter #3': true}}
  assert_equal(['Mara', 'Backstory'], LK.Split('Mara#Backstory', sets))
  assert_equal(['Mara', 'Back story'], LK.Split('Mara # Back story', sets))
  assert_equal(['Mara', ''], LK.Split('Mara', sets))
  assert_equal(['Chapter #3', ''], LK.Split('Chapter #3', sets))
  assert_equal(['chapter #3', ''], LK.Split('chapter #3', sets))
enddef

def Test_gf_on_a_heading_link_goes_to_the_heading(): void
  var project = HeadingProject()
  Edit(project, Scene(project, 0), ['See [[Mara#backstory]].'])
  cursor(1, 8)
  LK.Follow()
  assert_match('characters/mara\.md$', PA.Canon(expand('%:p')))
  assert_equal('## Backstory ##', getline('.'))
  Cleanup(project)
enddef

def Test_gf_on_a_missing_heading_opens_the_top_and_says_so(): void
  var project = HeadingProject()
  Edit(project, Scene(project, 0), ['See [[Mara#Nowhere]].'])
  cursor(1, 8)
  LM.Clear()
  LK.Follow()
  assert_match('characters/mara\.md$', PA.Canon(expand('%:p')))
  assert_equal(1, line('.'))
  assert_match('has no heading', LM.History()->mapnew((_, m) => join(m.lines, ' '))->join(' '))
  Cleanup(project)
enddef

def Test_gf_on_a_heading_link_in_a_scrivening(): void
  var project = HeadingProject()
  FI.WriteDocContent(project, Scene(project, 0), ['See [[Departure#Platform]].'])
  SV.Open(project, project.ChildAt(1))
  cursor(search('Departure#Platform', 'w'), 8)
  LK.Follow()
  assert_true(SV.IsScrivening(bufnr()), 'left the Scrivening')
  assert_equal('## Platform', getline('.'))
  set nomodified
  SV.Close()
  Cleanup(project)
enddef

def Test_a_heading_link_is_broken_without_its_heading(): void
  var project = HeadingProject()
  Edit(project, Scene(project, 0), ['[[Mara#Backstory]] [[Mara#Nowhere]] [[Nobody#X]] [[Chapter #3]]'])
  BA.EnterLinkDoc()
  assert_equal(['BartlebyLink', 'BartlebyLinkBroken', 'BartlebyLinkBroken', 'BartlebyLink'],
    LinkProps()->mapnew((_, p) => p[3]))
  Cleanup(project)
enddef

def Test_a_rename_keeps_the_heading_and_the_shown_title(): void
  var [out, count] = LK.Retitle(['[[Mara#Backstory]] [[mara#Backstory|her]] [[Mara]] [[Marat#Backstory]]'],
    'Mara', 'Mara Jones')
  assert_equal(['[[Mara Jones#Backstory|Mara]] [[Mara Jones#Backstory|her]] [[Mara Jones|Mara]] [[Marat#Backstory]]'], out)
  assert_equal(3, count)
  [out, count] = LK.Retitle(['[[Chapter #3]]'], 'Chapter #3', 'Chapter Three')
  assert_equal(['[[Chapter Three|Chapter #3]]'], out)
enddef

def Test_compile_shows_a_heading_link_as_its_title(): void
  var project = HeadingProject()
  assert_equal(['See Mara, her past, and Chapter #3.'],
    LK.Plain(['See [[Mara#Backstory]], [[Mara#Backstory|her past]], and [[Chapter #3]].']))
  Cleanup(project)
enddef

def Test_hash_after_a_title_offers_its_headings(): void
  var project = HeadingProject()
  Edit(project, Scene(project, 0), ['See '])
  g:tlinks_items = []
  feedkeys("A[[Mara#\<Cmd>call bartleby#links#CompleteHeadings()\<CR>\<Cmd>call TLinksCapture()\<CR>\<Esc>", 'xt')
  assert_equal([['Mara', '', 'Mara]]'], ['Backstory', '', 'Backstory]]']], g:tlinks_items)
  Cleanup(project)
enddef

export def RunAll(): void
  Test_a_link_is_found_anywhere_on_its_brackets()
  Test_a_link_with_its_own_text_and_two_links_on_a_line()
  Test_a_title_matches_exactly_or_else_without_case()
  Test_a_document_in_the_trash_is_not_a_target()
  Test_gf_on_a_link_opens_its_document()
  Test_gf_on_a_title_that_two_documents_share_offers_a_choice()
  Test_gf_on_a_missing_title_offers_to_create_it()
  Test_a_created_document_goes_next_to_the_current_one()
  Test_gf_off_a_link_opens_the_file_under_the_cursor()
  Test_a_rename_points_links_at_the_new_title_and_keeps_their_text()
  Test_a_rename_updates_open_buffers_and_closed_files()
  Test_counting_links_changes_nothing()
  Test_compile_shows_links_as_their_text_except_in_a_screenplay()
  Test_gf_is_mapped_to_follow_a_link()
  Test_double_brackets_offer_the_titles_with_their_folders()
  Test_a_document_in_the_trash_is_not_offered()
  Test_a_title_ends_the_link_unless_brackets_follow()
  Test_bracket_is_mapped_only_in_documents_of_a_scrive_in_prose()
  Test_quill_keys_pass_to_the_title_menu()
  Test_links_are_highlighted_good_or_broken()
  Test_a_rename_updates_the_link_highlights()
  Test_a_scrivening_keeps_its_title_properties()
  Test_a_screenplay_note_is_not_a_link()
  Test_open_buffers_count_behind_a_symlink()
  Test_a_target_splits_into_title_and_heading()
  Test_gf_on_a_heading_link_goes_to_the_heading()
  Test_gf_on_a_missing_heading_opens_the_top_and_says_so()
  Test_gf_on_a_heading_link_in_a_scrivening()
  Test_a_heading_link_is_broken_without_its_heading()
  Test_a_rename_keeps_the_heading_and_the_shown_title()
  Test_compile_shows_a_heading_link_as_its_title()
  Test_hash_after_a_title_offers_its_headings()
enddef
