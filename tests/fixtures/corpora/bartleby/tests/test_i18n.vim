vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_i18n.vim: T and N of i18n.vim. Without a translation, both
# return English, and N chooses the English plural form. With one, they
# return the translated text: the test compiles a small German
# translation into a temporary folder with msgfmt, binds the text domain
# to it, and switches the message language. It skips that part when
# msgfmt or a German locale is not installed.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/document.vim' as D
import autoload 'bartleby/lang.vim' as LA
import 'bartleby/variables/constants.vim' as CO

const PO: list<string> = [
  'msgid ""',
  'msgstr ""',
  '"Content-Type: text/plain; charset=UTF-8\n"',
  '"Plural-Forms: nplurals=2; plural=(n != 1);\n"',
  '',
  'msgid "Open Scrive"',
  'msgstr "Scrive öffnen"',
  '',
  'msgid "%d document"',
  'msgid_plural "%d documents"',
  'msgstr[0] "%d Dokument"',
  'msgstr[1] "%d Dokumente"',
  '',
  'msgid "Chapter: "',
  'msgstr "Kapitel: "',
  '',
  'msgid "Red"',
  'msgstr "Rot"',
  '',
  'msgid "Label:"',
  'msgstr "Markierung:"',
]

def Test_untranslated_text_is_english(): void
  assert_equal('Open Scrive', IN.T("Open Scrive"))
  assert_equal('1 document', printf(IN.N("%d document", "%d documents", 1), 1))
  assert_equal('3 documents', printf(IN.N("%d document", "%d documents", 3), 3))
enddef

def Test_translation_is_used(): void
  if !executable('msgfmt')
    echomsg 'SKIP: msgfmt not installed'
    return
  endif
  var dir: string = tempname()
  mkdir(dir .. '/de/LC_MESSAGES', 'p')
  writefile(PO, dir .. '/de.po')
  system($'msgfmt -o {dir}/de/LC_MESSAGES/{CO.TEXT_DOMAIN}.mo {dir}/de.po')
  var saved: string = v:lang
  try
    language messages de_DE.UTF-8
  catch
    echomsg 'SKIP: no German locale'
    delete(dir, 'rf')
    return
  endtry
  bindtextdomain(CO.TEXT_DOMAIN, dir)
  assert_equal('Scrive öffnen', IN.T("Open Scrive"))
  assert_equal('1 Dokument', printf(IN.N("%d document", "%d documents", 1), 1))
  assert_equal('3 Dokumente', printf(IN.N("%d document", "%d documents", 3), 3))
  assert_equal('Close', IN.T("Close"))
  CheckTranslatedDisplay()
  execute 'language messages ' .. saved
  bindtextdomain(CO.TEXT_DOMAIN, LA.PluginRoot() .. '/lang')
  delete(dir, 'rf')
enddef

# FUNCTION: With the German test translation active, the display names
# are German, and the Binder and Inspector syntax files, which build their
# patterns from those names, highlight the German texts.
def CheckTranslatedDisplay(): void
  assert_equal('Kapitel: ', BI.RolePrefixes()[CO.ROLE_CHAPTER])
  assert_equal('Rot', D.LabelName('Red'))
  syntax on
  new
  setline(1, ['Title', '  ▾ Kapitel: 1/', '    · Scene (Rot)'])
  setlocal filetype=bartleby-binder
  assert_equal('bartlebyBinderRoleLabel', synIDattr(synID(2, 7, 1), 'name'))
  # The folder name after the German prefix is still a folder name.
  assert_equal('bartlebyBinderDirectory', synIDattr(synID(2, 16, 1), 'name'))
  assert_equal('bartlebyBinderItemLabel', synIDattr(synID(3, 15, 1), 'name'))
  bwipe!
  new
  setline(1, ['::Inspector::', 'Markierung: Rot'])
  setlocal filetype=bartleby-inspector
  assert_equal('bartlebyInspectorField', synIDattr(synID(2, 1, 1), 'name'))
  bwipe!
enddef

export def RunAll(): void
  Test_untranslated_text_is_english()
  Test_translation_is_used()
enddef
