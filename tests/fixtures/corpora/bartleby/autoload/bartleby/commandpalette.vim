vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# commandpalette.vim: a list of Bartleby's global commands that narrows
# as you type, built on the filter field of inputpopup.vim. Type a few
# letters, move with Up and Down, and run with Enter.
#
# It runs Ex commands instead of importing modules: most functions behind
# the commands, such as OpenScrive and RunCompile, are local to
# plugin/bartleby.vim, so the :Bartleby commands are the public API.
#
# Only global commands are listed. Binder actions such as New Chapter and
# Rename need an item under the cursor, so they do not fit a list without
# context.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

const SPOTLIGHT: string = 'spotlight'
const CHOICE_PICK_SPOTLIGHT_MODE: string = 'Pick Spotlight Mode'

# Display name to Ex command, for commands without an argument.
const CMDS: dict<string> = {
  'List Scrives': CO.CMD_LIST,
  'Toggle Binder': CO.CMD_TOGGLE_BINDER,
  'Search Scrive': CO.CMD_SEARCH,
  'Import Files': CO.CMD_IMPORT,
  'Toggle Inspector': CO.CMD_TOGGLE_INSPECTOR,
  'Toggle Focus': CO.CMD_FOCUS,
  'Writing Progress': CO.CMD_PROGRESS,
  'Writing Goals': CO.CMD_GOALS,
  'Toggle Spotlight': CO.CMD_SPOTLIGHT,
  'Toggle Quill': CO.CMD_QUILL,
  'Insert Table': CO.CMD_TABLE,
  'Edit Profile': CO.CMD_PROFILE,
  'Edit Project Info': CO.CMD_PROJ_INFO,
  'Compile': CO.CMD_COMPILE,
  'Take Snapshot': CO.CMD_SNAP,
  'View Snapshots': CO.CMD_SNAPS,
  'Empty Trash': CO.CMD_EMPTY_TRASH,
  'Recover Files': CO.CMD_RECOVER,
  'Tidy Files': CO.CMD_TIDY_FILES,
  'Open Scrivening': CO.CMD_SCRIVENINGS,
  'Close Scrivening': CO.CMD_SCRIVENINGS_BANG,
  'Close Scrive': CO.CMD_CLOSE,
}

# Display name to Ex command, for commands that need an argument, asked
# for with a second PromptText.
const CMDS_WITH_ARG: dict<string> = {
  'Open Scrive': CO.CMD_OPEN,
  'New Scrive': CO.CMD_NEW_SCRIVE,
  'New Scrive from Files': CO.CMD_NEW_SCRIVE_FROM,
}

# The completion type of the argument that an entry asks for, by the name
# that CMDS_WITH_ARG uses. An entry that asks for a path completes it, and
# one that asks for a scrive name does not.
const ARG_COMPLETE: dict<string> = {
  'New Scrive from Files': CO.COMPLETE_FILE,
}

# Entries with no Ex command, called through an exported function of
# their module.
const DIRECT_ACTIONS: dict<string> = {
  'Pick Spotlight Mode': SPOTLIGHT,
}

# Display name to lexicon kind, see EnabledLookups.
const LOOKUPS: dict<string> = {
  'Define Word': 'dictionary',
  'Thesaurus': 'thesaurus',
}

export def Open(): void
  var shown: dict<string> = CmdNames()
  var options: list<string> = (keys(CMDS) + keys(CMDS_WITH_ARG)
    + keys(DIRECT_ACTIONS) + keys(EnabledLookups()))
    ->sort((a, b) => get(shown, a, a) ==? get(shown, b, b) ? 0 : get(shown, a, a) >? get(shown, b, b) ? 1 : -1)
  IP.PromptFilter(MI.CmdPalette(), options, (choice: string) => {
    Run(choice)
  }, 10, 0, shown)
enddef

# FUNCTION: Return each entry, by the name that the tables above use, to
# its name in the message language. The list shows these names, sorted.
def CmdNames(): dict<string>
  return {
    'List Scrives': MI.ListScrives(),
    'Toggle Binder': MI.ToggleBinder(),
    'Search Scrive': MI.SearchScrive(),
    'Import Files': MI.ImportFiles(),
    'Toggle Inspector': MI.ToggleInspector(),
    'Toggle Focus': MI.ToggleFocus(),
    'Writing Progress': MI.WritingProgress(),
    'Writing Goals': MI.WritingGoals(),
    'Toggle Spotlight': MI.ToggleSpotlight(),
    'Toggle Quill': MI.ToggleQuill(),
    'Insert Table': MI.InsertTable(),
    'Edit Profile': MI.EditProfile(),
    'Edit Project Info': MI.EditProjInfo(),
    'Compile': MC.Compile(),
    'Take Snapshot': MI.TakeSnap(),
    'View Snapshots': MI.ViewSnaps(),
    'Empty Trash': MI.EmptyTrash(),
    'Recover Files': MI.RecoverFiles(),
    'Tidy Files': MI.TidyFiles(),
    'Open Scrivening': MC.OpenScrivening(),
    'Close Scrivening': MI.CloseScrivening(),
    'Close Scrive': MI.CloseScrive(),
    'Open Scrive': MI.OpenScrive(),
    'New Scrive': MI.NewScrive(),
    'New Scrive from Files': MI.NewScriveFrom(),
    'Pick Spotlight Mode': MI.PickSpotlightMode(),
    'Define Word': MI.DefineWord(),
    'Thesaurus': MI.Thesaurus(),
  }
enddef

# FUNCTION: Return the lookup entries for the kinds that have an API key.
# They act on the word under the cursor in the window where the palette
# opened.
def EnabledLookups(): dict<string>
  var lookups: dict<string> = {}
  for [name, kind] in items(LOOKUPS)
    if LE.IsEnabled(kind)
      lookups[name] = kind
    endif
  endfor
  return lookups
enddef

def Run(choice: string): void
  if has_key(CMDS, choice)
    execute CMDS[choice]
    return
  endif
  if has_key(LOOKUPS, choice)
    execute LOOKUPS[choice] ==# CO.KIND_THESAURUS ? 'BartlebyThesaurus' : 'BartlebyDefine'
    return
  endif
  if has_key(CMDS_WITH_ARG, choice)
    var cmd: string = CMDS_WITH_ARG[choice]
    IP.PromptText(get(CmdNames(), choice, choice), '', (name: string) => {
      if name !=# ''
        execute $'{cmd} {name}'
      endif
    }, null_function, get(ARG_COMPLETE, choice, ''))
    return
  endif
  if choice ==# CHOICE_PICK_SPOTLIGHT_MODE
    SP.PickMode()
  endif
enddef
