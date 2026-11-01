vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# profile.vim: author and contact information for compile: name, author,
# address, phone, and email. A global profile and an optional override
# per scrive, merged by field: an empty scrive field takes the global
# value. Edited with inputpopup.vim.
#
# ProjInfo is defined before the functions that use it because several
# of them name it in a parameter or return type, and Vim9 resolves a
# signature when the function is defined.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/data.vim' as MD
import 'bartleby/variables/constants.vim' as CO

const AUTHORNAME: string = 'authorname'
const ADDR: string = 'address'
const CITY: string = 'city'
const STATE: string = 'state'
const COUNTRYCODE: string = 'countrycode'
const ZIP: string = 'zip'
const PHONENUMBER: string = 'phonenumber'
const EMAIL: string = 'email'
const PATH_PROJ_INFO_JSON: string = '/project-info.json'
const FIRSTNAME: string = 'firstname'
const MIDDLENAME: string = 'middlename'
const SUFFIX: string = 'suffix'

var log = L.New(expand('<sfile>:t'))

const FIELDS: list<string> = ['prefix', 'firstname', 'middlename', 'surname', 'suffix',
  AUTHORNAME, ADDR, CITY, STATE, COUNTRYCODE, ZIP, PHONENUMBER, EMAIL]

export class ProjInfo
  var prefix: string = ''
  var firstname: string = ''
  var middlename: string = ''
  var surname: string = ''
  var suffix: string = ''
  var authorname: string = ''
  var address: string = ''
  var city: string = ''
  var state: string = ''
  var countrycode: string = ''
  var zip: string = ''
  var phonenumber: string = ''
  var email: string = ''

  static def FromDict(src: dict<any>): ProjInfo
    var info: ProjInfo = ProjInfo.new()
    info.prefix = get(src, 'prefix', '')
    info.firstname = get(src, 'firstname', '')
    info.middlename = get(src, 'middlename', '')
    info.surname = get(src, 'surname', '')
    info.suffix = get(src, 'suffix', '')
    # A profile saved before the name had parts has one name. Split it
    # once: the first word is the first name, the last the surname, and
    # anything between the middle name. The next save keeps the parts.
    var oldName: list<string> = split(get(src, 'name', ''))
    if !empty(oldName) && info.firstname ==# '' && info.surname ==# ''
      info.firstname = oldName[0]
      info.surname = len(oldName) > 1 ? oldName[-1] : ''
      info.middlename = join(oldName[1 : -2])
    endif
    info.authorname = get(src, 'authorname', '')
    info.address = get(src, 'address', '')
    info.city = get(src, 'city', '')
    info.state = get(src, 'state', '')
    info.countrycode = get(src, 'countrycode', '')
    info.zip = get(src, 'zip', '')
    info.phonenumber = get(src, 'phonenumber', '')
    info.email = get(src, 'email', '')
    return info
  enddef

  def ToDict(): dict<any>
    return {prefix: this.prefix, firstname: this.firstname, middlename: this.middlename,
      surname: this.surname, suffix: this.suffix, authorname: this.authorname, address: this.address,
      city: this.city, state: this.state, countrycode: this.countrycode,
      zip: this.zip, phonenumber: this.phonenumber, email: this.email}
  enddef

  # METHOD: Return the full legal name: the parts that are not empty,
  # from the prefix to the suffix.
  def FullName(): string
    return [this.prefix, this.firstname, this.middlename, this.surname, this.suffix]
      ->filter((_, p) => p !=# '')->join(' ')
  enddef

  # METHOD: Return the author name, or the full name when the author is
  # empty.
  def EffectiveAuthor(): string
    return this.authorname !=# '' ? this.authorname : this.FullName()
  enddef
endclass

export def GlobalPath(): string
  return expand('~/.bartleby/profile.json')
enddef

export def ScriveInfoPath(project: PO.Project): string
  return project.scriveDir .. PATH_PROJ_INFO_JSON
enddef

def LoadFrom(path: string): ProjInfo
  if !filereadable(path)
    return ProjInfo.new()
  endif
  return ProjInfo.FromDict(PE.ReadJson(path))
enddef

export def LoadGlobal(): ProjInfo
  return LoadFrom(GlobalPath())
enddef

export def LoadForScrive(project: PO.Project): ProjInfo
  return LoadFrom(ScriveInfoPath(project))
enddef

# FUNCTION: Merge the scrive profile of project with the global profile,
# by field: an empty scrive field takes the global value.
export def Resolve(project: PO.Project): ProjInfo
  var g: dict<any> = LoadGlobal().ToDict()
  var s: dict<any> = LoadForScrive(project).ToDict()
  var merged: dict<any> = {}
  for f in FIELDS
    merged[f] = get(s, f, '') !=# '' ? s[f] : get(g, f, '')
  endfor
  return ProjInfo.FromDict(merged)
enddef

def FormLayout(): list<list<string>>
  return [['prefix', FIRSTNAME, MIDDLENAME], ['surname', SUFFIX], ['authorname'],
    ['address'], ['city', STATE, COUNTRYCODE, ZIP], ['phonenumber'], ['email']]
enddef

# FUNCTION: Return the width of each form field. A field with a fixed
# international maximum is that wide, see FormMaxLens, and
# inputpopup.vim adds one column for the cursor. The others are wide
# enough for usual values, and longer text scrolls.
def FormWidths(): dict<number>
  return {
    prefix: 8, firstname: 16, middlename: 16, surname: 20, suffix: 6,
    authorname: 32, address: 40, city: 20, phonenumber: 20, email: 32,
  }->extend(FormMaxLens())
enddef

# FUNCTION: Return the maximum length of the fields that have a fixed
# international maximum: a subdivision code of ISO 3166-2 has at most 3
# characters, a country code of ISO 3166-1 alpha-2 has 2, and the longest
# postal codes have 10, such as a US ZIP+4 code.
def FormMaxLens(): dict<number>
  return {state: 3, countrycode: 2, zip: 10}
enddef

def FormLabels(): dict<string>
  return {
    prefix: MD.Prefix(),
    firstname: MD.First(),
    middlename: MD.Middle(),
    surname: MD.Surname(),
    suffix: MD.Suffix(),
    authorname: MD.AuthorName(),
    address: MD.Addr(),
    city: MD.City(),
    state: MD.State(),
    countrycode: MD.Country(),
    zip: MD.Zip(),
    phonenumber: MD.PhoneNum(),
    email: MD.Email(),
  }
enddef

def SaveAndValidate(path: string, vals: dict<any>, requireName: bool): void
  if requireName && get(vals, 'firstname', '') ==# '' && get(vals, 'surname', '') ==# ''
    log.Error(MD.NameRequired())
    return
  endif
  PE.WriteJson(path, vals)
enddef

export def EditGlobal(): void
  var current: dict<any> = LoadGlobal().ToDict()
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(FormLayout()), current,
    {title: MD.Profile(CO.PLUGIN_NAME), labels: FormLabels(),
      widths: FormWidths(), maxlengths: FormMaxLens()})
  form.OnSubmit((vals: dict<any>) => {
    SaveAndValidate(GlobalPath(), vals, true)
  })
  form.Open()
enddef

export def EditForScrive(project: PO.Project): void
  var globalDict: dict<any> = LoadGlobal().ToDict()
  var current: dict<any> = Resolve(project).ToDict()
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(FormLayout()), current,
    {title: MD.Info(project.name), labels: FormLabels(),
      widths: FormWidths(), maxlengths: FormMaxLens()})
  form.OnSubmit((vals: dict<any>) => {
    var overrides: dict<any> = {}
    for key in keys(vals)
      overrides[key] = vals[key] ==# get(globalDict, key, '') ? '' : vals[key]
    endfor
    SaveAndValidate(ScriveInfoPath(project), overrides, false)
  })
  form.Open()
enddef
