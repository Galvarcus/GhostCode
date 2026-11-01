vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autoload/bartleby/locale/compile.vim:
# the messages of compile, the tagger, and the dictionary.
# One function for each message. The English text, which is the message id
# for translators, is written once, in the call to IN.T or IN.N, and the
# function returns it translated when it is called. Import it with an
# autoload import, so that it loads only when a message is first needed:
#   import autoload 'bartleby/locale/compile.vim' as MK
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN

##############################################################################
# SECTION: compile.vim
##############################################################################

export def Book(): string
  return IN.T("Book")
enddef

export def CompileSelectContents(): string
  return IN.T("Compile - Select Contents")
enddef

export def ToggleInclusionFolders(): string
  return IN.T("Toggle inclusion (folders toggle all descendants)")
enddef

export def ConfirmSelContinue(): string
  return IN.T("Confirm selection and continue")
enddef

export def CompileSettings(): string
  return IN.T("Compile Settings")
enddef

export def Name(): string
  return IN.T("Name")
enddef

export def Font(): string
  return IN.T("Font")
enddef

export def CoverImg(): string
  return IN.T("Cover Image")
enddef

export def Sep(): string
  return IN.T("Separator")
enddef

export def CompileTargetName(): string
  return IN.T("compile target name is required")
enddef

export def CompileKind(): string
  return IN.T("Compile Kind")
enddef

export def Fmt(): string
  return IN.T("Format")
enddef

export def LineSpacing(): string
  return IN.T("Line Spacing")
enddef

export def Double(): string
  return IN.T("Double")
enddef

export def Single(): string
  return IN.T("Single")
enddef

export def TargetNameTwice(name: any, used: any, ignored: any): string
  return printf(IN.T("the name \"%s\" is in two files: using %s, ignoring %s"),
    name, used, ignored)
enddef

export def NothingToDelete(name: any): string
  return printf(IN.T("no compile target is named \"%s\""), name)
enddef

export def DeleteFailed(path: any): string
  return printf(IN.T("could not delete %s"), path)
enddef

export def NameStillInUse(name: any): string
  return printf(IN.T("another file still carries the name \"%s\""), name)
enddef

export def ReplaceCompileTarget(name: any): string
  return printf(IN.T("Another compile target is named \"%s\". Replace it?"),
    name)
enddef

export def NotCompiled(name: any): string
  return printf(IN.T("\"%s\" was not compiled, because it was not saved"),
    name)
enddef

export def KeptCompileTarget(name: any): string
  return printf(IN.T("kept \"%s\", so nothing was saved"), name)
enddef

export def DeleteCompileTarget(name: any): string
  return printf(IN.T("Delete compile target \"%s\"?"), name)
enddef

export def DeletedCompileTarget(name: any): string
  return printf(IN.T("deleted compile target: %s"), name)
enddef

export def SkippingMissingFile(path: any): string
  return printf(IN.T("skipping missing file: %s"), path)
enddef

export def RenameFailed(path: any, name: any): string
  return printf(IN.T("compiled %s, but it could not be renamed to %s"), path, name)
enddef

export def ArtifactNameShared(artifact: any, other: any, kept: any): string
  return printf(IN.T("two targets compile to %s, this one and \"%s\": keeping %s"),
    artifact, other, kept)
enddef

export def Compiled(path: any): string
  return printf(IN.T("compiled: %s"), path)
enddef

export def CompiledOpen(name: any): string
  return printf(IN.T("Compiled \"%s\". Open it?"), name)
enddef

export def AlreadyCompiling(name: any): string
  return printf(IN.T("\"%s\" is already compiling"), name)
enddef

export def Compiling(name: any, label: any): string
  return printf(IN.T("compiling \"%s\" (%s)..."), name, label)
enddef

export def ExitedStatus(cmd: any, status: any, err: any): string
  return printf(IN.T("%s exited with status %s: %s"), cmd, status, err)
enddef

export def Cmd(cmd: any): string
  return printf(IN.T("Command: %s"), cmd)
enddef

export def ExitStatus(status: any): string
  return printf(IN.T("Exit status: %s"), status)
enddef

export def NoErrOutput(): string
  return IN.T("No error output.")
enddef

export def CompilingFailedOpen(name: any): string
  return printf(IN.T("Compiling \"%s\" failed. Open the log?"), name)
enddef

export def ScreenplainNotFound(bin: any): string
  return printf(IN.T("screenplain not found (%s) - install via pip, or set g:bartleby_compile_screenplain_bin"), bin)
enddef

export def PandocNotFound(bin: any): string
  return printf(IN.T("pandoc not found (%s) - install it or set g:bartleby_compile_pandoc_bin"), bin)
enddef

export def EngineNotFound(engine: any): string
  return printf(IN.T("%s not found - a PDF needs a TeX distribution, see Requirements in the README"), engine)
enddef

export def MissingTex(kind: any, files: any): string
  return printf(IN.T("a %s PDF needs TeX files that are not installed: %s - see Requirements in the README"), kind, files)
enddef

export def CoverNotFound(path: any): string
  return printf(IN.T("cover image not found: %s"), path)
enddef

export def UnknownPaperSize(size: any): string
  return printf(IN.T("unknown paper size \"%s\", using letter"), size)
enddef

export def TargetNotFound(choice: any): string
  return printf(IN.T("target not found: %s"), choice)
enddef

export def Msg(choice: any): string
  return printf(IN.T("\"%s\""), choice)
enddef

export def Run(): string
  return IN.T("Run")
enddef

export def Edit(): string
  return IN.T("Edit")
enddef

export def Delete(): string
  return IN.T("Delete")
enddef

export def NewTarget(): string
  return IN.T("+ New Target")
enddef

##############################################################################
# SECTION: lang.vim
##############################################################################

export def MissingLangFile(path: any): string
  return printf(IN.T("missing language file: %s"), path)
enddef

export def NoLangFile(lang: any, path: any): string
  return printf(IN.T("no language file for \"%s\", using English: %s"), lang, path)
enddef

export def CannotReadLang(path: any): string
  return printf(IN.T("cannot read language file: %s"), path)
enddef

##############################################################################
# SECTION: lexicon.vim
##############################################################################

export def NoRefLang(label: any, ref: any): string
  return printf(IN.T("no %s reference \"%s\" for this language"), label, ref)
enddef

export def LookupsOffSet(label: any, kind: any, envName: any): string
  return printf(IN.T("%s lookups are off: set g:bartleby_%s_api_key or $%s"), label, kind, envName)
enddef

export def LookupsNeedCurl(label: any): string
  return printf(IN.T("%s lookups need curl, which was not found"), label)
enddef

export def NoReferenceForThis(label: any): string
  return printf(IN.T("no %s reference for this language"), label)
enddef

export def Thesaurus(): string
  return IN.T("thesaurus")
enddef

export def Dict(): string
  return IN.T("dictionary")
enddef

export def ExitCode(code: any): string
  return printf(IN.T("exit code %s"), code)
enddef

export def LookupFailed(detail: any): string
  return printf(IN.T("lookup failed: %s"), detail)
enddef

export def CouldNotStart(): string
  return IN.T("could not start curl")
enddef

export def IgnoringUnreadableLexicon(path: any): string
  return printf(IN.T("ignoring unreadable lexicon cache: %s"), path)
enddef

export def CouldNotWrite(path: any): string
  return printf(IN.T("could not write lexicon cache: %s"), path)
enddef

##############################################################################
# SECTION: lexiconpopup.vim
##############################################################################

export def LookupsNotAvailable(): string
  return IN.T("lookups are not available in Bartleby panes")
enddef

export def NoWordUnder(): string
  return IN.T("no word under the cursor")
enddef

export def NothingLookUp(): string
  return IN.T("nothing to look up")
enddef

export def SelectTextOne(): string
  return IN.T("select text on one line only")
enddef

export def SelEmpty(): string
  return IN.T("the selection is empty")
enddef

export def LookingUp(word: any): string
  return printf(IN.T("Looking up \"%s\" ..."), word)
enddef

export def NoEntry(word: any): string
  return printf(IN.T("No entry for \"%s\"."), word)
enddef

export def DidMean(): string
  return IN.T("Did you mean:")
enddef

export def NoAntonyms(): string
  return IN.T("(no antonyms)")
enddef

export def CopiedUnnamedRegister(value: any): string
  return printf(IN.T("\"%s\" copied to the unnamed register"), value)
enddef

export def ChangedSinceLookup(text: any): string
  return printf(IN.T("\"%s\" changed since the lookup - not replaced"), text)
enddef

export def BufCannotChanged(): string
  return IN.T("this buffer cannot be changed")
enddef

export def NextWord(): string
  return IN.T("Next word")
enddef

export def ScrollDown(): string
  return IN.T("Scroll down")
enddef

export def PrevWord(): string
  return IN.T("Previous word")
enddef

export def ScrollUp(): string
  return IN.T("Scroll up")
enddef

export def CopyWord(): string
  return IN.T("Copy the word")
enddef

export def ReplaceWordText(): string
  return IN.T("Replace the word in the text")
enddef

export def LookUpSel(): string
  return IN.T("Look up the selected suggestion")
enddef

export def ToggleAntonyms(): string
  return IN.T("Toggle antonyms")
enddef

export def DefineSelWord(): string
  return IN.T("Define the selected word")
enddef

export def Lookup(): string
  return IN.T("Lookup")
enddef

##############################################################################
# SECTION: tagger.vim
##############################################################################

export def TaggerCmdCould(cmd: any): string
  return printf(IN.T("the tagger command could not start: %s"), cmd)
enddef

export def PartSpeechTagger(detail: any): string
  return printf(IN.T("the part-of-speech tagger stopped: %s"), detail)
enddef

##############################################################################
# SECTION: lexicon_mw.vim
##############################################################################

export def EmptyRespMerriam(): string
  return IN.T("empty response from Merriam-Webster")
enddef

export def MerriamWebster(text: any): string
  return printf(IN.T("Merriam-Webster: %s"), text)
enddef

export def UnexpectedRespMerriam(): string
  return IN.T("unexpected response from Merriam-Webster")
enddef
