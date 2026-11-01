vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartlebymenu.vim: a menu of Bartleby's global commands in groups, built
# on menu.vim. It adds to commandpalette.vim: the palette is fast when you
# know what you want, and the menu lets you browse by group when you do
# not. Both have the same commands: the global ones. Binder actions such
# as New Chapter or Rename need an item under the cursor, so they are in
# neither.
#
# The menu is built once, at first use, and reused. Menu.new registers
# the menu by name for the hotkey, so building it on every open would
# leave old registrations.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/menu.vim' as M
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

const CMD_DEFINE: string = 'BartlebyDefine'
const CMD_THESAURUS: string = 'BartlebyThesaurus'
const PROJ_GROUP: string = 'bartleby_menu_proj'

var menu: M.Menu = null_object
# The lookup entries, each with its kind as data. The tests read them.
var lookups: list<M.MenuItem> = []

def RunEx(cmd: string): func(M.MenuItem)
  return (_: M.MenuItem) => {
    execute cmd
  }
enddef

def PromptThenEx(title: string, cmd: string, complete: string = ''): func(M.MenuItem)
  return (_: M.MenuItem) => {
    IP.PromptText(title, '', (name: string) => {
      if name !=# ''
        execute $'{cmd} {name}'
      endif
    }, null_function, complete)
  }
enddef

def HasProj(): bool
  return ST.Get() isnot null_object
enddef

# FUNCTION: Dim each of items while no scrive is open.
def NeedProj(items: list<any>): void
  for item in items
    item.When = HasProj
  endfor
enddef

def LookupOn(kind: string): func(): bool
  return (): bool => LE.IsEnabled(kind)
enddef

def BuildMenu(): M.Menu
  var m: M.Menu = M.Menu.new(CO.MENU_NAME, CO.PLUGIN_NAME)

  var scrive: M.MenuItem = m.AddItem(MI.Scrive())
  scrive.AddItem(MI.List(), RunEx(CO.CMD_LIST))
  scrive.AddItem(MI.Open(), PromptThenEx(MI.OpenScrive(), CO.CMD_OPEN))
  scrive.AddItem(MI.New(), PromptThenEx(MI.NewScrive(), CO.CMD_NEW_SCRIVE))
  scrive.AddItem(MI.NewFrom(),
    PromptThenEx(MI.NewScriveFrom(), CO.CMD_NEW_SCRIVE_FROM, CO.COMPLETE_FILE))
  NeedProj([scrive.AddItem(MC.Close(), RunEx(CO.CMD_CLOSE))])

  var binder: M.MenuItem = m.AddItem(MC.Binder())
  binder.AddItem(MI.Toggle(), RunEx(CO.CMD_TOGGLE_BINDER))
  binder.AddItem(MI.Search(), RunEx(CO.CMD_SEARCH))
  binder.AddItem(MI.Import(), RunEx(CO.CMD_IMPORT))
  binder.AddItem(MI.EmptyTrash(), RunEx(CO.CMD_EMPTY_TRASH))
  binder.AddItem(MI.RecoverFiles(), RunEx(CO.CMD_RECOVER))
  binder.AddItem(MI.TidyFiles(), RunEx(CO.CMD_TIDY_FILES))
  binder.AddItem(MC.OpenScrivening(), RunEx(CO.CMD_SCRIVENINGS))
  binder.AddItem(MI.CloseScrivening(), RunEx(CO.CMD_SCRIVENINGS_BANG))
  NeedProj(binder.items)

  var view: M.MenuItem = m.AddItem(MC.View())
  var inspector: M.MenuItem = view.AddItem(MI.ToggleInspector(),
    RunEx(CO.CMD_TOGGLE_INSPECTOR))
  view.AddItem(MI.ToggleFocus(), RunEx(CO.CMD_FOCUS))
  NeedProj([
    inspector,
    view.AddItem(MI.WritingProgress(), RunEx(CO.CMD_PROGRESS)),
    view.AddItem(MI.WritingGoals(), RunEx(CO.CMD_GOALS)),
  ])
  view.AddItem(MI.ToggleSpotlight(), RunEx(CO.CMD_SPOTLIGHT))
  view.AddItem(MI.PickSpotlightMode(), (_: M.MenuItem) => SP.PickMode())
  view.AddItem(MI.ToggleQuill(), RunEx(CO.CMD_QUILL))

  var doc: M.MenuItem = m.AddItem(MI.Doc())
  NeedProj([
    doc.AddItem(MI.TakeSnap(), RunEx(CO.CMD_SNAP)),
    doc.AddItem(MI.ViewSnaps(), RunEx(CO.CMD_SNAPS)),
  ])
  doc.AddItem(MI.InsertTable(), RunEx(CO.CMD_TABLE))
  # The native menu is built at startup, before lexicon.vim loads, so the
  # lookups are always there, and Sync disables the ones that are off.
  lookups = [
    doc.AddItem(MI.DefineWord(), RunEx(CMD_DEFINE), CO.KIND_DICT),
    doc.AddItem(MI.Thesaurus(), RunEx(CMD_THESAURUS), CO.KIND_THESAURUS),
  ]
  for item in lookups
    item.When = LookupOn(item.data)
  endfor

  var project: M.MenuItem = m.AddItem(MI.Proj())
  project.AddItem(MI.EditProfile(), RunEx(CO.CMD_PROFILE))
  project.AddItem(MI.EditInfo(), RunEx(CO.CMD_PROJ_INFO))
  project.AddItem(MC.Compile(), RunEx(CO.CMD_COMPILE))
  NeedProj(project.items)

  return m
enddef

# FUNCTION: Open or close the popup menu. The entries are checked at each
# open, so that a key set while Vim runs counts.
export def Toggle(): void
  if menu is null_object
    menu = BuildMenu()
  endif
  Sync()
  menu.Toggle()
enddef

# FUNCTION: Disable each entry whose condition is false, in the popup menu
# and in the native menu.
export def Sync(): void
  menu.Sync()
enddef

# FUNCTION: Return the lookup entries of the menu. The tests use it.
export def Lookups(): list<M.MenuItem>
  return lookups
enddef

# FUNCTION: In gVim, also register the menu as :amenu entries, so that it
# shows in the gVim menu bar and runs with :emenu. The popup menu does
# not change. The entries are checked once Vim has started, so that
# lexicon.vim does not load while gVim starts. The check runs directly,
# not from a timer: a timer runs inside the wait for input, after Vim has
# sent the menu state to the GUI, so the GUI would show the change only
# after the next key. A timer started before VimEnter can also fire
# during the start.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/33
# The native menu has no event for its own open, so it also syncs when a
# scrive opens or closes.
export def RegisterNative(): void
  if menu is null_object
    menu = BuildMenu()
  endif
  menu.RegisterAsVimMenu()
  execute $'augroup {PROJ_GROUP}'
  autocmd!
  execute $'autocmd User {CO.EVENT_PROJ_CHANGED} Sync()'
  augroup END
  if v:vim_did_enter
    Sync()
  else
    augroup bartleby_menu_sync
      autocmd!
      autocmd VimEnter * ++once Sync()
    augroup END
  endif
enddef
