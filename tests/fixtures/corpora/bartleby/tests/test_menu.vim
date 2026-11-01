vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_menu.vim: the native menu of menu.vim, the one that shows in the
# menu bar of gVim and MacVim and runs with :emenu. Vim runs a native entry
# in no script, so the entry must reach MenuInvoke by its autoload name.
# The popup menu is tested through the commands that use it, and for the
# entries that it disables.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/bartlebymenu.vim' as BM
import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'Logger/messages.vim' as LM
import 'bartleby/variables/constants.vim' as CO

var invoked: list<string> = []

def Test_a_native_entry_runs_its_action(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_a', 'TestMenuA')
  menu.AddItem('Run', (item) => {
    invoked->add(item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuA.Run
  assert_equal(['Run'], invoked)
  menu.UnregisterVimMenu()
enddef

def Test_each_entry_runs_its_own_action(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_b', 'TestMenuB')
  menu.AddItem('First', (item) => {
    invoked->add('first')
  })
  var sub = menu.AddItem('Sub')
  sub.AddItem('Deep', (item) => {
    invoked->add('deep ' .. item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuB.Sub.Deep
  emenu TestMenuB.First
  assert_equal(['deep Deep', 'first'], invoked)
  menu.UnregisterVimMenu()
enddef

def Test_a_label_with_dots_and_spaces_runs(): void
  if !has('menu')
    return
  endif
  invoked = []
  var menu = M.Menu.new('test_menu_c', 'TestMenuC')
  menu.AddItem('Open file...', (item) => {
    invoked->add(item.label)
  })
  menu.RegisterAsVimMenu()
  emenu TestMenuC.Open\ file\.\.\.
  assert_equal(['Open file...'], invoked)
  menu.UnregisterVimMenu()
enddef

# FUNCTION: :emenu runs a disabled entry, which the GUI shows greyed and never
# runs, so check the state that the GUI uses.
def Test_a_disabled_entry_is_registered_disabled(): void
  if !has('menu')
    return
  endif
  var menu = M.Menu.new('test_menu_d', 'TestMenuD')
  var item = menu.AddItem('Off', (it) => {
    invoked->add('ran')
  })
  item.enabled = false
  menu.AddItem('On', (it) => {
    invoked->add('ran')
  })
  menu.RegisterAsVimMenu()
  assert_false(menu_info('TestMenuD.Off', 'n').enabled)
  assert_true(menu_info('TestMenuD.On', 'n').enabled)
  menu.UnregisterVimMenu()
enddef

# FUNCTION: Sync sets an entry with a condition in both menus, and leaves
# an entry without one as the caller set it.
def Test_sync_sets_each_entry_from_its_condition(): void
  if !has('menu')
    return
  endif
  var on: bool = false
  var menu = M.Menu.new('test_menu_s', 'TestMenuS')
  var cond = menu.AddItem('Cond', (it) => {
    invoked->add('ran')
  })
  cond.When = () => on
  var fixed = menu.AddItem('Fixed', (it) => {
    invoked->add('ran')
  })
  fixed.enabled = false
  menu.RegisterAsVimMenu()
  menu.Sync()
  assert_equal([false, false], [cond.enabled, menu_info('TestMenuS.Cond', 'n').enabled])
  on = true
  menu.Sync()
  assert_equal([true, true], [cond.enabled, menu_info('TestMenuS.Cond', 'n').enabled])
  assert_equal([false, false], [fixed.enabled, menu_info('TestMenuS.Fixed', 'n').enabled])
  menu.UnregisterVimMenu()
enddef

def Test_unregistering_removes_the_entries(): void
  if !has('menu')
    return
  endif
  var menu = M.Menu.new('test_menu_e', 'TestMenuE')
  menu.AddItem('Gone', (item) => {
    invoked->add('ran')
  })
  menu.RegisterAsVimMenu()
  menu.UnregisterVimMenu()
  assert_fails('emenu TestMenuE.Gone', 'E')
enddef

# FUNCTION: Bartleby's own native menu: an entry runs its Ex command. Close
# logs a message when nothing is open, which shows that the command ran.
def Test_an_entry_of_the_bartleby_menu_runs_its_command(): void
  if !has('menu')
    return
  endif
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  BM.RegisterNative()
  LM.Clear()
  execute 'emenu ' .. CO.PLUGIN_NAME .. '.Scrive.Close'
  var logged: string = LM.History()->mapnew((_, m) => join(m.lines, ' '))->join(' ')
  assert_match('nothing of Bartleby is open', logged)
  execute 'aunmenu ' .. CO.PLUGIN_NAME
enddef

# FUNCTION: Run the check of the entries that the native menu waits for.
# The tests run before VimEnter, so fire it for that check only. The check
# must be done when the event returns, with no wait.
def StartedSync(): void
  if !v:vim_did_enter
    doautocmd bartleby_menu_sync VimEnter
  endif
enddef

# FUNCTION: The lookups are checked at each open of the popup menu, so a
# key set while Vim runs enables its entry. The native entry follows. The
# native menu registers the lookups unchecked, and checks them once Vim has
# started.
def Test_a_lookup_that_is_off_is_disabled_in_both_menus(): void
  var savedKey: string = g:bartleby_dictionary_api_key
  var savedEnv: string = $BARTLEBY_MW_DICTIONARY_KEY
  g:bartleby_dictionary_api_key = ''
  $BARTLEBY_MW_DICTIONARY_KEY = ''
  var native: bool = has('menu')
  if native
    BM.RegisterNative()
    StartedSync()
  endif
  BM.Toggle()
  BM.Toggle()
  var dict: list<any> = BM.Lookups()->copy()->filter((_, it) => it.data ==# CO.KIND_DICT)
  assert_equal(1, len(dict))
  assert_false(dict[0].enabled)
  if native
    assert_false(menu_info(dict[0].vimPath, 'n').enabled)
  endif
  if executable('curl')
    g:bartleby_dictionary_api_key = 'test-key'
    BM.Toggle()
    BM.Toggle()
    assert_true(dict[0].enabled)
    if native
      assert_true(menu_info(dict[0].vimPath, 'n').enabled)
    endif
  endif
  if native
    execute 'aunmenu ' .. CO.PLUGIN_NAME
  endif
  g:bartleby_dictionary_api_key = savedKey
  $BARTLEBY_MW_DICTIONARY_KEY = savedEnv
enddef

# FUNCTION: The native menu checks the lookups in VimEnter itself, never
# while it registers its entries. A timer would run after Vim sent the menu
# state to the GUI.
def Test_the_native_menu_checks_the_lookups_at_vim_enter(): void
  if !has('menu')
    return
  endif
  var savedKey: string = g:bartleby_dictionary_api_key
  var savedEnv: string = $BARTLEBY_MW_DICTIONARY_KEY
  g:bartleby_dictionary_api_key = ''
  $BARTLEBY_MW_DICTIONARY_KEY = ''
  BM.Toggle()
  BM.Toggle()
  BM.Lookups()->foreach((_, it) => {
    it.enabled = true
  })
  BM.RegisterNative()
  var dict: list<any> = BM.Lookups()->copy()->filter((_, it) => it.data ==# CO.KIND_DICT)
  var atRegister: bool = menu_info(dict[0].vimPath, 'n').enabled
  StartedSync()
  assert_equal([true, false], [atRegister, menu_info(dict[0].vimPath, 'n').enabled])
  execute 'aunmenu ' .. CO.PLUGIN_NAME
  g:bartleby_dictionary_api_key = savedKey
  $BARTLEBY_MW_DICTIONARY_KEY = savedEnv
enddef

# FUNCTION: A disabled entry of the popup menu shows in the disabled
# highlight before it is selected.
def Test_a_disabled_entry_is_dimmed_in_the_popup(): void
  var menu = M.Menu.new('test_menu_f', 'TestMenuF')
  var sub = menu.AddItem('Sub')
  sub.AddItem('On', (it) => {
    invoked->add('on')
  })
  var off = sub.AddItem('Off', (it) => {
    invoked->add('off')
  })
  off.enabled = false
  highlight TestMenuDim ctermfg=8 guifg=Grey
  menu.disabled_hl = 'TestMenuDim'
  menu.Open()
  if !has('gui_running')
    feedkeys("\<CR>", 'xt')
  endif
  var dimmed: list<any> = popup_list()
    ->mapnew((_, w) => getmatches(w))
    ->flattennew()
    ->filter((_, m) => m.group ==# menu.disabled_hl)
  menu.Close()
  assert_equal([[2]], dimmed->mapnew((_, m) => get(m, 'pos1', [])))
enddef

export def RunAll(): void
  Test_a_native_entry_runs_its_action()
  Test_each_entry_runs_its_own_action()
  Test_a_label_with_dots_and_spaces_runs()
  Test_a_disabled_entry_is_registered_disabled()
  Test_sync_sets_each_entry_from_its_condition()
  Test_unregistering_removes_the_entries()
  Test_an_entry_of_the_bartleby_menu_runs_its_command()
  Test_a_lookup_that_is_off_is_disabled_in_both_menus()
  Test_the_native_menu_checks_the_lookups_at_vim_enter()
  Test_an_entry_that_needs_a_scrive_follows_open_and_close()
  Test_a_disabled_entry_is_dimmed_in_the_popup()
enddef

# FUNCTION: An entry that needs a scrive is dimmed while none is open, and
# follows an open and a close at once, with no open of the popup menu.
def Test_an_entry_that_needs_a_scrive_follows_open_and_close(): void
  if !has('menu')
    return
  endif
  ST.Set(null_object)
  BM.RegisterNative()
  StartedSync()
  var path: string = [CO.PLUGIN_NAME, MC.Binder(), MI.Toggle()]
    ->mapnew((_, l) => escape(l, '. \\'))
    ->join('.')
  var states: list<bool> = [menu_info(path, 'n').enabled]
  ST.Set(PO.Project.new(tempname() .. CO.SCRIVE_EXT))
  states->add(menu_info(path, 'n').enabled)
  ST.Set(null_object)
  states->add(menu_info(path, 'n').enabled)
  assert_equal([false, true, false], states)
  execute 'aunmenu ' .. CO.PLUGIN_NAME
enddef
