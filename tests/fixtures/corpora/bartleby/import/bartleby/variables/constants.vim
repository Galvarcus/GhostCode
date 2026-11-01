vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# import/bartleby/variables/constants.vim: every constant that more than
# one script uses, each defined once. Import it with a plain import, which
# Vim finds in the import folder of runtimepath:
#   import 'bartleby/variables/constants.vim' as CO
# This file imports nothing, so it can never be part of an import cycle.
# A constant that only one script uses stays in that script.
# License: GNU GPL 3.0
##############################################################################

##############################################################################
# SECTION: Identity. Display names derive from PLUGIN_NAME. Values stored
# on disk, SCRIVE_EXT and SCRIVE_FOLDER, have their own literals: they
# identify existing user data, so they must not change with the name.
##############################################################################

export const PLUGIN_NAME: string = 'Bartleby'
export const MENU_NAME: string = tolower(PLUGIN_NAME)
# The gettext package of Bartleby's messages, and the name of its .mo
# files, see i18n.vim.
export const TEXT_DOMAIN: string = tolower(PLUGIN_NAME)
export const SCRIVE_EXT: string = '.bartleby'
export const SCRIVE_FOLDER: string = 'Bartleby'
export const PROJ_FILE: string = 'project.json'

##############################################################################
# SECTION: Pane buffers. windows.vim protects these panes from being
# replaced, and each pane's own script creates its buffer by this name.
##############################################################################

export const BINDER_BUF: string = $'{PLUGIN_NAME}-Binder'
export const INSPECTOR_BUF: string = $'{PLUGIN_NAME}-Inspector'
export const COMPILE_SELECT_BUF: string = $'{PLUGIN_NAME}-Compile-Select'

# The buffer of a Scrivening. It is an editor buffer, not a pane, so that
# documents and other buffers can replace it in its window.
export const SCRIVENINGS_BUF: string = $'{PLUGIN_NAME}-Scrivenings'

##############################################################################
# SECTION: Binder items and scrive types.
##############################################################################

export const KIND_FOLDER: string = 'folder'
export const KIND_DOC: string = 'document'

# What a folder is in the structure, independent of its title. ROLE_PART
# and ROLE_CHAPTER exist only under ROLE_MANUSCRIPT, and ROLE_CUSTOM only
# at the top level. ROLE_NONE is a plain folder. See binderitem.vim.
export const ROLE_NONE: string = ''
export const ROLE_FRONT_MATTER: string = 'front-matter'
export const ROLE_MANUSCRIPT: string = 'manuscript'
export const ROLE_PART: string = 'part'
export const ROLE_CHAPTER: string = 'chapter'
export const ROLE_CHARS: string = 'characters'
export const ROLE_RESEARCH: string = 'research'
# The Trash, always the last folder at the top level, see trash.vim.
export const ROLE_TRASH: string = 'trash'
export const ROLE_BACK_MATTER: string = 'back-matter'
export const ROLE_CUSTOM: string = 'custom'

export const TYPE_NOVEL: string = 'novel'
export const TYPE_NOVEL_PARTS: string = 'novel_parts'
export const TYPE_SHORT_STORY: string = 'short_story'
export const TYPE_SCREENPLAY: string = 'screenplay'
# Every scrive type, in the order that pickers show them.
export const TYPES: list<string> = [TYPE_NOVEL, TYPE_NOVEL_PARTS, TYPE_SHORT_STORY, TYPE_SCREENPLAY]

##############################################################################
# SECTION: Document metadata. The display strings are also the stored
# values. syntax/bartleby-binder.vim builds its label rule from LABELS.
##############################################################################

# The empty label and the empty status, the first entry of both lists and
# the default of both, so that a document nobody has marked claims no
# state, as an unlabeled one claims no color.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/42
export const NONE: string = 'None'
export const LABELS: list<string> = [NONE, 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple']
export const STATUS_TODO: string = 'To Do'
export const STATUS_WORKING: string = 'Working Draft'
export const STATUS_FIRST: string = 'First Draft'
export const STATUS_REVISED: string = 'Revised'
export const STATUS_FINAL: string = 'Final Draft'
export const STATUS_DONE: string = 'Done'
# In the order of the work, which is the order the pickers of the
# Inspector and the Outliner show.
export const STATUSES: list<string> = [NONE, STATUS_TODO, STATUS_WORKING,
  STATUS_FIRST, STATUS_REVISED, STATUS_FINAL, STATUS_DONE]

##############################################################################
# SECTION: Dictionary and thesaurus. Each reference names its provider,
# see lexicon.vim, and a language file chooses its default references.
##############################################################################

export const KIND_DICT: string = 'dictionary'
export const KIND_THESAURUS: string = 'thesaurus'
export const REFS: dict<dict<string>> = {
  collegiate: {
    provider: 'merriam-webster',
    apiName: 'collegiate',
    kind: KIND_DICT,
    title: 'Merriam-Webster Dictionary',
  },
  thesaurus: {
    provider: 'merriam-webster',
    apiName: 'thesaurus',
    kind: KIND_THESAURUS,
    title: 'Merriam-Webster Thesaurus',
  },
}

##############################################################################
# SECTION: Part of speech and Fountain. syntax/fountain.vim builds its
# character cue and scene heading rules from the two patterns.
##############################################################################

# Mode name to its list key in the lists of tools/lang/<code>.json.
export const MODE_LISTS: dict<string> = {
  Pronouns: 'pronouns',
  Determiners: 'determiners',
  Prepositions: 'prepositions',
  Conjunctions: 'conjunctions',
  Auxiliaries: 'auxiliaries',
  Fillers: 'fillers',
  Adverbs: 'adverbs',
  Contractions: 's_contraction_words',
}

export const FOUNTAIN_CHAR_PAT: string = '^\L*$'
# A scene heading starts with a standard prefix, or with a period that
# forces a heading. syntax/fountain.vim uses the two parts in two rules.
export const FOUNTAIN_SCENE_PREFIX_PAT: string = '^\c\(int\|ext\|est\|i\/e\)\([.\/]\| \)'
export const FOUNTAIN_FORCED_SCENE_PAT: string = '^\.\a'
export const FOUNTAIN_SCENE_HEADING_PAT: string =
  $'{FOUNTAIN_SCENE_PREFIX_PAT}\|{FOUNTAIN_FORCED_SCENE_PAT}'

##############################################################################
# SECTION: Files and paths that more than one script uses.
##############################################################################

export const EXT_FOUNTAIN: string = '.fountain'
export const PATH_BINDER: string = '/binder'

# The name of a title, or of a compile target, that holds nothing a name
# on disk can keep. It is stored on disk, so it has its own literal and
# never derives from a display name.
export const UNTITLED: string = 'untitled'

# The extensions that an import accepts, lowercase, by scrive type. The
# copy of an imported file takes the document extension of its scrive,
# see import.vim.
export const IMPORT_EXTS_TEXT: list<string> = ['.md', '.markdown', '.txt']
export const IMPORT_EXTS_SCREENPLAY: list<string> = IMPORT_EXTS_TEXT + [EXT_FOUNTAIN]

##############################################################################
# SECTION: Keys that more than one script uses.
##############################################################################

export const KEY_CR: string = "\<CR>"
export const KEY_C_C: string = "\<C-c>"
export const KEY_DOWN: string = "\<Down>"
export const KEY_ESC: string = "\<Esc>"
export const KEY_LEFT: string = "\<Left>"
export const KEY_LEFT_MOUSE: string = "\<LeftMouse>"
export const KEY_RIGHT: string = "\<Right>"
export const KEY_SCROLL_WHEEL_DOWN: string = "\<ScrollWheelDown>"
export const KEY_SCROLL_WHEEL_UP: string = "\<ScrollWheelUp>"
export const KEY_S_TAB: string = "\<S-Tab>"
export const KEY_TAB: string = "\<Tab>"
export const KEY_UP: string = "\<Up>"

##############################################################################
# SECTION: Names and values that more than one script uses.
##############################################################################

export const ACTION_RESTORE: string = 'Restore'
export const CMD_CLOSE: string = 'BartlebyClose'
export const CMD_COMPILE: string = 'BartlebyCompile'
export const CMD_EMPTY_TRASH: string = 'BartlebyEmptyTrash'
export const CMD_FOCUS: string = 'BartlebyFocus'
export const CMD_GOALS: string = 'BartlebyGoals'
export const CMD_IMPORT: string = 'BartlebyImport'
export const CMD_LIST: string = 'BartlebyList'
export const CMD_NEW_SCRIVE: string = 'BartlebyNewScrive'
export const CMD_NEW_SCRIVE_FROM: string = 'BartlebyNewScriveFrom'
export const CMD_OPEN: string = 'BartlebyOpen'
export const CMD_PROFILE: string = 'BartlebyProfile'
export const CMD_PROGRESS: string = 'BartlebyProgress'
export const CMD_PROJ_INFO: string = 'BartlebyProjectInfo'
export const CMD_QUILL: string = 'BartlebyQuill'
export const CMD_TABLE: string = 'BartlebyTable'
export const CMD_RECOVER: string = 'BartlebyRecover'
export const CMD_SCRIVENINGS: string = 'BartlebyScrivenings'
export const CMD_SEARCH: string = 'BartlebySearch'
export const CMD_SNAP: string = 'BartlebySnapshot'
export const CMD_SNAPS: string = 'BartlebySnapshots'
export const CMD_SPOTLIGHT: string = 'BartlebySpotlight'
export const CMD_TIDY_FILES: string = 'BartlebyTidyFiles'
export const CMD_TOGGLE_BINDER: string = 'BartlebyToggleBinder'
export const CMD_TOGGLE_INSPECTOR: string = 'BartlebyToggleInspector'
# The completion type of a popup field that holds a path, as
# getcompletion takes it. See the complete option in inputpopup.vim.
export const COMPLETE_FILE: string = 'file'
# The User event that state.vim fires when a scrive opens or closes.
export const EVENT_PROJ_CHANGED: string = 'BartlebyProjectChanged'
export const FILETYPE_FOUNTAIN: string = 'fountain'
export const HL_PMENU: string = 'Pmenu'
export const HL_PMENU_SEL: string = 'PmenuSel'
export const MODE_ADVERBS: string = 'Adverbs'
export const MODE_CONTRACTIONS: string = 'Contractions'
export const CANCEL: string = 'Cancel'
export const STATUS_ERR: string = 'error'
export const STATUS_NOTFOUND: string = 'notfound'
export const STATUS_OK: string = 'ok'
export const TYPE_TEXT: string = 'text'
export const TYPE_CHOICE: string = 'choice'
export const FILETYPE_MARKDOWN: string = 'markdown'
# A row of a pipe table: a line that starts with a bar.
export const TABLE_ROW_PAT: string = '^\s*|'

##############################################################################
# SECTION: Patterns and formats that more than one script uses.
##############################################################################

export const BELOW_CURSOR: string = 'cursor+1'
export const PAT_INSERT: string = '^[iR]'
export const PAT_NONBLANK: string = '\S'
export const PAT_NOMAGIC_BOL: string = '^\V'

##############################################################################
# SECTION: Text and marks that more than one script uses.
##############################################################################

export const CMD_SCRIVENINGS_BANG: string = 'BartlebyScrivenings!'
export const TITLE_FMT: string = ' %s '
export const ID_FMT: string = '%s-%03d'
export const ID_TIME_FMT: string = '%Y%m%d%H%M%S'
