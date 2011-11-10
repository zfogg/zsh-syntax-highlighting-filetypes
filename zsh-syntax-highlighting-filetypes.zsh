#!/bin/zsh
# Name:   zsh-syntax-highlighting-filetypes
# Author: Magnus Woldrich <m@japh.se>
# Update: 2011-06-20 23:26:38
#
# This is based on nicoulaj's zsh-syntax-highlighting project [0]. I've
# taken the initial version of his script and added highlighting for
# filetypes and a few other things. The filetype highlighting rules are
# taken from my LS_COLORS [1] project.
#
# This will only work in terminals capable of displaying 256 colors.
#
# [0]: https://github.com/nicoulaj/zsh-syntax-highlighting
# [1]: https://github.com/trapd00r/LS_COLORS


# Core highlighting update system

# Array used by highlighters to declare overridable styles.
typeset -gA ZSH_HIGHLIGHT_STYLES

# An `object' implemented by below 3 arrays' elements could be called a
# `highlighter', registered by `_zsh_highlight_add-highlighter`. In
# other words, these arrays are indexed and tied by their own
# functionality. If they have been arranged inconsistently, things goes
# wrong. Please see `_zsh_highlight-zle-buffer` and `_zsh_highlight_add-
# highlighter`.


# Actual recolorize functions to be called.
typeset -a zsh_highlight_functions; zsh_highlight_functions=()

# Predicate functions whether its recolorize function should be called or not.
typeset -a zsh_highlight_predicates; zsh_highlight_predicates=()

# Highlight storages for each recolorize functions.
typeset -a zsh_highlight_caches; zsh_highlight_caches=()

_zsh_highlight-zle-buffer() {
  if (( PENDING )); then
    return
  fi

  local ret=$?
  {
    local -a funinds
    local -i rh_size=$#region_highlight
    for i in {1..${#zsh_highlight_functions}}; do
      local pred=${zsh_highlight_predicates[i]}
      local cache_place=${zsh_highlight_caches[i]}
      if _zsh_highlight-zle-buffer-p "$rh_size" "$pred"; then
        if ((${#${(P)cache_place}} > 0)); then
          region_highlight=(${region_highlight:#(${(P~j.|.)cache_place})})
          local -a empty; empty=(); : ${(PA)cache_place::=$empty}
        fi
        funinds+=$i
      fi
    done
    for i in $funinds; do
      local func=${zsh_highlight_functions[i]}
      local cache_place=${zsh_highlight_caches[i]}
      local -a rh; rh=($region_highlight)
      {
        "$func"
      } always  {
        : ${(PA)cache_place::=${region_highlight:#(${(~j.|.)rh})}}
      }
    done
  } always {
    ZSH_PRIOR_CURSOR=$CURSOR
    ZSH_PRIOR_HIGHLIGHTED_BUFFER=$BUFFER
    return $ret
  }
}

# Whether supplied highlight_predicate satisfies or not.
_zsh_highlight-zle-buffer-p() {
  local region_highlight_size="$1" highlight_predicate="$2"
  # If any highlightings are not taken into account, asume it is needed.
  # This holds for some up/down-history commands, for example.
  ((region_highlight_size == 0)) || "$highlight_predicate"
}

# Whether the command line buffer is modified or not.
_zsh_highlight_buffer-modified-p() {
  [[ ${ZSH_PRIOR_HIGHLIGHTED_BUFFER:-} != $BUFFER ]]
}

# Whether the cursor is moved or not.
_zsh_highlight_cursor-moved-p() {
  ((ZSH_PRIOR_CURSOR != $CURSOR))
}

# Register an highlighter.
_zsh_highlight_add-highlighter() {
  zsh_highlight_functions+="$1"
  zsh_highlight_predicates+="${2-${1}-p}"
  zsh_highlight_caches+="${3-${1//-/_}}"
}


# Main highlighter

ZSH_HIGHLIGHT_STYLES+=(
  default                       'fg=248'
  unknown-token                 'fg=196,bold,bg=234'
  reserved-word                 'fg=197,bold'
  alias                         'fg=197,bold'
  builtin                       'fg=107,bold'
  function                      'fg=85,bold'
  command                       'fg=166,bold'
  hashed-command                'fg=70'
  path                          'fg=30'
  globbing                      'fg=170,bold'
  history-expansion             'fg=blue'
  single-hyphen-option          'fg=244'
  double-hyphen-option          'fg=244'
  back-quoted-argument          'fg=220,bold'
  single-quoted-argument        'fg=137'
  double-quoted-argument        'fg=137'
  dollar-double-quoted-argument 'fg=148'
  back-double-quoted-argument   'fg=172,bold'
  assign                        'fg=240,bold'
)

mkstyle () {
  local lastlast
  local last

  while [ "$#" -gt 0 ]; do
    cur=$1
    shift

    if [ "$last" = 5 ]; then
      if [ "$lastlast" = 38 ]; then
        style+=( "fg=$cur" )
        lastlast=
        last=
        continue
      elif [ "$lastlast" = 48 ]; then
        style+=( "bg=$cur" )
        lastlast=
        last=
        continue
      fi
    fi

    lastlast=$last
    last=$cur
  done

  case "$last" in
    00|0) style+=( "none" )       ;;
    01|1) style+=( "bold" )       ;;
    04|4) style+=( "underscore" ) ;;
    05|5) style+=( "blink" )      ;;
    07|7) style+=( "reverse" )    ;;
    08|8) style+=( "concealed" )  ;;
  esac
}

function {
  local coloring ext rawstyle
  local -a style

  for coloring in ${(s.:.)LS_COLORS}; do
    ext=${coloring%%\=*}
    rawstyle=${coloring##*\=}
    style=()

    mkstyle ${(s.;.)rawstyle}
    style=${(j.,.)style}

    ZSH_HIGHLIGHT_STYLES+=(
      "$ext" "$style"
    )
  done
}

# Tokens that are always immediately followed by a command.
ZSH_HIGHLIGHT_TOKENS_FOLLOWED_BY_COMMANDS=(
  '|' '||' ';' '&' '&&' 'noglob' 'nocorrect' 'builtin'
)

# Check if the argument is variable assignment
_zsh_highlight_check-assign() {
    setopt localoptions extended_glob
    [[ ${(Q)arg} == [[:alpha:]_]([[:alnum:]_])#=* ]]
}

# Check if the argument is a path.
_zsh_highlight_check-path() {
  [[ -z ${(Q)arg} ]] && return 1
  [[ -e ${(Q)arg} ]] && return 0
  [[ ! -e ${(Q)arg:h} ]] && return 1
  [[ ${#BUFFER} == $end_pos && -n $(print ${(Q)arg}*(N)) ]] && return 0
  return 1
}

# Highlight special chars inside double-quoted strings
_zsh_highlight_highlight_string() {
  setopt localoptions noksharrays
  local i j k style
  # Starting quote is at 1, so start parsing at offset 2 in the string.
  for (( i = 2 ; i < end_pos - start_pos ; i += 1 )) ; do
    (( j = i + start_pos - 1 ))
    (( k = j + 1 ))
    case "$arg[$i]" in
      '$')  style=$ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument];;
      '%')  style=$ZSH_HIGHLIGHT_STYLES[globbing];;
      '^')  style=$ZSH_HIGHLIGHT_STYLES[globbing];;
      "\\") style=$ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]
            (( k += 1 )) # Color following char too.
            (( i += 1 )) # Skip parsing the escaped char.
            ;;
      *)    continue;;
    esac
    region_highlight+=("$j $k $style")
  done
}

# Core syntax highlighting.
_zsh_main-highlight() {
  setopt localoptions extendedglob bareglobqual
  local start_pos=0 end_pos highlight_glob=true new_expression=true arg style
  region_highlight=()

  for arg in ${(z)BUFFER}; do
    local substr_color=0

    style=

    [[ $start_pos -eq 0 && $arg = 'noglob' ]] && highlight_glob=false

    ((start_pos+=${#BUFFER[$start_pos+1,-1]}-${#${BUFFER[$start_pos+1,-1]##[[:space:]]#}}))
    ((end_pos=$start_pos+${#arg}))

    if $new_expression; then
      new_expression=false

      res=$(LC_ALL=C builtin type -w $arg 2>/dev/null)
      case $res in
        *': reserved')  style=$ZSH_HIGHLIGHT_STYLES[reserved-word];;
        *': alias')     style=$ZSH_HIGHLIGHT_STYLES[alias]
                        local aliased_command="${"$(alias $arg)"#*=}"
                        [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_FOLLOWED_BY_COMMANDS:#"$aliased_command"} && -z ${(M)ZSH_HIGHLIGHT_TOKENS_FOLLOWED_BY_COMMANDS:#"$arg"} ]] && ZSH_HIGHLIGHT_TOKENS_FOLLOWED_BY_COMMANDS+=($arg)
                        ;;
        *': builtin')   style=$ZSH_HIGHLIGHT_STYLES[builtin];;
        *': function')  style=$ZSH_HIGHLIGHT_STYLES[function];;
        *': command')   style=$ZSH_HIGHLIGHT_STYLES[command];;
        *': hashed')    style=$ZSH_HIGHLIGHT_STYLES[hashed-command];;
        *)              if _zsh_highlight_check-assign; then
                          style=$ZSH_HIGHLIGHT_STYLES[assign]
                          new_expression=true
                        elif _zsh_highlight_check-path; then
                          style=$ZSH_HIGHLIGHT_STYLES[path]
                        elif [[ $arg[0,1] = $histchars[0,1] ]]; then
                          style=$ZSH_HIGHLIGHT_STYLES[history-expansion]
                        else
                          style=$ZSH_HIGHLIGHT_STYLES[unknown-token]
                        fi
                        ;;
      esac
    else
      case $arg in
        *.pl)         style=$ZSH_HIGHLIGHT_STYLES[filetype-perl];;
        *.bash)       style=$ZSH_HIGHLIGHT_STYLES[filetype-bash];;
        *.sh)         style=$ZSH_HIGHLIGHT_STYLES[filetype-sh];;
        *.1p)         style=$ZSH_HIGHLIGHT_STYLES[filetype-1p];;
        *.32x)        style=$ZSH_HIGHLIGHT_STYLES[filetype-32x];;
        *.3p)         style=$ZSH_HIGHLIGHT_STYLES[filetype-3p];;
        *.7z)         style=$ZSH_HIGHLIGHT_STYLES[filetype-7z];;
        *.a00)        style=$ZSH_HIGHLIGHT_STYLES[filetype-a00];;
        *.a52)        style=$ZSH_HIGHLIGHT_STYLES[filetype-a52];;
        *.a64)        style=$ZSH_HIGHLIGHT_STYLES[filetype-a64];;
        *.A64)        style=$ZSH_HIGHLIGHT_STYLES[filetype-A64];;
        *.a78)        style=$ZSH_HIGHLIGHT_STYLES[filetype-a78];;
        *.adf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-adf];;
        *.afm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-afm];;
        *.am)         style=$ZSH_HIGHLIGHT_STYLES[filetype-am];;
        *.arj)        style=$ZSH_HIGHLIGHT_STYLES[filetype-arj];;
        *.asm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-asm];;
        *.a)          style=$ZSH_HIGHLIGHT_STYLES[filetype-a];;
        *.atr)        style=$ZSH_HIGHLIGHT_STYLES[filetype-atr];;
        *.avi)        style=$ZSH_HIGHLIGHT_STYLES[filetype-avi];;
        *.awk)        style=$ZSH_HIGHLIGHT_STYLES[filetype-awk];;
        *.bak)        style=$ZSH_HIGHLIGHT_STYLES[filetype-bak];;
        *.bash)       style=$ZSH_HIGHLIGHT_STYLES[filetype-bash];;
        *.bat)        style=$ZSH_HIGHLIGHT_STYLES[filetype-bat];;
        *.BAT)        style=$ZSH_HIGHLIGHT_STYLES[filetype-BAT];;
        *.bin)        style=$ZSH_HIGHLIGHT_STYLES[filetype-bin];;
        *.bmp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-bmp];;
        *.bz2)        style=$ZSH_HIGHLIGHT_STYLES[filetype-bz2];;
        *.cbr)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cbr];;
        *.cbz)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cbz];;
        *.cdi)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cdi];;
        *.cdr)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cdr];;
        *.cfg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cfg];;
        *.chm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-chm];;
        *.coffee)     style=$ZSH_HIGHLIGHT_STYLES[filetype-coffee];;
        *.conf)       style=$ZSH_HIGHLIGHT_STYLES[filetype-conf];;
        *.cpp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cpp];;
        *.css)        style=$ZSH_HIGHLIGHT_STYLES[filetype-css];;
        *.cs)         style=$ZSH_HIGHLIGHT_STYLES[filetype-cs];;
        *.c)          style=$ZSH_HIGHLIGHT_STYLES[filetype-c];;
        *.csv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-csv];;
        *.cue)        style=$ZSH_HIGHLIGHT_STYLES[filetype-cue];;
        *.dat)        style=$ZSH_HIGHLIGHT_STYLES[filetype-dat];;
        *.db)         style=$ZSH_HIGHLIGHT_STYLES[filetype-db];;
        *.def)        style=$ZSH_HIGHLIGHT_STYLES[filetype-def];;
        *.diff)       style=$ZSH_HIGHLIGHT_STYLES[filetype-diff];;
        *.directory)  style=$ZSH_HIGHLIGHT_STYLES[filetype-directory];;
        *.djvu)       style=$ZSH_HIGHLIGHT_STYLES[filetype-djvu];;
        *.dump)       style=$ZSH_HIGHLIGHT_STYLES[filetype-dump];;
        *.enc)        style=$ZSH_HIGHLIGHT_STYLES[filetype-enc];;
        *.eps)        style=$ZSH_HIGHLIGHT_STYLES[filetype-eps];;
        *.error)      style=$ZSH_HIGHLIGHT_STYLES[filetype-error];;
        *.err)        style=$ZSH_HIGHLIGHT_STYLES[filetype-err];;
        *.etx)        style=$ZSH_HIGHLIGHT_STYLES[filetype-etx];;
        *.example)    style=$ZSH_HIGHLIGHT_STYLES[filetype-example];;
        *.ex)         style=$ZSH_HIGHLIGHT_STYLES[filetype-ex];;
        *.fcm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-fcm];;
        *.flac)       style=$ZSH_HIGHLIGHT_STYLES[filetype-flac];;
        *.flv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-flv];;
        *.fm2)        style=$ZSH_HIGHLIGHT_STYLES[filetype-fm2];;
        *.gba)        style=$ZSH_HIGHLIGHT_STYLES[filetype-gba];;
        *.gbc)        style=$ZSH_HIGHLIGHT_STYLES[filetype-gbc];;
        *.gb)         style=$ZSH_HIGHLIGHT_STYLES[filetype-gb];;
        *.gel)        style=$ZSH_HIGHLIGHT_STYLES[filetype-gel];;
        *.ggl)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ggl];;
        *.gg)         style=$ZSH_HIGHLIGHT_STYLES[filetype-gg];;
        *.gif)        style=$ZSH_HIGHLIGHT_STYLES[filetype-gif];;
        *.gitignore)  style=$ZSH_HIGHLIGHT_STYLES[filetype-gitignore];;
        *.git)        style=$ZSH_HIGHLIGHT_STYLES[filetype-git];;
        *.go)         style=$ZSH_HIGHLIGHT_STYLES[filetype-go];;
        *.hs)         style=$ZSH_HIGHLIGHT_STYLES[filetype-hs];;
        *.h)          style=$ZSH_HIGHLIGHT_STYLES[filetype-h];;
        *.html)       style=$ZSH_HIGHLIGHT_STYLES[filetype-html];;
        *.htm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-htm];;
        *.ico)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ico];;
        *.info)       style=$ZSH_HIGHLIGHT_STYLES[filetype-info];;
        *.ini)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ini];;
        *.in)         style=$ZSH_HIGHLIGHT_STYLES[filetype-in];;
        *.iso)        style=$ZSH_HIGHLIGHT_STYLES[filetype-iso];;
        *.j64)        style=$ZSH_HIGHLIGHT_STYLES[filetype-j64];;
        *.jad)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jad];;
        *.jar)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jar];;
        *.java)       style=$ZSH_HIGHLIGHT_STYLES[filetype-java];;
        *.jhtm)       style=$ZSH_HIGHLIGHT_STYLES[filetype-jhtm];;
        *.jpeg)       style=$ZSH_HIGHLIGHT_STYLES[filetype-jpeg];;
        *.jpg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jpg];;
        *.JPG)        style=$ZSH_HIGHLIGHT_STYLES[filetype-JPG];;
        *.jsm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jsm];;
        *.jsm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jsm];;
        *.json)       style=$ZSH_HIGHLIGHT_STYLES[filetype-json];;
        *.jsp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-jsp];;
        *.js)         style=$ZSH_HIGHLIGHT_STYLES[filetype-js];;
        *.lisp)       style=$ZSH_HIGHLIGHT_STYLES[filetype-lisp];;
        *.log)        style=$ZSH_HIGHLIGHT_STYLES[filetype-log];;
        *.lua)        style=$ZSH_HIGHLIGHT_STYLES[filetype-lua];;
        *.m3u)        style=$ZSH_HIGHLIGHT_STYLES[filetype-m3u];;
        *.m4a)        style=$ZSH_HIGHLIGHT_STYLES[filetype-m4a];;
        *.m4)         style=$ZSH_HIGHLIGHT_STYLES[filetype-m4];;
        *.map)        style=$ZSH_HIGHLIGHT_STYLES[filetype-map];;
        *.markdown)   style=$ZSH_HIGHLIGHT_STYLES[filetype-markdown];;
        *.md)         style=$ZSH_HIGHLIGHT_STYLES[filetype-md];;
        *.mfasl)      style=$ZSH_HIGHLIGHT_STYLES[filetype-mfasl];;
        *.mf)         style=$ZSH_HIGHLIGHT_STYLES[filetype-mf];;
        *.mi)         style=$ZSH_HIGHLIGHT_STYLES[filetype-mi];;
        *.mkd)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mkd];;
        *.mkv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mkv];;
        *.mod)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mod];;
        *.mov)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mov];;
        *.MOV)        style=$ZSH_HIGHLIGHT_STYLES[filetype-MOV];;
        *.mp3)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mp3];;
        *.mp4)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mp4];;
        *.mpeg)       style=$ZSH_HIGHLIGHT_STYLES[filetype-mpeg];;
        *.mpg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mpg];;
        *.mtx)        style=$ZSH_HIGHLIGHT_STYLES[filetype-mtx];;
        *.nds)        style=$ZSH_HIGHLIGHT_STYLES[filetype-nds];;
        *.nes)        style=$ZSH_HIGHLIGHT_STYLES[filetype-nes];;
        *.nfo)        style=$ZSH_HIGHLIGHT_STYLES[filetype-nfo];;
        *.nrg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-nrg];;
        *.odb)        style=$ZSH_HIGHLIGHT_STYLES[filetype-odb];;
        *.odp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-odp];;
        *.ods)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ods];;
        *.odt)        style=$ZSH_HIGHLIGHT_STYLES[filetype-odt];;
        *.oga)        style=$ZSH_HIGHLIGHT_STYLES[filetype-oga];;
        *.ogg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ogg];;
        *.ogm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ogm];;
        *.ogv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ogv];;
        *.old)        style=$ZSH_HIGHLIGHT_STYLES[filetype-old];;
        *.out)        style=$ZSH_HIGHLIGHT_STYLES[filetype-out];;
        *.pacnew)     style=$ZSH_HIGHLIGHT_STYLES[filetype-pacnew];;
        *.part)       style=$ZSH_HIGHLIGHT_STYLES[filetype-part];;
        *.patch)      style=$ZSH_HIGHLIGHT_STYLES[filetype-patch];;
        *.pcf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pcf];;
        *.pc)         style=$ZSH_HIGHLIGHT_STYLES[filetype-pc];;
        *.pdf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pdf];;
        *.pfa)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pfa];;
        *.pfb)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pfb];;
        *.pfm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pfm];;
        *.php)        style=$ZSH_HIGHLIGHT_STYLES[filetype-php];;
        *.pid)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pid];;
        *.pi)         style=$ZSH_HIGHLIGHT_STYLES[filetype-pi];;
        *.pl)         style=$ZSH_HIGHLIGHT_STYLES[filetype-pl];;
        *.PL)         style=$ZSH_HIGHLIGHT_STYLES[filetype-PL];;
        *.pm)         style=$ZSH_HIGHLIGHT_STYLES[filetype-pm];;
        *.png)        style=$ZSH_HIGHLIGHT_STYLES[filetype-png];;
        *.pod)        style=$ZSH_HIGHLIGHT_STYLES[filetype-pod];;
        *.properties) style=$ZSH_HIGHLIGHT_STYLES[filetype-properties];;
        *.psf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-psf];;
        *.py)         style=$ZSH_HIGHLIGHT_STYLES[filetype-py];;
        *.qcow)       style=$ZSH_HIGHLIGHT_STYLES[filetype-qcow];;
        *.r00)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r00];;
        *.r01)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r01];;
        *.r02)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r02];;
        *.r03)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r03];;
        *.r04)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r04];;
        *.r05)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r05];;
        *.r06)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r06];;
        *.r07)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r07];;
        *.r08)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r08];;
        *.r09)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r09];;
        *.r100)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r100];;
        *.r101)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r101];;
        *.r102)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r102];;
        *.r103)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r103];;
        *.r104)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r104];;
        *.r105)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r105];;
        *.r106)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r106];;
        *.r107)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r107];;
        *.r108)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r108];;
        *.r109)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r109];;
        *.r10)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r10];;
        *.r110)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r110];;
        *.r111)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r111];;
        *.r112)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r112];;
        *.r113)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r113];;
        *.r114)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r114];;
        *.r115)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r115];;
        *.r116)       style=$ZSH_HIGHLIGHT_STYLES[filetype-r116];;
        *.r11)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r11];;
        *.r12)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r12];;
        *.r13)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r13];;
        *.r14)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r14];;
        *.r15)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r15];;
        *.r16)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r16];;
        *.r17)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r17];;
        *.r18)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r18];;
        *.r19)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r19];;
        *.r20)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r20];;
        *.r21)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r21];;
        *.r22)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r22];;
        *.r25)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r25];;
        *.r26)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r26];;
        *.r27)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r27];;
        *.r28)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r28];;
        *.r29)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r29];;
        *.r30)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r30];;
        *.r31)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r31];;
        *.r32)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r32];;
        *.r33)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r33];;
        *.r34)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r34];;
        *.r35)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r35];;
        *.r36)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r36];;
        *.r37)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r37];;
        *.r38)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r38];;
        *.r39)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r39];;
        *.r40)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r40];;
        *.r41)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r41];;
        *.r42)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r42];;
        *.r43)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r43];;
        *.r44)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r44];;
        *.r45)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r45];;
        *.r46)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r46];;
        *.r47)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r47];;
        *.r48)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r48];;
        *.r49)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r49];;
        *.r50)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r50];;
        *.r51)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r51];;
        *.r52)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r52];;
        *.r53)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r53];;
        *.r54)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r54];;
        *.r55)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r55];;
        *.r56)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r56];;
        *.r57)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r57];;
        *.r58)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r58];;
        *.r59)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r59];;
        *.r60)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r60];;
        *.r61)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r61];;
        *.r62)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r62];;
        *.r63)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r63];;
        *.r64)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r64];;
        *.r65)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r65];;
        *.r66)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r66];;
        *.r67)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r67];;
        *.r68)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r68];;
        *.r69)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r69];;
        *.r69)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r69];;
        *.r70)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r70];;
        *.r71)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r71];;
        *.r72)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r72];;
        *.r73)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r73];;
        *.r74)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r74];;
        *.r75)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r75];;
        *.r76)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r76];;
        *.r77)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r77];;
        *.r78)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r78];;
        *.r79)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r79];;
        *.r80)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r80];;
        *.r81)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r81];;
        *.r82)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r82];;
        *.r83)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r83];;
        *.r84)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r84];;
        *.r85)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r85];;
        *.r86)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r86];;
        *.r87)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r87];;
        *.r88)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r88];;
        *.r89)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r89];;
        *.r90)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r90];;
        *.r91)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r91];;
        *.r92)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r92];;
        *.r93)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r93];;
        *.r94)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r94];;
        *.r95)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r95];;
        *.r96)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r96];;
        *.r97)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r97];;
        *.r98)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r98];;
        *.r99)        style=$ZSH_HIGHLIGHT_STYLES[filetype-r99];;
        *.rar)        style=$ZSH_HIGHLIGHT_STYLES[filetype-rar];;
        *.rb)         style=$ZSH_HIGHLIGHT_STYLES[filetype-rb];;
        *.rdf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-rdf];;
        *.rmvb)       style=$ZSH_HIGHLIGHT_STYLES[filetype-rmvb];;
        *.rom)        style=$ZSH_HIGHLIGHT_STYLES[filetype-rom];;
        *.ru)         style=$ZSH_HIGHLIGHT_STYLES[filetype-ru];;
        *.s3m)        style=$ZSH_HIGHLIGHT_STYLES[filetype-s3m];;
        *.S3M)        style=$ZSH_HIGHLIGHT_STYLES[filetype-S3M];;
        *.sample)     style=$ZSH_HIGHLIGHT_STYLES[filetype-sample];;
        *.sav)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sav];;
        *.sed)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sed];;
        *.sfv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sfv];;
        *.sh)         style=$ZSH_HIGHLIGHT_STYLES[filetype-sh];;
        *.sid)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sid];;
        *.signature)  style=$ZSH_HIGHLIGHT_STYLES[filetype-signature];;
        *.SKIP)       style=$ZSH_HIGHLIGHT_STYLES[filetype-SKIP];;
        *.sms)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sms];;
        *.spl)        style=$ZSH_HIGHLIGHT_STYLES[filetype-spl];;
        *.sqlite)     style=$ZSH_HIGHLIGHT_STYLES[filetype-sqlite];;
        *.sql)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sql];;
        *.srt)        style=$ZSH_HIGHLIGHT_STYLES[filetype-srt];;
        *.st)         style=$ZSH_HIGHLIGHT_STYLES[filetype-st];;
        *.sty)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sty];;
        *.sug)        style=$ZSH_HIGHLIGHT_STYLES[filetype-sug];;
        *.svg)        style=$ZSH_HIGHLIGHT_STYLES[filetype-svg];;
        *.swo)        style=$ZSH_HIGHLIGHT_STYLES[filetype-swo];;
        *.swp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-swp];;
        *.tar.gz)     style=$ZSH_HIGHLIGHT_STYLES[filetype-tar.gz];;
        *.tar)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tar];;
        *.tcl)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tcl];;
        *.tdy)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tdy];;
        *.tex)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tex];;
        *.textile)    style=$ZSH_HIGHLIGHT_STYLES[filetype-textile];;
        *.tfm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tfm];;
        *.tfnt)       style=$ZSH_HIGHLIGHT_STYLES[filetype-tfnt];;
        *.tgz)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tgz];;
        *.theme)      style=$ZSH_HIGHLIGHT_STYLES[filetype-theme];;
        *.tmp)        style=$ZSH_HIGHLIGHT_STYLES[filetype-tmp];;
        *.torrent)    style=$ZSH_HIGHLIGHT_STYLES[filetype-torrent];;
        *.ts)         style=$ZSH_HIGHLIGHT_STYLES[filetype-ts];;
        *.t)          style=$ZSH_HIGHLIGHT_STYLES[filetype-t];;
        *.ttf)        style=$ZSH_HIGHLIGHT_STYLES[filetype-ttf];;
        *.txt)        style=$ZSH_HIGHLIGHT_STYLES[filetype-txt];;
        *.typelib)    style=$ZSH_HIGHLIGHT_STYLES[filetype-typelib];;
        *.un~)        style=$ZSH_HIGHLIGHT_STYLES[filetype-un~];;
        *.urlview)    style=$ZSH_HIGHLIGHT_STYLES[filetype-urlview];;
        *.viminfo)    style=$ZSH_HIGHLIGHT_STYLES[filetype-viminfo];;
        *.vim)        style=$ZSH_HIGHLIGHT_STYLES[filetype-vim];;
        *.wmv)        style=$ZSH_HIGHLIGHT_STYLES[filetype-wmv];;
        *.wvc)        style=$ZSH_HIGHLIGHT_STYLES[filetype-wvc];;
        *.wv)         style=$ZSH_HIGHLIGHT_STYLES[filetype-wv];;
        *.xml)        style=$ZSH_HIGHLIGHT_STYLES[filetype-xml];;
        *.xpm)        style=$ZSH_HIGHLIGHT_STYLES[filetype-xpm];;
        *.xz)         style=$ZSH_HIGHLIGHT_STYLES[filetype-xz];;
        *.yml)        style=$ZSH_HIGHLIGHT_STYLES[filetype-yml];;
        *.zcompdump)  style=$ZSH_HIGHLIGHT_STYLES[filetype-zcompdump];;
        *.zip)        style=$ZSH_HIGHLIGHT_STYLES[filetype-zip];;
        *.zsh)        style=$ZSH_HIGHLIGHT_STYLES[filetype-zsh];;


        '--'*)   style=$ZSH_HIGHLIGHT_STYLES[double-hyphen-option];;
        '-'*)    style=$ZSH_HIGHLIGHT_STYLES[single-hyphen-option];;
        "'"*"'") style=$ZSH_HIGHLIGHT_STYLES[single-quoted-argument];;
        '"'*'"') style=$ZSH_HIGHLIGHT_STYLES[double-quoted-argument]
                 region_highlight+=("$start_pos $end_pos $style")
                 _zsh_highlight_highlight_string
                 substr_color=1
                 ;;
        '`'*'`') style=$ZSH_HIGHLIGHT_STYLES[back-quoted-argument];;
        *"*"*)   $highlight_glob && style=$ZSH_HIGHLIGHT_STYLES[globbing] ||
                   style=$ZSH_HIGHLIGHT_STYLES[default];;
        *)       if _zsh_highlight_check-path; then
                   style=$ZSH_HIGHLIGHT_STYLES[path]
                 elif [[ $arg[0,1] = $histchars[0,1] ]]; then
                   style=$ZSH_HIGHLIGHT_STYLES[history-expansion]
                 else
                   style=$ZSH_HIGHLIGHT_STYLES[default]
                 fi
                 ;;
      esac
    fi
    [[ $substr_color = 0 ]] &&
      region_highlight+=("$start_pos $end_pos $style")
    [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_FOLLOWED_BY_COMMANDS:#"$arg"} ]] && new_expression=true
    start_pos=$end_pos
  done
}


# Setup functions

# Intercept specified ZLE events to have highlighting triggered.
_zsh_highlight_bind-events() {

  # Resolve event names what have to be bound to.
  zmodload zsh/zleparameter 2>/dev/null || {
    echo 'zsh-syntax-highlighting:zmodload error. exiting.' >&2
    return -1
  }
  local -a events; : ${(A)events::=${@:#(_*|orig-*|.run-help|.which-command)}}

  # Bind the events to _zsh_highlight-zle-buffer.
  local clean_event
  for event in $events; do
    if [[ "$widgets[$event]" == completion:* ]]; then
      eval "zle -C orig-$event ${${${widgets[$event]}#*:}/:/ } ; $event() { builtin zle orig-$event && _zsh_highlight-zle-buffer } ; zle -N $event"
    else
      case $event in
        accept-and-menu-complete)
          eval "$event() { builtin zle .$event && _zsh_highlight-zle-buffer } ; zle -N $event"
          ;;
        .*)
          # Remove the leading dot in the event name
          clean_event=$event[2,${#event}]
          case ${widgets[$clean_event]-} in
            (completion|user):*)
              ;;
            *)
              eval "$clean_event() { builtin zle $event && _zsh_highlight-zle-buffer } ; zle -N $clean_event"
              ;;
          esac
          ;;
        *)
          ;;
      esac
    fi
  done
}

# Load highlighters from specified directory if it exists.
_zsh_highlight_load-highlighters() {
  [[ -d $1 ]] && for highlighter_def ($1/*.zsh) . $highlighter_def
}


# Setup

# Bind highlighting to all known events.
_zsh_highlight_bind-events "${(@f)"$(zle -la)"}"

# Register the main highlighter.
_zsh_highlight_add-highlighter _zsh_main-highlight _zsh_highlight_buffer-modified-p

# Load additional highlighters if available.
_zsh_highlight_load-highlighters "${${(%):-%N}:h}/highlighters"
