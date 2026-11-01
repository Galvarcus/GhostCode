vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_slug.vim: slug.vim, which turns a title into a name on disk.
# A slug that names a Windows device is the one that cannot be left as it
# is: that system answers with the device whatever extension follows, so a
# document titled Nul was written to NUL and lost.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/55
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/slug.vim' as SU

def Test_a_title_becomes_lower_case_with_hyphens(): void
  assert_equal('a-dark-and-stormy-night', SU.Slugify('A Dark and Stormy Night'))
  assert_equal('chapter-1', SU.Slugify('Chapter 1!'))
  assert_equal('1984', SU.Slugify('1984'))
  assert_equal('', SU.Slugify('***'))
enddef

def Test_a_run_of_anything_else_becomes_one_hyphen(): void
  assert_equal('a-b', SU.Slugify('A  --  B'))
  assert_equal('leading-and-trailing', SU.Slugify('  leading and trailing  '))
  assert_equal("mr-smith-s-plan", SU.Slugify('Mr. Smith''s "Plan"'))
enddef

def Test_a_separator_of_a_path_never_survives(): void
  assert_equal('a-b-c', SU.Slugify('a/b\c'))
  assert_equal('up-here', SU.Slugify('../up/here'))
enddef

# A letter outside a to z is dropped rather than turned into its nearest
# plain letter, so Über and Ober give the same slug and a title in a
# script of its own gives none at all. Only the working files that pandoc
# and the engines read are named this way, see Safe for the rest.
def Test_a_letter_outside_ascii_is_dropped(): void
  assert_equal('caf-noir', SU.Slugify('Café Noir'))
  assert_equal('nicode-ber', SU.Slugify('Ünicode Über'))
  assert_equal('', SU.Slugify('日本語'))
enddef

# An accent can be written as one character or as a letter and a
# combining mark. A collection matches on the base character and takes
# the marks with it, so the e of the second spelling passed the class
# that a to z keeps and the mark stayed in the slug.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/65
def Test_the_two_spellings_of_an_accent_give_one_slug(): void
  var decomposed: string = 'Cafe' .. nr2char(0x301) .. ' Noir'
  assert_equal('caf-noir', SU.Slugify(decomposed))
  assert_equal(SU.Slugify('Café Noir'), SU.Slugify(decomposed))
enddef

# The slug names every working file of a compile, which a TeX engine
# reads, and the prefix of the glob that trims the logs, so a byte above
# ASCII in it is a path no engine is reliable with and a name that one
# file system stores in the spelling the glob was not built from.
def Test_no_mark_survives_into_a_slug(): void
  for title in ['Cafe' .. nr2char(0x301), 'Shalom' .. nr2char(0x05B0),
      'Hindi' .. nr2char(0x0902), 'A' .. nr2char(0x20DD),
      'Cafe' .. nr2char(0x301) .. nr2char(0x327), nr2char(0x301) .. 'abc']
    var slug: string = SU.Slugify(title)
    # Bytes against characters, because a collection matches the base of
    # a marked character and a pattern would pass on the very fault.
    assert_equal(strchars(slug), strlen(slug),
      $'the slug of {title} is [{slug}], of more bytes than characters')
  endfor
  # One slug in full, because the count above is also true of a fold
  # that answered nothing at all.
  assert_equal('shalo', SU.Slugify('Shalom' .. nr2char(0x05B0)))
enddef

# The layout asks for the name of a title whenever it lays a scrive out,
# so a slug of a slug must be the same slug, or a document would move on
# every pass.
def Test_a_slug_is_unchanged_by_a_second_pass(): void
  for title in ['A Dark and Stormy Night', 'Chapter 1!', 'Nul', 'doc-nul',
      'Café Noir', 'Cafe' .. nr2char(0x301), 'a/b\c', '  spaced  ', '***']
    assert_equal(SU.Slugify(title), SU.Slugify(SU.Slugify(title)),
      $'the slug of {title} changed on a second pass')
  endfor
enddef

def Test_a_slug_that_names_a_device_never_stands_alone(): void
  assert_equal('doc-nul', SU.Slugify('Nul'))
  assert_equal('doc-con', SU.Slugify('con'))
  assert_equal('doc-prn', SU.Slugify('PRN'))
  assert_equal('doc-aux', SU.Slugify('Aux'))
  assert_equal('doc-com1', SU.Slugify('COM1'))
  assert_equal('doc-lpt9', SU.Slugify('lpt9'))
  # The name is reached after the reduction, so punctuation does not hide
  # it.
  assert_equal('doc-nul', SU.Slugify('NUL!'))
  assert_equal('doc-nul', SU.Slugify('-nul-'))
enddef

def Test_a_title_that_merely_holds_a_device_name_is_left_alone(): void
  assert_equal('nul-and-void', SU.Slugify('Nul and void'))
  assert_equal('console', SU.Slugify('Console'))
  assert_equal('auxiliary', SU.Slugify('Auxiliary'))
  # Only COM1 to COM9 are reserved, and LPT1 to LPT9.
  assert_equal('com10', SU.Slugify('COM10'))
  assert_equal('com0', SU.Slugify('COM0'))
  # An extension in the title is reduced to a hyphen, so the stem is no
  # longer the reserved name that Windows answers for.
  assert_equal('nul-md', SU.Slugify('nul.md'))
  assert_equal('com1-txt', SU.Slugify('COM1.txt'))
enddef

# A name that the writer reads keeps the letters of the title, in any
# script, so that a folder on disk carries the name of the document.
def Test_a_name_keeps_every_letter_and_its_case(): void
  assert_equal('Über', SU.Safe('Über'))
  assert_equal('Café-Noir', SU.Safe('Café Noir'))
  assert_equal('日本語', SU.Safe('日本語'))
  assert_equal('A-Dark-and-Stormy-Night', SU.Safe('A Dark and Stormy Night'))
enddef

def Test_a_name_folds_what_a_file_system_forbids(): void
  assert_equal('Mr-Smith-s-Plan', SU.Safe('Mr. Smith''s "Plan"'))
  assert_equal('a-b-c-d-e-f-g-h-i-j', SU.Safe('a<b>c:d"e/f\g|h?i*j'))
  assert_equal('A-B', SU.Safe('A  --  B'))
  assert_equal('leading-and-trailing', SU.Safe('  leading and trailing  '))
  # Windows forbids a trailing dot and a trailing space, and neither can
  # survive the fold.
  assert_equal('trail', SU.Safe('trail. '))
  assert_equal('up-here', SU.Safe('../up/here'))
enddef

# A separator above ASCII is folded for the reason a space is: the writer
# cannot see it, and a name that holds one cannot be typed again.
def Test_a_name_folds_a_separator_above_ascii(): void
  assert_equal('no-break', SU.Safe("no\u00a0break"))
  assert_equal('', SU.Safe("\u3000\u00a0"))
  assert_equal('', SU.Safe('***'))
enddef

def Test_a_name_that_names_a_device_never_stands_alone(): void
  assert_equal('doc-Nul', SU.Safe('Nul'))
  assert_equal('doc-COM1', SU.Safe('COM1'))
  assert_equal('Console', SU.Safe('Console'))
  assert_equal('Nul-and-void', SU.Safe('Nul and void'))
enddef

# Windows reserves the superscript forms of COM1 to COM3 and LPT1 to
# LPT3 as well. Slugify destroyed them with every other character
# outside ASCII, and a name that keeps its letters can reach them.
def Test_a_name_that_names_a_device_in_superscript_is_guarded(): void
  assert_equal("doc-COM\u00b9", SU.Safe("COM\u00b9"))
  assert_equal("doc-lpt\u00b3", SU.Safe("lpt\u00b3"))
  # Only 1, 2 and 3 have a superscript that Windows reads as a digit.
  assert_equal("COM\u2074", SU.Safe("COM\u2074"))
enddef

# A slug names a file too, so it takes the same cap as a name. Before
# it did not, and a target of a very long name produced a file name the
# system refused, so the target was never saved.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/61
def Test_a_long_slug_is_capped(): void
  assert_equal(200, strlen(SU.Slugify(repeat('a', 300))))
  # A slug holds one byte to the character, however many marks the title
  # carried, so a cap in bytes is a cap in characters as well. Here the
  # cut lands on the hyphen of a folded letter, which the edge strip
  # then takes, so the name is one byte under the cap.
  var marked: string = SU.Slugify(repeat('a' .. 'e' .. nr2char(0x301), 200))
  assert_equal(199, strlen(marked))
  assert_equal(strchars(marked), strlen(marked),
    $'the slug [{marked}] holds a mark')
  assert_equal(marked, SU.Slugify(marked), 'the capped slug moved again')
enddef

# A path component holds 255 bytes, and a title of three bytes to the
# character reaches that in eighty-five characters.
def Test_a_long_name_is_capped_on_a_character(): void
  var long: string = repeat('日', 100)
  var name: string = SU.Safe(long)
  assert_true(strlen(name) <= 200, $'{strlen(name)} bytes is over the cap')
  assert_equal(66, strchars(name))
  assert_equal(long[0 : 2], name[0 : 2])
  # A cut that lands on a fold must not leave the name ending in one.
  assert_true(SU.Safe('a' .. repeat('-b', 200))[-1 : ] !=# SU.SEP)
  # A name keeps its marks, so a cut must take one with the letter it
  # sits on rather than strand it. The slug holds none to strand.
  var marked: string = SU.Safe(repeat('e' .. nr2char(0x301), 100))
  assert_equal(198, strlen(marked))
  assert_equal(66, strchars(marked, 1))
  assert_notequal(nr2char(0x301), marked[-2 : ])
enddef

# A caller with less room than the cap passes it, rather than cutting
# the name this returns: a cut after the guards undoes them, so three
# bytes of room gave Nul, the device, from Nullify.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/67
def Test_a_budgeted_cut_onto_a_device_name_is_guarded(): void
  assert_equal('doc-Nul', SU.Safe('Nullify', 3))
  assert_equal('doc-Com1', SU.Safe('Com1x', 4))
  assert_equal('doc-nul', SU.Slugify('Nullify', 3))
  assert_equal('doc-com1', SU.Slugify('Com1x', 4))
enddef

# A caller's room never raises the cap. A shallow folder leaves more
# room than a component holds, and a budget of that room gave a name of
# 320 bytes, which the save then refused.
def Test_a_budget_over_the_cap_leaves_the_cap(): void
  assert_equal(200, strlen(SU.Slugify(repeat('a', 300), 900)))
  assert_equal(200, strlen(SU.Safe(repeat('a', 300), 900)))
enddef

# A budget under zero is met by nothing, so the cut ends on the empty
# name rather than running for ever. Without that, this test hangs Vim
# rather than failing.
def Test_a_budget_under_zero_keeps_nothing(): void
  assert_equal('', SU.Capped('abc', -1))
  assert_equal('', SU.Safe('abc', -1))
  assert_equal('', SU.Slugify('abc', -1))
enddef

def Test_a_budgeted_cut_leaves_no_separator_at_an_edge(): void
  assert_equal('ab', SU.Safe('ab-cd', 3))
  assert_equal('ab', SU.Slugify('ab cd', 3))
enddef

def Test_a_budgeted_cut_lands_on_a_whole_character(): void
  # Café takes five bytes, so a budget of four keeps three letters.
  assert_equal('Caf', SU.Safe('Café Noir', 4))
  var wide: string = SU.Safe(repeat('日', 10), 4)
  assert_equal(3, strlen(wide))
  assert_equal(1, strchars(wide))
enddef

def Test_a_name_is_unchanged_by_a_second_pass(): void
  for title in ['Über', 'Café Noir', '日本語', 'Nul', 'doc-Nul',
      'a/b\c', '  spaced  ', '***', repeat('日', 100)]
    assert_equal(SU.Safe(title), SU.Safe(SU.Safe(title)),
      $'the name of {title} changed on a second pass')
  endfor
enddef

export def RunAll(): void
  Test_a_title_becomes_lower_case_with_hyphens()
  Test_a_run_of_anything_else_becomes_one_hyphen()
  Test_a_separator_of_a_path_never_survives()
  Test_a_letter_outside_ascii_is_dropped()
  Test_the_two_spellings_of_an_accent_give_one_slug()
  Test_no_mark_survives_into_a_slug()
  Test_a_slug_is_unchanged_by_a_second_pass()
  Test_a_slug_that_names_a_device_never_stands_alone()
  Test_a_title_that_merely_holds_a_device_name_is_left_alone()
  Test_a_name_keeps_every_letter_and_its_case()
  Test_a_name_folds_what_a_file_system_forbids()
  Test_a_name_folds_a_separator_above_ascii()
  Test_a_name_that_names_a_device_never_stands_alone()
  Test_a_name_that_names_a_device_in_superscript_is_guarded()
  Test_a_long_slug_is_capped()
  Test_a_long_name_is_capped_on_a_character()
  Test_a_budgeted_cut_onto_a_device_name_is_guarded()
  Test_a_budget_over_the_cap_leaves_the_cap()
  Test_a_budget_under_zero_keeps_nothing()
  Test_a_budgeted_cut_leaves_no_separator_at_an_edge()
  Test_a_budgeted_cut_lands_on_a_whole_character()
  Test_a_name_is_unchanged_by_a_second_pass()
enddef
