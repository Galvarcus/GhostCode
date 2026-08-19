vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

# Vim9 ghost-code (unreferenced code) analyzer. Opens results in a quickfix
# window.

#######################################################################
# Class: Symbol
#######################################################################
class Symbol
  var id: string
  var name: string
  var kind: string
  var file: string
  var line: number
  var class_name: string
  var exported: bool

  def new(id: string, name: string, kind: string, file: string, line: number, class_name: string = '', exported: bool = false)
      this.id = id
      this.name = name
      this.kind = kind
      this.file = file
      this.line = line
      this.class_name = class_name
      this.exported = exported
  enddef
endclass

#######################################################################
# Class: Reference
#######################################################################
class Reference
  var name: string
  var file: string
  var line: number
  var caller: string
  var class_name: string

  def new(name: string, file: string, line: number, caller: string, class_name: string = '')
      this.name = name
      this.file = file
      this.line = line
      this.caller = caller
      this.class_name = class_name
  enddef
endclass

#######################################################################
# Class: Analysis
#######################################################################
class Analysis
  var symbols: dict<Symbol> = {}
  var references: list<Reference> = []
  var roots: list<string> = []
  var unresolved: list<Reference> = []
  public var root: string = ''
  public var known_names: dict<bool> = {}

  var namespace_imports: dict<dict<string>> = {}

  var named_import_file: dict<dict<string>> = {}
  var named_import_orig: dict<dict<string>> = {}

  var file_imports: dict<list<string>> = {}

  def new()
  enddef

  def AddSymbol(symbol: Symbol)
    if !has_key(this.symbols, symbol.id)
      this.symbols[symbol.id] = symbol
    endif
  enddef

  def AddReference(reference: Reference): void
    add(this.references, reference)
  enddef

  def AddRoot(id: string): void
    if index(this.roots, id) < 0
      add(this.roots, id)
    endif
  enddef

  def AddNamespaceImport(file: string, alias: string, target: string): void
      if !has_key(this.namespace_imports, file)
        this.namespace_imports[file] = {}
      endif

      this.namespace_imports[file][alias] = target
  enddef

  def AddNamedImport(file: string, alias: string, target: string, orig: string ): void
      if !has_key(this.named_import_file, file)
        this.named_import_file[file] = {}
        this.named_import_orig[file] = {}
      endif

      this.named_import_file[file][alias] = target
      this.named_import_orig[file][alias] = orig
  enddef

  def AddFileImport(file: string, target: string): void
      if !has_key(this.file_imports, file)
        this.file_imports[file] = []
      endif

      if index(this.file_imports[file], target) < 0
        add(this.file_imports[file], target)
      endif
  enddef
endclass

#######################################################################
# Entry Points:
#######################################################################

export def Run(path: string = ''): void
  var root: string = path

  if root ==# ''
    root = getcwd()
  endif

  root = fnamemodify(root, ':p')

  if !isdirectory(root)
    echoerr 'GhostCode: not a directory: ' .. root
    return
  endif

  var files: list<string> = FindFiles(root)

  if empty(files)
    echomsg 'GhostCode: no Vim files found under ' .. root
    return
  endif

  var analysis: Analysis = Analysis.new()
  analysis.root = root


  for file in files
    if file =~# '/plugin/'
      analysis.AddRoot(ScriptId(file))
    endif
  endfor

  ################################################################
  # Pass 1:
  # Discover declarations.
  ################################################################

  for file in files
    ScanDeclarations(file, analysis)
  endfor

  ################################################################
  # Pass 2:
  # Discover imports (needs the file list; feeds reference
  # resolution in pass 3).
  ################################################################

  for file in files
    ScanImports(file, root, analysis)
  endfor

  analysis.known_names = BuildKnownNames(analysis)

  ################################################################
  # Pass 3:
  # Discover references.
  ################################################################

  for file in files
    ScanReferences(file, analysis)
  endfor

  ################################################################
  # Build reachability graph.
  ################################################################

  var reachable: dict<bool> = FindReachable(analysis)

  ################################################################
  # Report.
  ################################################################

  Report(analysis, reachable)
enddef

#######################################################################
# Method: FindFiles
#######################################################################
def FindFiles(root: string): list<string>
  var files: list<string> = globpath(root, '**/*.vim', true, true)

  var result: list<string> = []

  for file in files
    if filereadable(file)
      add(result, fnamemodify(file, ':p'))
    endif
  endfor

  return result
enddef

#######################################################################
# Method: ScanDeclarations
#######################################################################
def ScanDeclarations(file: string, analysis: Analysis): void

  var lines: list<string> = readfile(file)
  var current_class: string = ''
  var container_kind: string = ''   # '', 'class', 'enum', 'interface'
  var in_def_body: bool = false

  for i in range(len(lines))
    var line: string = StripComment(lines[i])
    var lnum: number = i + 1

    var m: list<string> = matchlist(line, '^\s*\(export\s\+\)\?\(class\|enum\|interface\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)')

    if !empty(m)
      current_class = m[3]
      container_kind = m[2]
      in_def_body = false

      var id: string = SymbolId(file, current_class, '')

      var sym: Symbol = Symbol.new(id, current_class, container_kind, file, lnum, '', !empty(m[1]))

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif

      continue
    endif

    if line =~ '^\s*end\(class\|enum\|interface\)'
      current_class = ''
      container_kind = ''
      in_def_body = false
      continue
    endif

    m = matchlist(line, '^\s*\(export\s\+\)\?\(static\s\+\)\?def\s\+\([A-Za-z_][A-Za-z0-9_]*\)\s*(')

    if !empty(m)
      if container_kind ==# 'interface'
        continue
      endif

      var name: string = m[3]
      var exported: bool = !empty(m[1])

      var kind: string = current_class ==# '' ? 'function' : 'method'

      var id: string = SymbolId(file, name, current_class)

      var sym: Symbol = Symbol.new(id, name, kind, file, lnum, current_class, exported)

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif

      in_def_body = true
      continue
    endif

    if line =~ '^\s*enddef'
      in_def_body = false
      continue
    endif

    if in_def_body
      continue
    endif

    if container_kind ==# 'enum'
      for item in split(line, ',')
        var em: list<string> = matchlist(trim(item), '^\([A-Za-z_][A-Za-z0-9_]*\)')

        if !empty(em)
          var vid: string = SymbolId(file, em[1], current_class)

          var vsym: Symbol = Symbol.new(vid, em[1], 'enum_value', file, lnum, current_class, false)

          analysis.AddSymbol(vsym)
        endif
      endfor

      continue
    endif

    m = matchlist(
      line,
      '^\s*\(export\s\+\)\?' ..
      '\%(public\s\+\|protected\s\+\|private\s\+\)\?' ..
      '\%(static\s\+\)\?' ..
      '\(var\|const\|final\)\s\+' ..
      '\([A-Za-z_][A-Za-z0-9_]*\)',
    )

    if !empty(m)
      var name: string = m[3]
      var exported: bool = !empty(m[1])

      var kind: string = current_class ==# '' ? 'variable' : 'field'

      var id: string = SymbolId(file, name, current_class)

      var sym: Symbol = Symbol.new(id, name, kind, file, lnum, current_class, exported)

      analysis.AddSymbol(sym)

      if sym.exported
        analysis.AddRoot(id)
      endif
    endif
  endfor
enddef

#######################################################################
# Method: ScanImports
#######################################################################
def ScanImports(file: string, root: string, analysis: Analysis): void

  var lines = readfile(file)

  for i in range(len(lines))
    var line = StripComment(lines[i])

    var m = matchlist(line, '^\s*import\s\+{\s*\(.\{-}\)\s*}\s\+from\s\+' ..  '\(''[^'']\+''\|"[^"]\+"\)')

    if !empty(m)
      var target = ResolveImportPath(file, root, Unquote(m[2]))

      if target !=# ''
        analysis.AddFileImport(file, target)

        for item in split(m[1], ',')
          var piece = trim(item)
          var alias = piece
          var orig = piece

          var am = matchlist(piece, '^\(\S\+\)\s\+as\s\+\(\S\+\)$')

          if !empty(am)
            orig = am[1]
            alias = am[2]
          endif

          analysis.AddNamedImport(file, alias, target, orig)
        endfor
      endif

      continue
    endif

    m = matchlist(line, '^\s*import\s\+\(autoload\s\+\)\?' ..  '\(''[^'']\+''\|"[^"]\+"\)' ..  '\%(\s\+as\s\+\([A-Za-z_][A-Za-z0-9_]*\)\)\?')

    if !empty(m)
      var spec = Unquote(m[2])
      var target = ResolveImportPath(file, root, spec, !empty(m[1]))

      if target !=# ''
        analysis.AddFileImport(file, target)

        var alias = m[3] !=# ''
          ? m[3]
          : fnamemodify(spec, ':t:r')

        analysis.AddNamespaceImport(file, alias, target)
      endif
    endif
  endfor
enddef

def Unquote(text: string): string
  return strpart(text, 1, strlen(text) - 2)
enddef

def ResolveImportPath(file: string, root: string, spec: string, is_autoload: bool = false): string

  var candidate: string

  if spec =~# '^\.\{1,2}/' || spec[0] ==# '/'
    candidate = simplify(fnamemodify(file, ':h') .. '/' .. spec)
  elseif is_autoload
    candidate = simplify(root .. '/autoload/' .. spec)
  else
    candidate = simplify(root .. '/import/' .. spec)
  endif

  if filereadable(candidate)
    return fnamemodify(candidate, ':p')
  endif

  return ''
enddef


#######################################################################
# Method: BuildKnownNames
#######################################################################
def BuildKnownNames(analysis: Analysis): dict<bool>
  var result: dict<bool> = {}

  for id in keys(analysis.symbols)
    result[analysis.symbols[id].name] = true
  endfor

  return result
enddef

#######################################################################
# Method: ScanReferences
#######################################################################
def ScanReferences(file: string, analysis: Analysis): void

  var lines = readfile(file)

  var current_class = ''
  var container_kind = ''
  var current_function = ''
  var in_def_body = false

  for i in range(len(lines))
    var line = StripComment(lines[i])
    var lnum = i + 1

    if line =~# '^\s*import\s'
      continue
    endif

    var m = matchlist(
      line,
      '^\s*\(export\s\+\)\?\(class\|enum\|interface\)\s\+\([A-Za-z_][A-Za-z0-9_]*\)' ..
      '\%(\s\+extends\s\+\([A-Za-z_][A-Za-z0-9_]*\)\)\?' ..
      '\%(\s\+implements\s\+\(.\+\)\)\?',
    )

    if !empty(m)
      current_class = m[3]
      container_kind = m[2]
      in_def_body = false

      if container_kind ==# 'class'
        var class_id = SymbolId(file, current_class, '')

        if m[4] !=# ''
          AddCall(m[4], file, lnum, class_id, analysis)
        endif

        if m[5] !=# ''
          for iface in split(m[5], ',')
            AddCall(trim(iface), file, lnum, class_id, analysis)
          endfor
        endif
      endif

      continue
    endif

    if line =~ '^\s*end\(class\|enum\|interface\)'
      current_class = ''
      container_kind = ''
      in_def_body = false
      continue
    endif

    m = matchlist(line, '^\s*\(export\s\+\)\?\(static\s\+\)\?def\s\+\([A-Za-z_][A-Za-z0-9_]*\)\s*(')

    if !empty(m)
      var sig_id = SymbolId(file, m[3], current_class)

      ScanTypeReferences(line, file, lnum, sig_id, analysis)

      if container_kind ==# 'interface'
        continue
      endif

      current_function = sig_id
      in_def_body = true
      continue
    endif

    if line =~ '^\s*enddef'
      current_function = ''
      in_def_body = false
      continue
    endif

    if container_kind ==# 'enum'
      continue
    endif

    var scan_line = line

    var vm = matchlist(
      line,
      '^\(\s*\%(export\s\+\)\?' ..
      '\%(public\s\+\|protected\s\+\|private\s\+\)\?' ..
      '\%(static\s\+\)\?' ..
      '\%(var\|const\|final\)\s\+[A-Za-z_][A-Za-z0-9_]*\)\(.*\)',
    )

    if !empty(vm)
      scan_line = vm[2]
    endif

    var effective_caller = current_function

    if effective_caller ==# ''
        && container_kind ==# 'class'
        && current_class !=# ''
      effective_caller = SymbolId(file, current_class, '')
    endif

    ScanDynamicCalls(scan_line, file, lnum, effective_caller, analysis)
    ScanCalls(scan_line, file, lnum, effective_caller, analysis, current_class)
    ScanBareReferences(scan_line, file, lnum, effective_caller, current_class, analysis)
    ScanTypeReferences(scan_line, file, lnum, effective_caller, analysis)
  endfor
enddef


#######################################################################
# Method: ScanCalls
#######################################################################
def ScanCalls(code: string, file: string, line: number, caller: string, analysis: Analysis, class_name: string = ''): void

  var hash_pattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\%(#[A-Za-z_][A-Za-z0-9_]*\)*\)#' ..
    '\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  var hstart = 0

  while true
    var htext = strpart(code, hstart)
    var hpos = match(htext, hash_pattern)

    if hpos < 0
      break
    endif

    var hm = matchlist(strpart(htext, hpos), hash_pattern)

    if empty(hm)
      break
    endif

    AddCall(hm[1] .. '#' .. hm[2], file, line, caller, analysis)

    hstart += hpos + max([1, strlen(hm[0])])
  endwhile

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

    var m = matchlist(strpart(text, pos), pattern)

    if empty(m)
      break
    endif

    AddCall(m[1] .. '.' .. m[2], file, line, caller, analysis, class_name)

    if m[1] !=# 'this' && has_key(analysis.known_names, m[1])
      AddCall(m[1], file, line, caller, analysis, class_name)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile

  pattern = '\<\([A-Za-z_][A-Za-z0-9_]*\)\s*('

  start = 0

  var ignored = ['if', 'while', 'for', 'catch', 'echo', 'execute', 'call', 'function', 'return', 'range']

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

    if index(ignored, name) < 0
      AddCall(name, file, line, caller, analysis, class_name)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile
enddef


#######################################################################
# Method: ScanDynamicCalls - call(), function(), execute()
#######################################################################
def ScanDynamicCalls(code: string, file: string, line: number, caller: string, analysis: Analysis): void

  var m = matchlist(code, '\<call\s*(\s*[''"]\?\%([sgbwtla]:\)\?\([A-Za-z_][A-Za-z0-9_.#]*\)')

  if !empty(m)
    AddCall(m[1], file, line, caller, analysis)
  endif

  m = matchlist(code, '\<function\s*(\s*[''"]\%([sgbwtla]:\)\?\([A-Za-z_][A-Za-z0-9_.#]*\)[''"]')

  if !empty(m)
    AddCall(m[1], file, line, caller, analysis)
  endif

  if code =~# '\<execute\s*('
    for str in ExtractQuotedStrings(code)
      ScanCalls(str, file, line, caller, analysis)
    endfor
  endif
enddef


#######################################################################
# Method: ScanBareReferences - funcrefs, variables, callback options, enum
#######################################################################
def ScanBareReferences(code: string, file: string, line: number, caller: string, class_name: string, analysis: Analysis): void

  for str in ExtractQuotedStrings(code)
    var content = StripScopePrefix(trim(str))

    if content !=# '' && has_key(analysis.known_names, content)
      AddCall(content, file, line, caller, analysis, class_name)
    elseif content =~# '^[A-Za-z_][A-Za-z0-9_]*\%(#[A-Za-z_][A-Za-z0-9_]*\)\+$'
      AddCall(content, file, line, caller, analysis, class_name)
    endif
  endfor

  var dotted_pattern =
    '\<\([A-Za-z_][A-Za-z0-9_]*\)\.\([A-Za-z_][A-Za-z0-9_]*\)\>' ..
    '\%(\s*(\)\@!'

  var start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, dotted_pattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), dotted_pattern)

    if empty(m)
      break
    endif

    AddCall(m[1] .. '.' .. m[2], file, line, caller, analysis, class_name)

    if m[1] !=# 'this' && has_key(analysis.known_names, m[1])
      AddCall(m[1], file, line, caller, analysis, class_name)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile

  var bare_pattern = '\%(\.\)\@<!\<\([A-Za-z_][A-Za-z0-9_]*\)\>\%(\s*[(.]\)\@!'

  start = 0

  while true
    var text = strpart(code, start)
    var pos = match(text, bare_pattern)

    if pos < 0
      break
    endif

    var m = matchlist(strpart(text, pos), bare_pattern)

    if empty(m)
      break
    endif

    var name = m[1]

    if has_key(analysis.known_names, name)
      AddCall(name, file, line, caller, analysis, class_name)
    endif

    start += pos + max([1, strlen(name)])
  endwhile
enddef

#######################################################################
# Method: ScanTypeReferences
#######################################################################
def ScanTypeReferences(code: string, file: string, line: number, caller: string, analysis: Analysis): void

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

    if has_key(analysis.known_names, name)
      AddCall(name, file, line, caller, analysis)
    endif

    start += pos + max([1, strlen(m[0])])
  endwhile
enddef

#######################################################################
# Method: ExtractQuotedStrings
#######################################################################
def ExtractQuotedStrings(code: string): list<string>
  var sq = "'"
  var dq = '"'

  var pattern = sq .. '\([^' .. sq .. ']*\)' .. sq ..
    '\|' ..
    dq .. '\([^' .. dq .. ']*\)' .. dq

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


def AddCall(name: string, file: string, line: number, caller: string, analysis: Analysis, class_name: string = ''): void

  var reference = Reference.new(name, file, line, caller, class_name)

  analysis.AddReference(reference)
enddef

#######################################################################
# Method: ResolveReference
#######################################################################
def ResolveReference(ref: Reference, analysis: Analysis): string

  var local_id = ref.file .. '::' .. ref.name

  if has_key(analysis.symbols, local_id)
    return local_id
  endif

  var hash = strridx(ref.name, '#')

  if hash >= 0
    var prefix = strpart(ref.name, 0, hash)
    var func_name = strpart(ref.name, hash + 1)

    var candidate = simplify(analysis.root .. '/autoload/' ..  substitute(prefix, '#', '/', 'g') .. '.vim')

    if filereadable(candidate)
      var hash_id = fnamemodify(candidate, ':p') .. '::' .. func_name

      if has_key(analysis.symbols, hash_id)
        return hash_id
      endif
    endif
  endif

  var dot = stridx(ref.name, '.')

  if dot >= 0
    var receiver = strpart(ref.name, 0, dot)
    var member = strpart(ref.name, dot + 1)

    if receiver ==# 'this' && ref.class_name !=# ''
      var this_id = SymbolId(ref.file, member, ref.class_name)

      if has_key(analysis.symbols, this_id)
        return this_id
      endif
    endif

    var method_id = SymbolId(ref.file, member, receiver)

    if has_key(analysis.symbols, method_id)
      return method_id
    endif

    if has_key(analysis.namespace_imports, ref.file)
      var aliases = analysis.namespace_imports[ref.file]

      if has_key(aliases, receiver)
        var target_file = aliases[receiver]
        var qualified_id = target_file .. '::' .. member

        if has_key(analysis.symbols, qualified_id)
          return qualified_id
        endif
      endif
    endif

    var member_matches: list<string> = []

    for id in keys(analysis.symbols)
      var sym = analysis.symbols[id]

      if sym.name ==# member
          && (sym.kind ==# 'method'
          || sym.kind ==# 'enum_value'
          || sym.kind ==# 'field')
        add(member_matches, id)
      endif
    endfor

    if len(member_matches) == 1
      return member_matches[0]
    endif
  endif

  if has_key(analysis.named_import_file, ref.file)
    var names = analysis.named_import_file[ref.file]

    if has_key(names, ref.name)
      var target_file = names[ref.name]
      var orig = analysis.named_import_orig[ref.file][ref.name]
      var named_id = target_file .. '::' .. orig

      if has_key(analysis.symbols, named_id)
        return named_id
      endif
    endif
  endif

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

#######################################################################
# Method: FindReachable
#######################################################################
def FindReachable(analysis: Analysis): dict<bool>

  # Graph: caller -> callees
  var edges: dict<list<string>> = {}

  for ref in analysis.references
    var target = ResolveReference(ref, analysis)

    if target ==# ''
      add(analysis.unresolved, ref)

      continue
    endif

    if ref.caller ==# ''
      var script_id = ScriptId(ref.file)

      if !has_key(edges, script_id)
        edges[script_id] = []
      endif

      if index(edges[script_id], target) < 0
        add(edges[script_id], target)
      endif

      continue
    endif

    if !has_key(edges, ref.caller)
      edges[ref.caller] = []
    endif

    if index(edges[ref.caller], target) < 0
      add(edges[ref.caller], target)
    endif
  endfor

  for id in keys(analysis.symbols)
    var script_id = ScriptId(analysis.symbols[id].file)

    if !has_key(edges, id)
      edges[id] = []
    endif

    if index(edges[id], script_id) < 0
      add(edges[id], script_id)
    endif
  endfor

  for file in keys(analysis.file_imports)
    var importer_script = ScriptId(file)

    if !has_key(edges, importer_script)
      edges[importer_script] = []
    endif

    for target in analysis.file_imports[file]
      var target_script = ScriptId(target)

      if index(edges[importer_script], target_script) < 0
        add(edges[importer_script], target_script)
      endif
    endfor
  endfor

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

#######################################################################
# Method: CompareSymbols
#######################################################################
def CompareSymbols(a: Symbol, b: Symbol): number

  if a.file ==# b.file
    return a.line - b.line
  endif

  return a.file <# b.file
    ? -1
    : 1
enddef

#######################################################################
# Method: Report
#######################################################################
def Report(analysis: Analysis, reachable: dict<bool>): void

  var ghost: list<Symbol> = []

  for id in keys(analysis.symbols)
    var sym = analysis.symbols[id]

    if has_key(reachable, sym.id)
      continue
    endif

    if sym.exported
      continue
    endif

    add(ghost, sym)
  endfor

  sort(ghost, CompareSymbols)

  var qf: list<dict<any>> = []

  for sym in ghost
    add(qf, {filename: sym.file, lnum: sym.line, col: 1, text: printf('[ghost] %s %s', sym.kind, sym.name)})
  endfor

  setqflist(qf, 'r')

  echomsg printf(
    'GhostCode: %d symbols, %d ghost, %d unresolved',
    len(keys(analysis.symbols)),
    len(ghost),
    len(analysis.unresolved),
  )

  if !empty(ghost)
    copen
  endif
enddef

#######################################################################
# Method: SymbolId
#######################################################################
def SymbolId(file: string, name: string, class_name: string): string

  if class_name ==# ''
    return file .. '::' .. name
  endif

  return file .. '::' ..
    class_name .. '.' .. name
enddef


def ScriptId(file: string): string
  return file .. '::<script>'
enddef

#######################################################################
# Utilities:
#######################################################################


#######################################################################
# Method: StripScopePrefix
#######################################################################
def StripScopePrefix(name: string): string
  if name =~# '^[sgbwtla]:'
    return strpart(name, 2)
  endif

  return name
enddef

#######################################################################
# Method: StripComment
#######################################################################
def StripComment(line: string): string
  return substitute(line, '\%(\S\)\@<!\s*#.*$', '', '')
enddef
