vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif

var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Finds unreferenced code in Vim9 plugins: functions, methods,
# classes, fields, enum values, and script-level variables that
# nothing in the scanned project calls or reads.
# License: GNU GPL 3.0

# Currently detects:
#
#   - `def` and `export def`
#   - `class` and `export class`, including `extends` and `implements`
#   - `enum` and `export enum`, and enum values such as `Color.Red`
#   - `interface` and `export interface` declarations, though an
#     interface's abstract method signatures are not tracked as
#     callable symbols
#   - class methods, static methods, and fields
#   - script-level variables and class fields
#   - type annotations: `var x: Foo`, `def F(): Foo`, `list<Foo>`
#   - `Foo()`
#   - `Foo.Bar()`
#   - `this.Method()`, resolved against the enclosing class
#   - calls through a locally-typed variable or parameter, resolved
#     against its declared or constructor-inferred type, including a
#     two-level field-then-method chain such as `this.field.Method()`
#   - a method called directly on a constructor result, such as
#     `Foo.new(args).Bar()`
#   - bare funcref and value usage of a known symbol, such as
#     `var Ref = Foo`, `timer_start(1000, Foo)`, and `{callback: Foo}`
#   - `call({func}, ...)`, `function({name})`, and `execute({cmd})`,
#     where the target is a string literal or bare identifier
#   - every `import` form: `import './mod.vim' [as ns]`,
#     `import autoload '...' [as ns]`, and
#     `import {Foo [as Bar]} from '...'`
#   - exported symbols
#   - top-level code in scripts that Vim sources directly, such as
#     `plugin/`, `syntax/`, `ftplugin/`, and their `after/` copies, and
#     in `tests/`, all treated as entry points that need no call site
#
# Results are placed in the quickfix list.
#
# Deliberately not handled:
#
#   - local variables declared inside a def body, since Ghostcode
#     analyzes reachability between module-level symbols, not local
#     dead stores
#   - dynamic dispatch where the target name is built from string
#     concatenation, computed indices, or anything else that isn't a
#     literal identifier or string
#   - method calls on a variable with no declared or inferable type:
#     `obj.Method()` falls back to an unambiguous same-name match
#     across the codebase when obj's type can't be determined, same
#     as bare `Foo()` does
#
# Ghostcode is deliberately conservative around unresolved
# references. Anything it can't prove is dead is left alone.


import autoload 'ghostcode/log.vim' as L

var log = L.New(expand('<sfile>:t'))

# Runtime directories whose scripts Vim sources directly, plus tests/.
const ENTRY_DIRS: list<string> = [
  'plugin',
  'ftplugin',
  'ftdetect',
  'syntax',
  'indent',
  'compiler',
  'colors',
  'keymap',
  'lang',
  'tests',
]


# The classes precede the functions, against the usual order: Vim
# rejects a def signature that names a class defined later in the
# script with E1010.

# CLASS: Represents one declared function, method, class, enum,
# interface, field, variable, or enum value found during a scan.
class Symbol
  var id: string
  var name: string
  var kind: string
  var file: string
  var line: number
  var className: string
  var exported: bool

  def new(
    id: string,
    name: string,
    kind: string,
    file: string,
    line: number,
    className: string = '',
    exported: bool = false,
  )
    this.id = id
    this.name = name
    this.kind = kind
    this.file = file
    this.line = line
    this.className = className
    this.exported = exported
  enddef
endclass


# CLASS: Represents one textual reference to a name, found while
# scanning, not yet resolved to the symbol it targets.
class Reference
  var name: string
  var file: string
  var line: number
  var caller: string
  var className: string

  # Set only when the scanner already knows the exact target, such
  # as a locally-typed variable's method call resolved against its
  # declared type at scan time, when every declaration and import
  # is already known. Bypasses all heuristic matching below.
  var resolvedId: string

  def new(
    name: string,
    file: string,
    line: number,
    caller: string,
    className: string = '',
    resolvedId: string = '',
  )
    this.name = name
    this.file = file
    this.line = line
    this.caller = caller
    this.className = className
    this.resolvedId = resolvedId
  enddef
endclass


# CLASS: Holds every symbol, reference, root, and import discovered
# while scanning a project.
class Analysis
  var symbols: dict<Symbol> = {}
  var references: list<Reference> = []
  var roots: list<string> = []
  var unresolved: list<Reference> = []
  public var root: string = ''
  public var knownNames: dict<bool> = {}

  # file -> alias -> resolved file, for `import '...' [as alias]`
  var namespaceImports: dict<dict<string>> = {}

  # file -> alias -> resolved file / original name, for
  # `import {Foo [as alias]} from '...'`
  var namedImportFile: dict<dict<string>> = {}
  var namedImportOrig: dict<dict<string>> = {}

  # file -> list of resolved files it imports, regardless of
  # alias/named-import details. `import` sources the target file
  # unconditionally as a side effect, whether or not anything
  # imported from it is ever referenced by name, so this drives a
  # separate file-level reachability edge, defined in ScriptId.
  var fileImports: dict<list<string>> = {}

  def new()
  enddef

  def AddSymbol(symbol: Symbol)
    if !has_key(this.symbols, symbol.id)
      this.symbols[symbol.id] = symbol
    endif
  enddef

  def AddReference(reference: Reference)
    add(this.references, reference)
  enddef

  def AddRoot(id: string)
    if index(this.roots, id) < 0
      add(this.roots, id)
    endif
  enddef

  def AddNamespaceImport(
    file: string,
    alias: string,
    target: string,
  )
    if !has_key(this.namespaceImports, file)
      this.namespaceImports[file] = {}
    endif

    this.namespaceImports[file][alias] = target
  enddef

  def AddNamedImport(
    file: string,
    alias: string,
    target: string,
    orig: string,
  )
    if !has_key(this.namedImportFile, file)
      this.namedImportFile[file] = {}
      this.namedImportOrig[file] = {}
    endif

    this.namedImportFile[file][alias] = target
    this.namedImportOrig[file][alias] = orig
  enddef

  def AddFileImport(
    file: string,
    target: string,
  )
    if !has_key(this.fileImports, file)
      this.fileImports[file] = []
    endif

    if index(this.fileImports[file], target) < 0
      add(this.fileImports[file], target)
    endif
  enddef
endclass


# METHOD: Scan the project rooted at path and report every symbol
# nothing else in the project references.
export def Run(path: string = ''): void
  var root = path

  if root ==# ''
    root = getcwd()
  endif

  root = fnamemodify(root, ':p')

  if !isdirectory(root)
    log.Error($'not a directory: {root}')
    return
  endif

  var files = FindFiles(root)

  if empty(files)
    log.Warn($'no Vim files found under {root}')
    return
  endif

  var analysis = Analysis.new()
  analysis.root = root

  # Vim sources files in its runtime directories directly, without an
  # import or a call: plugin/ at startup, syntax/ and ftplugin/ on
  # FileType, and so on. Their top-level code is an entry point even
  # when it holds no resolvable call. tests/ gets the same treatment,
  # since a test harness runs from the command line or CI.
  for file in files
    if IsEntryScript(root, file)
      analysis.AddRoot(ScriptId(file))
    endif
  endfor

  # Pass 1:
  # Discover declarations.
  for file in files
    ScanDeclarations(file, analysis)
  endfor

  # Pass 2:
  # Discover imports. This needs the file list and feeds reference
  # resolution in pass 3.
  for file in files
    ScanImports(file, root, analysis)
  endfor

  analysis.knownNames = BuildKnownNames(analysis)

  # Pass 3:
  # Discover references.
  for file in files
    ScanReferences(file, analysis)
  endfor

  # Build reachability graph.
  var reachable = FindReachable(analysis)

  # Report.
  Report(analysis, reachable)
enddef


# METHOD: Return true when Vim or a test runner sources file directly.
def IsEntryScript(root: string, file: string): bool
  var parts = split(strpart(file, strlen(root)), '/')

  if !empty(parts) && parts[0] ==# 'after'
    remove(parts, 0)
  endif

  if len(parts) < 2
    return false
  endif

  return index(ENTRY_DIRS, parts[0]) >= 0
enddef


def FindFiles(root: string): list<string>
  var files = globpath(
    root,
    '**/*.vim',
    true,
    true,
  )

  var result: list<string> = []

  for file in files
    if filereadable(file)
      add(result, fnamemodify(file, ':p'))
    endif
  endfor

  return result
enddef


# METHOD: Record every class, enum, interface, function, method,
# field, and enum value declared in file.
def ScanDeclarations(
  file: string,
  analysis: Analysis,
): void

  var lines = readfile(file)
  var currentClass = ''
  var currentClassExported = false
  # One of '', 'class', 'enum', or 'interface'.
  var containerKind = ''
  var inDefBody = false

  for i in range(len(lines))
    var line = StripComment(lines[i])
    var lnum = i + 1

    # class / enum / interface
    var m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(class\|enum\|interface\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)',
    )

    if !empty(m)
      currentClass = m[3]
      containerKind = m[2]
      currentClassExported = !empty(m[1])
      inDefBody = false

      var id = SymbolId(
        file,
        currentClass,
        '',
      )

      var sym = Symbol.new(
        id,
        currentClass,
        containerKind,
        file,
        lnum,
        '',
        !empty(m[1]),
      )

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif

      continue
    endif

    # endclass / endenum / endinterface
    if line =~ '^\s*end\(class\|enum\|interface\)'
      currentClass = ''
      currentClassExported = false
      containerKind = ''
      inDefBody = false
      continue
    endif

    # def: a function, method, or interface signature.
    m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(static\s\+\)\?def\s\+\([A-Za-z_][A-Za-z0-9_]*\)\s*(',
    )

    if !empty(m)
      if containerKind ==# 'interface'
        # Abstract signature only: no body, no enddef, and no
        # standalone symbol worth tracking, since
        # implementations live on the implementing classes
        # instead.
        continue
      endif

      var name = m[3]

      # A method can't be marked `export` in Vim9: only the
      # class itself can. Vim9's actual visibility convention
      # is a leading underscore: `_Name` is private to the
      # class, everything else is public API. So a method of
      # an exported class is treated like a top-level `export
      # def`, unless its name marks it private, matching how
      # consumers of this class from outside the file would
      # actually be able to use it.
      var exported = currentClass ==# ''
        ? !empty(m[1])
        : currentClassExported && name !~# '^_'

      var kind = currentClass ==# ''
        ? 'function'
        : 'method'

      var id = SymbolId(
        file,
        name,
        currentClass,
      )

      var sym = Symbol.new(
        id,
        name,
        kind,
        file,
        lnum,
        currentClass,
        exported,
      )

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif

      inDefBody = true
      continue
    endif

    if line =~ '^\s*enddef'
      inDefBody = false
      continue
    endif

    # Everything below is module-level / class-level only. Local
    # declarations inside a function body are out of scope.
    if inDefBody
      continue
    endif

    # enum values:
    #
    #   Red, Green, Blue
    #   Red('r'), Green('g')
    if containerKind ==# 'enum'
      for item in split(line, ',')
        var em = matchlist(
          trim(item),
          '^\([A-Za-z_][A-Za-z0-9_]*\)',
        )

        if !empty(em)
          var vid = SymbolId(
            file,
            em[1],
            currentClass,
          )

          var vsym = Symbol.new(
            vid,
            em[1],
            'enum_value',
            file,
            lnum,
            currentClass,
            false,
          )

          analysis.AddSymbol(vsym)
        endif
      endfor

      continue
    endif

    # var / const / final:
    #
    #   module-level script variable, or a class field.
    m = matchlist(
      line,
      '^\s*\(export\s\+\)\?' ..
      '\%(public\s\+\|protected\s\+\|private\s\+\)\?' ..
      '\%(static\s\+\)\?' ..
      '\(var\|const\|final\)\s\+' ..
      '\([A-Za-z_][A-Za-z0-9_]*\)',
    )

    if !empty(m)
      var name = m[3]

      # Same reasoning as methods above: a field can't be
      # marked `export` individually, so fall back to the
      # leading-underscore convention when its class is
      # exported.
      var exported = currentClass ==# ''
        ? !empty(m[1])
        : currentClassExported && name !~# '^_'

      var kind = currentClass ==# ''
        ? 'variable'
        : 'field'

      var id = SymbolId(
        file,
        name,
        currentClass,
      )

      var sym = Symbol.new(
        id,
        name,
        kind,
        file,
        lnum,
        currentClass,
        exported,
      )

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif
    endif
  endfor
enddef


# METHOD: Record every import in file and the file it resolves to.
def ScanImports(
  file: string,
  root: string,
  analysis: Analysis,
): void

  var lines = readfile(file)

  for i in range(len(lines))
    var line = StripComment(lines[i])

    # Named import:
    #
    #   import {Foo, Bar as Baz} from './mod.vim'
    var m = matchlist(
      line,
      '^\s*import\s\+{\s*\(.\{-}\)\s*}\s\+from\s\+' ..
      '\(''[^'']\+''\|"[^"]\+"\)',
    )

    if !empty(m)
      var target = ResolveImportPath(
        file,
        root,
        Unquote(m[2]),
      )

      if target !=# ''
        analysis.AddFileImport(file, target)

        for item in split(m[1], ',')
          var piece = trim(item)
          var alias = piece
          var orig = piece

          var am = matchlist(
            piece,
            '^\(\S\+\)\s\+as\s\+\(\S\+\)$',
          )

          if !empty(am)
            orig = am[1]
            alias = am[2]
          endif

          analysis.AddNamedImport(
            file,
            alias,
            target,
            orig,
          )
        endfor
      endif

      continue
    endif

    # Namespace import:
    #
    #   import './mod.vim'
    #   import './mod.vim' as ns
    #   import autoload './mod.vim'
    #   import autoload './mod.vim' as ns
    m = matchlist(
      line,
      '^\s*import\s\+\(autoload\s\+\)\?' ..
      '\(''[^'']\+''\|"[^"]\+"\)' ..
      '\%(\s\+as\s\+\([A-Za-z_][A-Za-z0-9_]*\)\)\?',
    )

    if !empty(m)
      var spec = Unquote(m[2])
      var target = ResolveImportPath(
        file,
        root,
        spec,
        !empty(m[1]),
      )

      if target !=# ''
        analysis.AddFileImport(file, target)

        var alias = m[3] !=# ''
          ? m[3]
          : fnamemodify(spec, ':t:r')

        analysis.AddNamespaceImport(
          file,
          alias,
          target,
        )
      endif
    endif
  endfor
enddef


def Unquote(text: string): string
  return strpart(text, 1, strlen(text) - 2)
enddef


def ResolveImportPath(
  file: string,
  root: string,
  spec: string,
  isAutoload: bool = false,
): string

  # A relative path, starting with './' or '../', or an absolute
  # path resolves against the importing file's own directory,
  # regardless of the `autoload` keyword.
  #
  # Otherwise the two import forms mean different things:
  #
  #   import autoload 'foo.vim'  -> autoload/foo.vim
  #   import 'foo.vim'           -> import/foo.vim
  #
  # Real Vim searches every 'runtimepath' entry for this case.
  # Ghostcode only has one plugin root to search, which is the
  # common case.
  var candidate: string

  if spec =~# '^\.\{1,2}/' || spec[0] ==# '/'
    var fileDir = fnamemodify(file, ':h')
    candidate = simplify($'{fileDir}/{spec}')
  elseif isAutoload
    candidate = simplify($'{root}/autoload/{spec}')
  else
    candidate = simplify($'{root}/import/{spec}')
  endif

  if filereadable(candidate)
    return fnamemodify(candidate, ':p')
  endif

  return ''
enddef


# METHOD: Build the index of known symbol names used by pass 3 to
# recognize bare funcref, variable, and type usage without
# over-matching ordinary identifiers that mean nothing to Ghostcode.
def BuildKnownNames(analysis: Analysis): dict<bool>
  var result: dict<bool> = {}

  for id in keys(analysis.symbols)
    result[analysis.symbols[id].name] = true
  endfor

  return result
enddef


# METHOD: Record every reference to a declared symbol found in file.
def ScanReferences(
  file: string,
  analysis: Analysis,
): void

  var lines = readfile(file)
  var fieldTypesByClass = CollectFieldTypes(file, analysis)

  var currentClass = ''
  var containerKind = ''
  var currentFunction = ''
  var inDefBody = false
  var localTypes: dict<string> = {}

  for i in range(len(lines))
    var line = StripComment(lines[i])
    var lnum = i + 1

    # import: handled entirely by ScanImports; the module path
    # and any named-import list would otherwise be misread as
    # ordinary call/reference syntax.
    if line =~# '^\s*import\s'
      continue
    endif

    # class / enum / interface, plus `extends` / `implements`
    var m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(class\|enum\|interface\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)' ..
      '\%(\s\+extends\s\+\([A-Za-z_][A-Za-z0-9_]*\)\)\?' ..
      '\%(\s\+implements\s\+\(.\+\)\)\?',
    )

    if !empty(m)
      currentClass = m[3]
      containerKind = m[2]
      inDefBody = false

      if containerKind ==# 'class'
        var classId = SymbolId(file, currentClass, '')

        if m[4] !=# ''
          AddCall(m[4], file, lnum, classId, analysis)
        endif

        if m[5] !=# ''
          for iface in split(m[5], ',')
            AddCall(trim(iface), file, lnum, classId, analysis)
          endfor
        endif
      endif

      continue
    endif

    if line =~ '^\s*end\(class\|enum\|interface\)'
      currentClass = ''
      containerKind = ''
      inDefBody = false
      continue
    endif

    # def
    m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(static\s\+\)\?def\s\+\([A-Za-z_][A-Za-z0-9_]*\)\s*(',
    )

    if !empty(m)
      var sigId = SymbolId(
        file,
        m[3],
        currentClass,
      )

      # Parameter / return types can reference classes even
      # though this line declares rather than calls. Attribute
      # them to the function itself, so they're reachable
      # exactly when it is. This mirrors the class-field case
      # below.
      ScanTypeReferences(line, file, lnum, sigId, analysis)

      if containerKind ==# 'interface'
        continue
      endif

      currentFunction = sigId
      inDefBody = true

      # A typed parameter lets a later `param.Method()` in this
      # function's body resolve exactly, rather than falling
      # back to an unambiguous-name guess across the codebase.
      localTypes = ParseParamTypes(
        file,
        ExtractParamList(line),
        analysis,
      )

      continue
    endif

    if line =~ '^\s*enddef'
      currentFunction = ''
      inDefBody = false
      localTypes = {}
      continue
    endif

    if containerKind ==# 'enum'
      # Enum value lists don't contain calls.
      continue
    endif

    # var / const / final: strip the declared name itself, so it
    # isn't mistaken for a self-reference, but keep scanning the
    # type annotation and initializer for real references.
    var scanLine = line

    var vm = matchlist(
      line,
      '^\(\s*\%(export\s\+\)\?' ..
      '\%(public\s\+\|protected\s\+\|private\s\+\)\?' ..
      '\%(static\s\+\)\?' ..
      '\%(var\|const\|final\)\s\+[A-Za-z_][A-Za-z0-9_]*\)\(.*\)',
    )

    if !empty(vm)
      scanLine = vm[2]
    endif

    # A local `var name: Type = ...`, or a type inferred from
    # `var name = Type.new(...)`, extends what a later
    # `name.Method()` in this same function can resolve against.
    for [varName, varType] in items(LocalVarType(file, line, analysis))
      localTypes[varName] = varType
    endfor

    # A class-level field initializer that isn't inside a method
    # is attributed to the class itself, so its dependencies
    # become reachable exactly when the class does.
    var effectiveCaller = currentFunction

    if effectiveCaller ==# ''
        && containerKind ==# 'class'
        && currentClass !=# ''
      effectiveCaller = SymbolId(file, currentClass, '')
    endif

    var thisFieldTypes = get(fieldTypesByClass, currentClass, {})

    ScanDynamicCalls(scanLine, file, lnum, effectiveCaller, analysis)
    ScanCalls(scanLine, file, lnum, effectiveCaller, analysis, currentClass, localTypes, thisFieldTypes)
    ScanBareReferences(scanLine, file, lnum, effectiveCaller, currentClass, analysis, localTypes, thisFieldTypes)
    ScanTypeReferences(scanLine, file, lnum, effectiveCaller, analysis)
  endfor
enddef


# METHOD: Record calls of the form `Foo()`, `Foo.Bar()`, and
# `this.Bar()`.
def ScanCalls(
  code: string,
  file: string,
  line: number,
  caller: string,
  analysis: Analysis,
  className: string = '',
  localTypes: dict<string> = {},
  fieldTypes: dict<string> = {},
): void

  # Classic autoload calls:
  #
  #   tartree#Init()
  #   foo#bar#Func()
  #
  # These bypass `import` entirely: Vim's autoload mechanism maps
  # the '#'-joined prefix straight to a file under autoload/, and
  # this convention is still common even in vim9script mappings,
  # commands, and autocmds. Do this before the bare Foo() pattern
  # so the prefix is captured instead of only incidentally matching
  # the tail after the last '#'.
  var hashPattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\%(#[A-Za-z_][A-Za-z0-9_]*\)*\)#' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  var hstart = 0

  while true
    var htext = strpart(code, hstart)
    var hpos = match(htext, hashPattern)

    if hpos < 0
      break
    endif

    var hm = matchlist(
      strpart(htext, hpos),
      hashPattern,
    )

    if empty(hm)
      break
    endif

    AddCall(
      $'{hm[1]}#{hm[2]}',
      file,
      line,
      caller,
      analysis,
    )

    hstart += hpos + max([1, strlen(hm[0])])
  endwhile

  # A method called directly on a constructor result:
  #
  #   ScriveListPopup.new(entries).Open()
  #
  # The generic Foo.Bar() pattern below needs an identifier before
  # the dot, so it never sees `.Open(` after the closing paren.
  # Resolve the method against the constructed class instead.
  for chain in FindConstructorChains(code)
    var classId = ResolveTypeExpr(file, chain[0], analysis)

    if classId !=# ''
      AddCall(
        $'{chain[0]}.{chain[1]}',
        file,
        line,
        caller,
        analysis,
        className,
        $'{classId}.{chain[1]}',
      )
    endif
  endfor

  # A two-level field-then-method chain on `this`:
  #
  #   this.dim.AdjustWidth()
  #
  # The generic Foo.Bar() pattern below can only ever see the last
  # two dot-separated segments, so on this it would mis-anchor on
  # just `dim.AdjustWidth(`, losing the `this.` context and falling
  # back to an ambiguous whole-codebase guess. Resolve it here
  # against the enclosing class's own field types instead, before
  # that pattern gets a chance to run.
  var thisChainPattern =
    '\<this\.\([A-Za-z_][A-Za-z0-9_]*\)\.' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  var tstart = 0

  while true
    var ttext = strpart(code, tstart)
    var tpos = match(ttext, thisChainPattern)

    if tpos < 0
      break
    endif

    var tm = matchlist(
      strpart(ttext, tpos),
      thisChainPattern,
    )

    if empty(tm)
      break
    endif

    if has_key(fieldTypes, tm[1])
      AddCall(
        $'this.{tm[1]}.{tm[2]}',
        file,
        line,
        caller,
        analysis,
        className,
        $'{fieldTypes[tm[1]]}.{tm[2]}',
      )
    endif

    tstart += tpos + max([1, strlen(tm[0])])
  endwhile

  # Class/method calls:
  #
  #   Foo.Bar()
  #   this.Bar()
  #
  # Do these first so that Foo.Bar() doesn't also produce Bar().
  var pattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\)\.' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  var start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, pattern)

    if pos < 0
      break
    endif

    var m = matchlist(
      strpart(text, pos),
      pattern,
    )

    if empty(m)
      break
    endif

    AddCall(
      $'{m[1]}.{m[2]}',
      file,
      line,
      caller,
      analysis,
      className,
      has_key(localTypes, m[1]) ? $'{localTypes[m[1]]}.{m[2]}' : '',
    )

    # `instance.Method()` reads the receiver `instance` itself,
    # not just the method being called on it. Credit that too,
    # so a plain variable holding an object isn't flagged dead
    # just because it's only ever dereferenced, never read bare.
    # This skips `this`, since it isn't a declared symbol in its
    # own right.
    if m[1] !=# 'this' && has_key(analysis.knownNames, m[1])
      AddCall(m[1], file, line, caller, analysis, className)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile

  # Ordinary calls:
  #
  #   Foo()
  pattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  start = 0

  var ignored = [
    'if',
    'while',
    'for',
    'catch',
    'echo',
    'execute',
    'call',
    'function',
    'return',
    'range',
  ]

  while true
    var text = strpart(code, start)
    var pos = match(text, pattern)

    if pos < 0
      break
    endif

    var m = matchlist(
      strpart(text, pos),
      pattern,
    )

    if empty(m)
      break
    endif

    var name = m[1]

    if index(ignored, name) < 0
      AddCall(
        name,
        file,
        line,
        caller,
        analysis,
        className,
      )
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile
enddef


# METHOD: Record calls through `call()`, `function()`, and
# `execute()`.
def ScanDynamicCalls(
  code: string,
  file: string,
  line: number,
  caller: string,
  analysis: Analysis,
): void

  # call({func}, {arglist} [, {dict}])
  #
  # {func} may be a bare Funcref or a string name; either way the
  # identifier we want is the first token after the opening paren.
  # A legacy scope prefix such as s: or g: is skipped, since vim9
  # script-locals are referenced without one in native syntax.
  var m = matchlist(
    code,
    '\<call\s*(\s*[''"]\?\%([sgbwtla]:\)\?\([A-Za-z_][A-Za-z0-9_.#]*\)',
  )

  if !empty(m)
    AddCall(m[1], file, line, caller, analysis)
  endif

  # function({name} [, {arglist}] [, {dict}])
  #
  # Only the string-name form is unambiguous enough to trust.
  m = matchlist(
    code,
    '\<function\s*(\s*[''"]\%([sgbwtla]:\)\?\([A-Za-z_][A-Za-z0-9_.#]*\)[''"]',
  )

  if !empty(m)
    AddCall(m[1], file, line, caller, analysis)
  endif

  # execute({command} [, ...])
  #
  # execute() runs arbitrary Ex command text. We can't evaluate the
  # expression, but if the argument is or contains a string
  # literal, rescan that literal's text for ordinary call syntax,
  # e.g. execute('call Foo()').
  if code =~# '\<execute\s*('
    for str in ExtractQuotedStrings(code)
      ScanCalls(str, file, line, caller, analysis)
    endfor
  endif
enddef


# METHOD: Record funcrefs, variables, callback options, enum values,
# and any other reference used as a value rather than called.
def ScanBareReferences(
  code: string,
  file: string,
  line: number,
  caller: string,
  className: string,
  analysis: Analysis,
  localTypes: dict<string> = {},
  fieldTypes: dict<string> = {},
): void

  # A string literal that is, in its entirety, the name of a known
  # symbol. Covers funcref-by-string usage such as:
  #
  #   call('Foo', [])
  #   function('Foo')
  #   timer_start(1000, 'Foo')
  #   {callback: 'Foo'}
  #
  # Also covers the common legacy-interop guard idiom, where a
  # vim9 script-local is checked by name with an explicit scope
  # prefix since exists() takes a string:
  #
  #   if exists('s:is_loaded') | finish | endif
  #   var is_loaded: bool = true
  for str in ExtractQuotedStrings(code)
    var content = StripScopePrefix(trim(str))

    if content !=# '' && has_key(analysis.knownNames, content)
      AddCall(content, file, line, caller, analysis, className)
    elseif content =~# '^[A-Za-z_][A-Za-z0-9_]*\%(#[A-Za-z_][A-Za-z0-9_]*\)\+$'
      # A hash-qualified autoload name, e.g. 'tartree#Init'.
      # knownNames only indexes bare names, so this isn't
      # there. Let ResolveReference's path-based lookup judge
      # it instead.
      AddCall(content, file, line, caller, analysis, className)
    endif
  endfor

  # Dotted access without a call, e.g. enum values or a funcref
  # stored on an object/class:
  #
  #   Color.Red
  #   this.OnDone

  # A two-level field-then-field chain on `this`, the without-call
  # counterpart of ScanCalls' `this.dim.AdjustWidth()` case, e.g.
  # `this.dim.someField`. Handle it first for the same reason: the
  # generic pattern below can only see the last two segments.
  var thisChainPattern =
    '\<this\.\([A-Za-z_][A-Za-z0-9_]*\)\.\([A-Za-z_][A-Za-z0-9_]*\)\>' ..
    '\%(\s*(\)\@!'

  var tstart = 0

  while true
    var ttext = strpart(code, tstart)
    var tpos = match(ttext, thisChainPattern)

    if tpos < 0
      break
    endif

    var tm = matchlist(strpart(ttext, tpos), thisChainPattern)

    if empty(tm)
      break
    endif

    if has_key(fieldTypes, tm[1])
      AddCall(
        $'this.{tm[1]}.{tm[2]}',
        file,
        line,
        caller,
        analysis,
        className,
        $'{fieldTypes[tm[1]]}.{tm[2]}',
      )
    endif

    tstart += tpos + max([1, strlen(tm[0])])
  endwhile

  var dottedPattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\)\.\([A-Za-z_][A-Za-z0-9_]*\)\>' ..
    '\%(\s*(\)\@!'

  var start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, dottedPattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), dottedPattern)

    if empty(m)
      break
    endif

    AddCall(
      $'{m[1]}.{m[2]}',
      file,
      line,
      caller,
      analysis,
      className,
      has_key(localTypes, m[1]) ? $'{localTypes[m[1]]}.{m[2]}' : '',
    )

    # Same reasoning as the call-with-parens case: reading
    # `instance.Field` or `Color.Red` also reads the receiver.
    if m[1] !=# 'this' && has_key(analysis.knownNames, m[1])
      AddCall(m[1], file, line, caller, analysis, className)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile

  # Bare identifiers matching a known declared name, used as a
  # value rather than a call: function references, variable reads,
  # callback options passed without quotes.
  #
  #   var Ref = Foo
  #   timer_start(1000, Foo)
  #   {callback: Foo}
  var barePattern =
    '\%(\.\)\@<!\<\([A-Za-z_][A-Za-z0-9_]*\)\>\%(\s*[(.]\)\@!'

  start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, barePattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), barePattern)

    if empty(m)
      break
    endif

    var name = m[1]

    if has_key(analysis.knownNames, name)
      AddCall(name, file, line, caller, analysis, className)
    endif

    start += pos + max([1, strlen(name)])
  endwhile
enddef


# METHOD: Record type annotations such as `var x: Foo`, `def F():
# Foo`, and `list<Foo>`.
def ScanTypeReferences(
  code: string,
  file: string,
  line: number,
  caller: string,
  analysis: Analysis,
): void

  # Only known symbol names are ever accepted, so this cannot
  # generate false positives out of ordinary dict keys or ternary
  # colons that happen to precede some unrelated identifier.
  var pattern = '[:<]\s*\([A-Za-z_][A-Za-z0-9_]*\)'
  var start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, pattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), pattern)

    if empty(m)
      break
    endif

    var name = m[1]

    if has_key(analysis.knownNames, name)
      AddCall(name, file, line, caller, analysis)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile
enddef


def ExtractQuotedStrings(code: string): list<string>
  var sq = "'"
  var dq = '"'

  var pattern = $'{sq}\([^{sq}]*\){sq}\|{dq}\([^{dq}]*\){dq}'

  var result: list<string> = []
  var start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, pattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), pattern)

    if empty(m)
      break
    endif

    add(result, m[1] !=# '' ? m[1] : m[2])

    start += pos + max([1, strlen(m[0])])
  endwhile

  return result
enddef


# METHOD: Record one reference to name for later resolution.
def AddCall(
  name: string,
  file: string,
  line: number,
  caller: string,
  analysis: Analysis,
  className: string = '',
  resolvedId: string = '',
): void

  var reference = Reference.new(
    name,
    file,
    line,
    caller,
    className,
    resolvedId,
  )

  analysis.AddReference(reference)
enddef


# METHOD: Resolve a reference to the symbol it targets, or an empty
# string when nothing can be proven.
def ResolveReference(
  ref: Reference,
  analysis: Analysis,
): string

  # Pre-resolved at scan time, such as a locally-typed variable's
  # method call resolved against its declared type. Trust it
  # outright rather than re-deriving it heuristically.
  if ref.resolvedId !=# '' && has_key(analysis.symbols, ref.resolvedId)
    return ref.resolvedId
  endif

  # Same-file function:
  #
  #   Foo()
  var localId = $'{ref.file}::{ref.name}'

  if has_key(analysis.symbols, localId)
    return localId
  endif

  # Classic autoload reference:
  #
  #   tartree#Init()
  #   foo#bar#Func()
  #
  # The '#'-joined prefix maps directly to a path under autoload/:
  # tartree# -> autoload/tartree.vim, foo#bar# -> autoload/foo/bar.vim.
  var hash = strridx(ref.name, '#')

  if hash >= 0
    var prefix = strpart(ref.name, 0, hash)
    var funcName = strpart(ref.name, hash + 1)

    var autoloadPath = substitute(prefix, '#', '/', 'g')
    var candidate = simplify($'{analysis.root}/autoload/{autoloadPath}.vim')

    if filereadable(candidate)
      var fullPath = fnamemodify(candidate, ':p')
      var hashId = $'{fullPath}::{funcName}'

      if has_key(analysis.symbols, hashId)
        return hashId
      endif
    endif
  endif

  # Dotted reference:
  #
  #   Foo.Bar()
  #   this.Bar()
  var dot = stridx(ref.name, '.')

  if dot >= 0
    var receiver = strpart(ref.name, 0, dot)
    var member = strpart(ref.name, dot + 1)

    # `this` resolves against the enclosing class at the call
    # site, not against a class literally named "this".
    if receiver ==# 'this' && ref.className !=# ''
      var thisId = SymbolId(ref.file, member, ref.className)

      if has_key(analysis.symbols, thisId)
        return thisId
      endif
    endif

    # Receiver is a real class/enum/interface name in this file.
    var methodId = SymbolId(
      ref.file,
      member,
      receiver,
    )

    if has_key(analysis.symbols, methodId)
      return methodId
    endif

    # Receiver is an import namespace alias:
    #
    #   import autoload 'util.vim' as util
    #   util.Foo()
    if has_key(analysis.namespaceImports, ref.file)
      var aliases = analysis.namespaceImports[ref.file]

      if has_key(aliases, receiver)
        var targetFile = aliases[receiver]
        var qualifiedId = $'{targetFile}::{member}'

        if has_key(analysis.symbols, qualifiedId)
          return qualifiedId
        endif
      endif
    endif

    # Receiver is a variable of unknown declared type: fall back
    # to an unambiguous same-member-name match anywhere in the
    # codebase. This mirrors the bare-name global search below.
    var memberMatches: list<string> = []

    for id in keys(analysis.symbols)
      var sym = analysis.symbols[id]

      if sym.name ==# member
          && (sym.kind ==# 'method'
            || sym.kind ==# 'enum_value'
            || sym.kind ==# 'field')
        add(memberMatches, id)
      endif
    endfor

    if len(memberMatches) == 1
      return memberMatches[0]
    endif
  endif

  # Named import:
  #
  #   import {Foo} from './mod.vim'
  #   Foo()
  if has_key(analysis.namedImportFile, ref.file)
    var names = analysis.namedImportFile[ref.file]

    if has_key(names, ref.name)
      var targetFile = names[ref.name]
      var orig = analysis.namedImportOrig[ref.file][ref.name]
      var namedId = $'{targetFile}::{orig}'

      if has_key(analysis.symbols, namedId)
        return namedId
      endif
    endif
  endif

  # Global search.
  #
  # Only accept an unambiguous result.
  var matches: list<string> = []

  for id in keys(analysis.symbols)
    if analysis.symbols[id].name ==# ref.name
      add(matches, id)
    endif
  endfor

  if len(matches) == 1
    return matches[0]
  endif

  return ''
enddef


# METHOD: Build the caller-to-callee graph from every resolved
# reference, then return every symbol reachable from a root.
def FindReachable(
  analysis: Analysis,
): dict<bool>

  var edges: dict<list<string>> = {}

  for ref in analysis.references
    var target = ResolveReference(
      ref,
      analysis,
    )

    if target ==# ''
      add(
        analysis.unresolved,
        ref,
      )

      continue
    endif

    # A top-level reference has no calling function to attribute
    # it to, but it still always runs once the file itself is
    # loaded. That happens immediately for plugin/*.vim, sourced
    # unconditionally at startup as the root-seeding above
    # establishes, and lazily for everything else, the first
    # time anything in the file is reached. Both cases are
    # modeled uniformly with a per-file pseudo node: every symbol
    # in the file gets an edge to that node below, so reaching
    # any one of them also reaches its top-level code, and
    # `import` edges, also defined below, chain that reachability
    # across files.
    if ref.caller ==# ''
      var scriptId = ScriptId(ref.file)

      if !has_key(edges, scriptId)
        edges[scriptId] = []
      endif

      if index(edges[scriptId], target) < 0
        add(edges[scriptId], target)
      endif

      continue
    endif

    if !has_key(edges, ref.caller)
      edges[ref.caller] = []
    endif

    if index(
      edges[ref.caller],
      target,
    ) < 0
      add(
        edges[ref.caller],
        target,
      )
    endif
  endfor

  # Every symbol implicitly reaches its own file's top-level code,
  # since loading any one of them via Vim's autoload mechanism
  # sources the whole file.
  for id in keys(analysis.symbols)
    var scriptId = ScriptId(analysis.symbols[id].file)

    if !has_key(edges, id)
      edges[id] = []
    endif

    if index(edges[id], scriptId) < 0
      add(edges[id], scriptId)
    endif
  endfor

  # `import` sources the target file as a side effect, whether or
  # not anything it exports is ever referenced by name. Chain each
  # importer's top-level code to the imported file's.
  for file in keys(analysis.fileImports)
    var importerScript = ScriptId(file)

    if !has_key(edges, importerScript)
      edges[importerScript] = []
    endif

    for target in analysis.fileImports[file]
      var targetScript = ScriptId(target)

      if index(edges[importerScript], targetScript) < 0
        add(edges[importerScript], targetScript)
      endif
    endfor
  endfor

  # Traverse from roots.
  var reachable: dict<bool> = {}
  var queue = copy(analysis.roots)

  while !empty(queue)
    var id = remove(queue, 0)

    if has_key(reachable, id)
      continue
    endif

    reachable[id] = true

    for child in get(edges, id, [])
      if !has_key(reachable, child)
        add(queue, child)
      endif
    endfor
  endwhile

  return reachable
enddef


def CompareSymbols(
  a: Symbol,
  b: Symbol,
): number

  if a.file ==# b.file
    return a.line - b.line
  endif

  return a.file <# b.file
    ? -1
    : 1
enddef


# METHOD: Build the ghost list, populate the quickfix list, and
# print the summary line.
def Report(
  analysis: Analysis,
  reachable: dict<bool>,
): void

  var ghost: list<Symbol> = []

  for id in keys(analysis.symbols)
    var sym = analysis.symbols[id]

    if has_key(reachable, sym.id)
      continue
    endif

    # Exported symbols are public API. Don't classify them as
    # definitely ghost.
    if sym.exported
      continue
    endif

    add(ghost, sym)
  endfor

  sort(
    ghost,
    CompareSymbols,
  )

  var qf: list<dict<any>> = []

  for sym in ghost
    add(qf, {
      filename: sym.file,
      lnum: sym.line,
      col: 1,
      text: printf(
        '[ghost] %s %s',
        sym.kind,
        sym.name,
      ),
    })
  endfor

  setqflist(
    qf,
    'r',
  )

  log.Info($'{len(analysis.symbols)} symbols, {len(ghost)} ghost, {len(analysis.unresolved)} unresolved')

  if !empty(ghost)
    copen
  endif
enddef


def SymbolId(
  file: string,
  name: string,
  className: string,
): string

  if className ==# ''
    return $'{file}::{name}'
  endif

  return $'{file}::{className}.{name}'
enddef


def ScriptId(file: string): string
  # Pseudo node representing "this file's top-level code has run".
  # '<script>' can't collide with a real SymbolId, since '<' and
  # '>' never appear in a Vim9 identifier.
  return $'{file}::<script>'
enddef


# Local variable type tracking:
#
# A dotted call's receiver is usually a plain local variable, not a
# class name or `this`: `popup.Open()`, not `OutlinerPopup.Open()`.
# Without knowing popup's declared type, resolving `Open` means
# searching the whole codebase for a method named `Open` and hoping
# it's unique, which fails the moment two unrelated classes happen to
# share a common method name such as `Open`, `Close`, or `Render`.
# Tracking a variable's declared type at its `var` or parameter
# declaration lets such calls resolve exactly instead of falling
# back to that guess.
def ResolveTypeExpr(
  file: string,
  typeExpr: string,
  analysis: Analysis,
): string

  var expr = trim(typeExpr)

  # Unwrap one level of list<...>/dict<...>.
  var wrapped = matchlist(expr, '^\%(list\|dict\)<\(.*\)>$')

  if !empty(wrapped)
    expr = trim(wrapped[1])
  endif

  if expr ==# '' || expr !~# '^[A-Za-z_][A-Za-z0-9_.]*$'
    return ''
  endif

  var dot = stridx(expr, '.')

  if dot >= 0
    var alias = strpart(expr, 0, dot)
    var className = strpart(expr, dot + 1)

    if has_key(analysis.namespaceImports, file)
      var aliases = analysis.namespaceImports[file]

      if has_key(aliases, alias)
        var id = SymbolId(aliases[alias], className, '')

        if has_key(analysis.symbols, id)
          return id
        endif
      endif
    endif

    return ''
  endif

  var localId = SymbolId(file, expr, '')

  if has_key(analysis.symbols, localId)
    return localId
  endif

  # An unambiguous class anywhere else in the codebase, such as one
  # brought in by a named import.
  var matches: list<string> = []

  for id in keys(analysis.symbols)
    if analysis.symbols[id].name ==# expr
        && analysis.symbols[id].kind ==# 'class'
      add(matches, id)
    endif
  endfor

  if len(matches) == 1
    return matches[0]
  endif

  return ''
enddef


# METHOD: Return each [class, method] pair in code where a method is
# called directly on a constructor result, as in
# `Foo.new(args).Bar()`.
def FindConstructorChains(code: string): list<list<string>>
  var result: list<list<string>> = []
  var pattern = '\<\([A-Za-z_][A-Za-z0-9_.]*\)\.new\s*('
  var start = 0

  while true
    var pos = match(code, pattern, start)

    if pos < 0
      break
    endif

    var m = matchlist(code, pattern, start)
    var classExpr = m[1]
    var open = pos + strlen(m[0]) - 1
    var depth = 0
    var i = open
    var close = -1

    while i < strlen(code)
      if code[i] ==# '('
        depth += 1
      elseif code[i] ==# ')'
        depth -= 1

        if depth == 0
          close = i
          break
        endif
      endif

      i += 1
    endwhile

    if close < 0
      break
    endif

    var tail = matchlist(
      strpart(code, close + 1),
      '^\s*\.\([A-Za-z_][A-Za-z0-9_]*\)\s*(',
    )

    if !empty(tail)
      add(result, [classExpr, tail[1]])
    endif

    start = open + 1
  endwhile

  return result
enddef


def ExtractParamList(line: string): string
  var open = stridx(line, '(')

  if open < 0
    return ''
  endif

  var depth = 0
  var i = open

  while i < strlen(line)
    if line[i] ==# '('
      depth += 1
    elseif line[i] ==# ')'
      depth -= 1

      if depth == 0
        return strpart(line, open + 1, i - open - 1)
      endif
    endif

    i += 1
  endwhile

  return strpart(line, open + 1)
enddef


def SplitTopLevel(text: string): list<string>
  var result: list<string> = []
  var depth = 0
  var start = 0
  var i = 0

  while i < strlen(text)
    if text[i] =~# '[(<[]'
      depth += 1
    elseif text[i] =~# '[)>\]]'
      depth -= 1
    elseif text[i] ==# ',' && depth == 0
      add(result, strpart(text, start, i - start))
      start = i + 1
    endif

    i += 1
  endwhile

  add(result, strpart(text, start))

  return result
enddef


def ParseParamTypes(
  file: string,
  paramList: string,
  analysis: Analysis,
): dict<string>

  var result: dict<string> = {}

  for chunk in SplitTopLevel(paramList)
    var piece = trim(chunk)

    if piece ==# ''
      continue
    endif

    var m = matchlist(piece, '^\([A-Za-z_][A-Za-z0-9_]*\)\s*:\s*\(.*\)$')

    if empty(m)
      continue
    endif

    # A default value (`= expr`) may itself contain '=' or ':',
    # but only the part before the first top-level '=' is ever
    # the type.
    var typeExpr = m[2]
    var eq = stridx(typeExpr, '=')

    if eq >= 0
      typeExpr = strpart(typeExpr, 0, eq)
    endif

    var resolved = ResolveTypeExpr(file, typeExpr, analysis)

    if resolved !=# ''
      result[m[1]] = resolved
    endif
  endfor

  return result
enddef


def LocalVarType(
  file: string,
  line: string,
  analysis: Analysis,
): dict<string>

  var m = matchlist(
    line,
    '^\s*\%(var\|const\|final\)\s\+' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*:\s*\([^=]*\)',
  )

  if !empty(m)
    var result: dict<string> = {}
    var resolved = ResolveTypeExpr(file, m[2], analysis)

    if resolved !=# ''
      result[m[1]] = resolved
    endif

    return result
  endif

  # No explicit annotation: infer from a direct constructor call,
  # e.g. `var popup = OutlinerPopup.new(...)`.
  m = matchlist(
    line,
    '^\s*\%(var\|const\|final\)\s\+' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*=\s*' ..
    '\([A-Za-z_][A-Za-z0-9_.]*\)\.new\s*(',
  )

  if !empty(m)
    var result: dict<string> = {}
    var resolved = ResolveTypeExpr(file, m[2], analysis)

    if resolved !=# ''
      result[m[1]] = resolved
    endif

    return result
  endif

  return {}
enddef


def CollectFieldTypes(
  file: string,
  analysis: Analysis,
): dict<dict<string>>

  # A `this.field.Method()` chain needs the enclosing class's own
  # field types up front, independent of scan order within the
  # file. Fields are conventionally declared before the methods
  # that use them, but this doesn't rely on that.
  var result: dict<dict<string>> = {}
  var currentClass = ''
  var containerKind = ''
  var inDefBody = false

  for lineRaw in readfile(file)
    var line = StripComment(lineRaw)

    var m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(class\|enum\|interface\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)',
    )

    if !empty(m)
      currentClass = m[3]
      containerKind = m[2]
      inDefBody = false

      if !has_key(result, currentClass)
        result[currentClass] = {}
      endif

      continue
    endif

    if line =~ '^\s*end\(class\|enum\|interface\)'
      currentClass = ''
      containerKind = ''
      inDefBody = false
      continue
    endif

    if line =~# '^\s*\%(export\s\+\)\?\%(static\s\+\)\?def\s\+'
      inDefBody = true
      continue
    endif

    if line =~ '^\s*enddef'
      inDefBody = false
      continue
    endif

    if inDefBody || containerKind !=# 'class'
      continue
    endif

    var fm = matchlist(
      line,
      '^\s*\%(public\s\+\|protected\s\+\|private\s\+\)\?\%(static\s\+\)\?' ..
      '\%(var\|const\|final\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)\s*:\s*\([^=]*\)',
    )

    if !empty(fm)
      var resolved = ResolveTypeExpr(file, fm[2], analysis)

      if resolved !=# ''
        result[currentClass][fm[1]] = resolved
      endif
    endif
  endfor

  return result
enddef


def StripScopePrefix(name: string): string
  # A quoted string such as 'exists('s:is_loaded')' refers to a
  # script-local by its legacy s: name, even though vim9 native
  # syntax refers to the same symbol without the prefix. Strip it
  # so string-literal references resolve against knownNames.
  if name =~# '^[sgbwtla]:'
    return strpart(name, 2)
  endif

  return name
enddef


def StripComment(line: string): string
  # Deliberately simplistic.
  #
  # This should eventually be replaced by a tokenizer because '#'
  # can occur inside Vim9 strings.
  #
  # A Vim9 comment marker must be at the start of the line or
  # preceded by whitespace; '#' immediately after an identifier is
  # the classic autoload naming convention (tartree#Init()), not a
  # comment, and must be left alone.
  return substitute(
    line,
    '\%(\S\)\@<!\s*#.*$',
    '',
    '',
  )
enddef
