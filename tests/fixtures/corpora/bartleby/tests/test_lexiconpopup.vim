vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_lexiconpopup.vim: the keys of the lookup popup for a misspelled
# word. A result with suggestions is fed to the popup directly, so there is
# no network. r uses the selected suggestion, as the thesaurus does with a
# synonym, and <CR> still looks it up.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/lexicon_result.vim' as LR
import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/lexiconpopup.vim' as LP
import 'bartleby/variables/constants.vim' as CO

const NOTFOUND: LR.Result = LR.NotFound(['murmurous', 'murmurs'])

# FUNCTION: Make a buffer with the word in a sentence, and return the target
# that a lookup of the word has, as WordAtCursor makes it.
def Target(word: string): dict<any>
  silent! only
  silent! :%bwipe!
  enew
  setline(1, $'A {word} here')
  return {text: word, bufnr: bufnr(), lnum: 1, start: 2, end: 2 + strlen(word)}
enddef

def Popup(kind: string, target: dict<any>, word: string, result: LR.Result): LP.LexiconPopup
  var popup = LP.LexiconPopup.new(kind, word, target)
  popup.Open()
  popup.OnResult(result)
  return popup
enddef

const DICTIONARY_BODY: string = json_encode([
  {meta: {id: 'murmurous', stems: ['murmurous']}, hwi: {hw: 'mur*mur*ous'}, fl: 'adjective', shortdef: ['low and indistinct']},
])

const THESAURUS_BODY: string = json_encode([
  {
    meta: {id: 'component', stems: ['component'], syns: [['building block', 'element']], ants: [['whole']]},
    hwi: {hw: 'component'}, fl: 'noun', shortdef: ['one of the parts that make up a whole'],
  },
])

# FUNCTION: Return the text of every popup after the help is opened.
def HelpText(popup: LP.LexiconPopup): string
  popup.Filter(0, '?')
  return popup_list()->mapnew((_, id) => join(getbufline(winbufnr(id), 1, '$'), "\n"))->join("\n")
enddef

def Cleanup(): void
  popup_clear()
  silent! :%bwipe!
enddef

def Test_r_replaces_the_word_with_the_selected_suggestion(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'murmurus', NOTFOUND)
  popup.Filter(0, 'r')
  assert_equal('A murmurous here', getline(1))
  assert_false(popup.IsOpen())
  Cleanup()
enddef

def Test_r_uses_the_suggestion_that_j_selected(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'murmurus', NOTFOUND)
  popup.Filter(0, 'j')
  popup.Filter(0, 'r')
  assert_equal('A murmurs here', getline(1))
  Cleanup()
enddef

def Test_r_keeps_the_capitalization(): void
  var target = Target('Murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'Murmurus', NOTFOUND)
  popup.Filter(0, 'r')
  assert_equal('A Murmurous here', getline(1))
  Cleanup()
enddef

def Test_r_copies_the_suggestion_when_the_lookup_has_no_text(): void
  Target('murmurus')
  setreg('"', 'untouched')
  var popup = Popup(CO.KIND_DICT, {}, 'murmurus', NOTFOUND)
  popup.Filter(0, 'r')
  assert_equal('murmurous', getreg('"'))
  assert_equal('A murmurus here', getline(1))
  assert_false(popup.IsOpen())
  Cleanup()
enddef

def Test_r_does_nothing_without_a_suggestion(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'murmurus', LR.NotFound())
  popup.Filter(0, 'r')
  assert_equal('A murmurus here', getline(1))
  assert_true(popup.IsOpen())
  Cleanup()
enddef

def Test_r_works_in_the_thesaurus_too(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_THESAURUS, target, 'murmurus', NOTFOUND)
  popup.Filter(0, 'r')
  assert_equal('A murmurous here', getline(1))
  Cleanup()
enddef

def Test_enter_on_a_suggestion_looks_it_up_and_does_not_replace(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'murmurus', NOTFOUND)
  popup.Filter(0, "\<CR>")
  assert_equal('A murmurus here', getline(1))
  assert_false(popup.IsOpen())
  Cleanup()
enddef

def Test_the_help_lists_r_on_a_suggestion_only(): void
  var target = Target('murmurus')
  var popup = Popup(CO.KIND_DICT, target, 'murmurus', NOTFOUND)
  popup.Filter(0, '?')
  var shown: string = popup_list()->mapnew((_, id) => join(getbufline(winbufnr(id), 1, '$'), "\n"))->join("\n")
  assert_match('\n\s*r\s\+Replace the word in the text', shown)
  Cleanup()
  target = Target('murmurus')
  popup = Popup(CO.KIND_DICT, target, 'murmurus', LR.NotFound())
  popup.Filter(0, '?')
  shown = popup_list()->mapnew((_, id) => join(getbufline(winbufnr(id), 1, '$'), "\n"))->join("\n")
  assert_notmatch('\n\s*r\s\+Replace', shown)
  Cleanup()
enddef

# FUNCTION: A thesaurus word that is not found shows suggestions, and
# then <CR> looks one up. It does not replace, and there are no antonyms
# to toggle.
def Test_the_thesaurus_help_for_a_word_not_found_describes_the_suggestions(): void
  var target = Target('murmurus')
  var shown = HelpText(Popup(CO.KIND_THESAURUS, target, 'murmurus', NOTFOUND))
  assert_match('\n\s*<CR>\s\+Look up the selected suggestion', shown)
  assert_match('\n\s*r\s\+Replace the word in the text', shown)
  assert_notmatch('<CR>\s\+Replace', shown)
  assert_notmatch('Toggle antonyms', shown)
  Cleanup()
enddef

# FUNCTION: A thesaurus word that is found shows synonyms, and then <CR>
# replaces the word, or copies the synonym when the lookup has no text.
def Test_the_thesaurus_help_for_a_word_found_describes_the_synonyms(): void
  var result = LE.ParseResp(CO.KIND_THESAURUS, 'component', THESAURUS_BODY)
  var target = Target('component')
  var shown = HelpText(Popup(CO.KIND_THESAURUS, target, 'component', result))
  assert_match('\n\s*<CR>\s\+Replace the word in the text', shown)
  assert_match('\n\s*a\s\+Toggle antonyms', shown)
  assert_match('\n\s*d\s\+Define the selected word', shown)
  assert_notmatch('Look up the selected suggestion', shown)
  assert_notmatch('\n\s*r\s', shown)
  Cleanup()
  Target('component')
  shown = HelpText(Popup(CO.KIND_THESAURUS, {}, 'component', result))
  assert_match('\n\s*<CR>\s\+Copy the word', shown)
  Cleanup()
enddef

def Test_the_dictionary_help_for_a_word_not_found_lists_the_suggestion_keys(): void
  var target = Target('murmurus')
  var shown = HelpText(Popup(CO.KIND_DICT, target, 'murmurus', NOTFOUND))
  assert_match('\n\s*<CR>\s\+Look up the selected suggestion', shown)
  assert_match('\n\s*r\s\+Replace the word in the text', shown)
  assert_notmatch('Toggle antonyms', shown)
  Cleanup()
enddef

# FUNCTION: The definitions of a found word have nothing to select, so <CR>
# does nothing and the help does not list it.
def Test_the_dictionary_help_for_a_word_found_has_no_enter(): void
  var result = LE.ParseResp(CO.KIND_DICT, 'murmurous', DICTIONARY_BODY)
  var target = Target('murmurous')
  var shown = HelpText(Popup(CO.KIND_DICT, target, 'murmurous', result))
  assert_notmatch('<CR>', shown)
  assert_notmatch('\n\s*r\s', shown)
  Cleanup()
enddef

# FUNCTION: With nothing to select, <CR> and d do nothing, so the help lists
# neither, and there are no antonyms to toggle.
def Test_the_thesaurus_help_with_nothing_to_select_lists_no_selection_keys(): void
  var target = Target('xyzzy')
  var shown = HelpText(Popup(CO.KIND_THESAURUS, target, 'xyzzy', LR.NotFound()))
  assert_notmatch('<CR>', shown)
  assert_notmatch('\n\s*d\s', shown)
  assert_notmatch('Toggle antonyms', shown)
  Cleanup()
enddef

export def RunAll(): void
  Test_r_replaces_the_word_with_the_selected_suggestion()
  Test_r_uses_the_suggestion_that_j_selected()
  Test_r_keeps_the_capitalization()
  Test_r_copies_the_suggestion_when_the_lookup_has_no_text()
  Test_r_does_nothing_without_a_suggestion()
  Test_r_works_in_the_thesaurus_too()
  Test_enter_on_a_suggestion_looks_it_up_and_does_not_replace()
  Test_the_help_lists_r_on_a_suggestion_only()
  Test_the_thesaurus_help_for_a_word_not_found_describes_the_suggestions()
  Test_the_thesaurus_help_for_a_word_found_describes_the_synonyms()
  Test_the_dictionary_help_for_a_word_not_found_lists_the_suggestion_keys()
  Test_the_dictionary_help_for_a_word_found_has_no_enter()
  Test_the_thesaurus_help_with_nothing_to_select_lists_no_selection_keys()
enddef
