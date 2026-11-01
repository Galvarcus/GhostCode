vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# texcheck.vim: what a LaTeX template needs, and what TeX lacks of it, so
# that compile can name a missing package before LaTeX stops on it. A
# template names its class and packages in \documentclass, \LoadClass, and
# \usepackage lines. Those in a $if(name)$ block count only when name is
# true. A class loads packages of its own, some only under an option, so
# the template lists those that it needs in a comment:
#   % NEEDS: ulem.sty setspace.sty
# kpsewhich finds the files. Without it nothing is checked, and neither
# with MiKTeX, which installs a missing package while it compiles.
# License: GNU GPL 3.0
##############################################################################

const KPSEWHICH: string = 'kpsewhich'
# A program that only MiKTeX has.
const MIKTEX_TOOL: string = 'initexmf'
const IF_PAT: string = '^\s*\$if(\([^)]*\))\$\s*$'
const ELSE_PAT: string = '^\s*\$else\$\s*$'
const ENDIF_PAT: string = '^\s*\$endif\$\s*$'
const NEEDS_PAT: string = '^\s*%\s*NEEDS:\s*\(.*\)$'
# A class or package line: the command, its options, and a list of names.
const LOAD_PAT: string = '\\\(documentclass\|LoadClass\|usepackage\|RequirePackage\)\%(\[[^]]*\]\)\={\([^}]*\)}'
const CLASS_PAT: string = 'documentclass\|LoadClass'
# A comment: from a % that is not escaped to the end of the line.
const COMMENT_PAT: string = '\\\@<!%.*'
const EXT_CLS: string = '.cls'
const EXT_STY: string = '.sty'

# FUNCTION: Return the files that template needs, sorted: each class as
# name.cls and each package as name.sty, and the files of its NEEDS lines.
# A $if(name)$ block counts when name is true in vars, and its $else$ part
# when it is not. A name that is a template variable, such as $pkg$, is
# left out.
export def Needs(template: list<string>, vars: dict<bool>): list<string>
  var names: list<string> = []
  var on: list<bool> = []
  for line in template
    var cond: list<string> = matchlist(line, IF_PAT)
    if !empty(cond)
      on->add(get(vars, cond[1], false))
    elseif line =~# ELSE_PAT && !empty(on)
      on[-1] = !on[-1]
    elseif line =~# ENDIF_PAT && !empty(on)
      on->remove(-1)
    elseif index(on, false) < 0
      var needs: list<string> = matchlist(line, NEEDS_PAT)
      if !empty(needs)
        names += split(needs[1])
        continue
      endif
      substitute(substitute(line, COMMENT_PAT, '', ''), LOAD_PAT, (m: list<string>): string => {
        var ext: string = m[1] =~# CLASS_PAT ? EXT_CLS : EXT_STY
        for name in split(m[2], ',')->mapnew((_, n) => trim(n))
          if name !=# '' && name !~# '\$'
            names->add(name .. ext)
          endif
        endfor
        return m[0]
      }, 'g')
    endif
  endfor
  return sort(names)->uniq()
enddef

# FUNCTION: Return the files that template needs, see Needs, and that TeX
# cannot find, by one call of kpsewhich. Empty without kpsewhich, and with
# MiKTeX.
export def Missing(template: list<string>, vars: dict<bool>): list<string>
  if !executable(KPSEWHICH) || executable(MIKTEX_TOOL)
    return []
  endif
  var names: list<string> = Needs(template, vars)
  if empty(names)
    return []
  endif
  var found: list<string> = systemlist(join([KPSEWHICH] + names->mapnew((_, n) => shellescape(n))))
    ->mapnew((_, p) => fnamemodify(trim(p), ':t'))
  return names->copy()->filter((_, n) => index(found, n) < 0)
enddef
