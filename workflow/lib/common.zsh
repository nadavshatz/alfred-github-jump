# lib/common.zsh — shared helpers for GitHub Jump.
#
# Alfred Script Filter JSON, input validation, cache paths and configuration.
# Nothing here ever passes a string to eval or sh -c.

zmodload zsh/datetime zsh/stat
setopt extended_glob no_unset pipe_fail
umask 077

typeset -r GJ_LABEL="io.github.nadavshatz.github-jump"
typeset -r GJ_WF_DIR="${${(%):-%x}:A:h:h}"          # .../workflow

# ---------------------------------------------------------------------------
# Configuration (Alfred "Configure Workflow…" variables)
# ---------------------------------------------------------------------------
typeset -r CFG_ORGS="${orgs:-TailorBrands}"
typeset -r CFG_CODE_DIR="${${code_dir:-$HOME/code}/#\~/$HOME}"
typeset -r CFG_KEYWORD="${keyword:-gh}"
typeset -ri REPOS_TTL=86400 TREE_TTL=3600

typeset -r GJ_CACHE="${alfred_workflow_cache:-$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/$GJ_LABEL}"
[[ -d $GJ_CACHE ]] || mkdir -p -m 700 -- "$GJ_CACHE"
chmod 700 "$GJ_CACHE" 2>/dev/null
typeset -r REPOS_FILE="$GJ_CACHE/repos.tsv"       # slug \t default-branch \t description
typeset -r CLONES_FILE="$GJ_CACHE/clones.tsv"     # slug \t local path
typeset -r ERRORS_FILE="$GJ_CACHE/errors"         # orgs that could not be listed
typeset -r REFRESH_MARK="$GJ_CACHE/refresh.started"

# Updater (lib/update.zsh)
typeset -r UPD_LABEL=$GJ_LABEL UPD_NAME="GitHub Jump" UPD_PKG="GitHub-Jump" UPD_WF_DIR=$GJ_WF_DIR
typeset -r UPD_REPO="${GJ_UPDATE_REPO:-https://github.com/nadavshatz/alfred-github-jump}"
typeset -r UPD_CURL="${GJ_CURL:-/usr/bin/curl}" UPD_OPEN="${GJ_OPEN:-/usr/bin/open}"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
# owner/repo: GitHub's name characters only; no "." / ".." parts, no leading "-".
valid_slug() {
  local s=${1:-}
  [[ $s == [A-Za-z0-9._-]##/[A-Za-z0-9._-]## ]] || return 1
  local o=${s%%/*} r=${s#*/}
  [[ $o != (.|..|-*) && $r != (.|..|-*) ]]
}
valid_org() { [[ ${1:-} == [A-Za-z0-9]([A-Za-z0-9-]#) ]] }

# urlencode_path PATH: percent-encode every byte outside [A-Za-z0-9._~/-].
urlencode_path() {
  local s=$1 out= c
  setopt local_options no_multibyte
  for (( i = 1; i <= $#s; i++ )); do
    c=$s[i]
    if [[ $c == [A-Za-z0-9._~/-] ]]; then out+=$c
    else out+=$(printf '%%%02X' "'$c"); fi
  done
  print -r -- $out
}

# ---------------------------------------------------------------------------
# Alfred JSON
# ---------------------------------------------------------------------------
typeset -ga ITEMS=()

js() {  # JSON string literal
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//[[:cntrl:]]/}
  print -rn -- "\"$s\""
}

# item TITLE SUBTITLE ARG VALID ICON [key=value ...]
#   cmd=ARG alt=ARG ctrl=ARG   modifier args (subtitles are fixed per key)
#   ac=STR  uid=STR            autocomplete / Alfred learning uid
#   vars=JSON                  raw JSON object for "variables"
item() {
  local t=$1 sub=$2 arg=$3 valid=$4 icon=$5; shift 5
  local j="{\"title\":$(js "$t"),\"subtitle\":$(js "$sub"),\"arg\":$(js "$arg"),\"valid\":$valid"
  j+=",\"icon\":{\"path\":$(js "icons/$icon.png")}"
  local -a mods=()
  local kv k v
  for kv in "$@"; do
    k=${kv%%=*} v=${kv#*=}
    case $k in
      cmd)  mods+=("\"cmd\":{\"arg\":$(js "$v"),\"subtitle\":\"Open Actions\",\"valid\":true}") ;;
      alt)  mods+=("\"alt\":{\"arg\":$(js "$v"),\"subtitle\":\"Open pull requests\",\"valid\":true}") ;;
      ctrl) mods+=("\"ctrl\":{\"arg\":$(js "$v"),\"subtitle\":\"Copy URL\",\"valid\":true}") ;;
      ac)   j+=",\"autocomplete\":$(js "$v")" ;;
      uid)  j+=",\"uid\":$(js "$v")" ;;
      vars) j+=",\"variables\":$v" ;;
    esac
  done
  (( $#mods )) && j+=",\"mods\":{${(j:,:)mods}}"
  ITEMS+=("$j}")
}

emit() {  # [rerun-seconds]
  local out="{\"skipknowledge\":false"
  [[ -n ${1:-} ]] && out+=",\"rerun\":$1"
  print -r -- "$out,\"items\":[${(j:,:)ITEMS}]}"
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
# atomic_write FILE: stdin → FILE (mode 600) via a temp file + rename.
atomic_write() {
  local tmp="$1.$$"
  cat > $tmp && chmod 600 $tmp && mv -f -- $tmp $1
}

# age_of FILE → REPLY=seconds since last modification (huge if missing).
age_of() {
  REPLY=999999999
  [[ -e $1 ]] || return 1
  local -a st
  zstat -A st +mtime -- $1 && REPLY=$(( EPOCHSECONDS - st[1] ))
}
