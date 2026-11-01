vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# i18n.vim: translation of Bartleby's own messages, menus, titles, and key
# help, with Vim's gettext and ngettext. Every text that the user sees
# goes through T, or through N when it has plural forms:
#   IN.T("Open Scrive")
#   printf(IN.T("No scrive named %s"), name)
#   printf(IN.N("%d document", "%d documents", count), count)
# The text must be a double-quoted literal in the call itself, because
# tools/i18n/extract.py reads it from the source to build the template
# lang/bartleby.pot. A text with values uses printf and %s, never an
# interpolated string, so that the translated text keeps its placeholders.
# A translation may reorder them with positional placeholders, such as
# %2$s.
#
# The translations are in lang/<code>/LC_MESSAGES/bartleby.mo, compiled
# from lang/<code>.po. Vim chooses the language from its message language,
# see :help :language. A text without a translation shows in English. See
# Localization_README.md for the process.
# License: GNU GPL 3.0
##############################################################################

import 'bartleby/variables/constants.vim' as CO

const PATH_LANG: string = '/lang'

# The plugin folder, from this script's own path. This script imports
# nothing else, so every script can import it without an import cycle.
bindtextdomain(CO.TEXT_DOMAIN, expand('<sfile>:p:h:h:h') .. PATH_LANG)

# FUNCTION: Return text translated into the message language.
export def T(text: string): string
  return gettext(text, CO.TEXT_DOMAIN)
enddef

# FUNCTION: Return text from a template file, translated into the message
# language. tools/i18n/extract.py finds this text in the files themselves,
# so a call of this function needs no literal text.
export def TFile(text: string): string
  return gettext(text, CO.TEXT_DOMAIN)
enddef

# FUNCTION: Return the form of single or plural that count needs in the
# message language. The caller formats count into it with printf.
export def N(single: string, plural: string, count: number): string
  return ngettext(single, plural, count, CO.TEXT_DOMAIN)
enddef
