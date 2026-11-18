#!/bin/zsh -f
# search.sh — GitHub Jump Script Filter.
#
#   gh <text>               fuzzy-match cached repos
#   gh owner/repo /path     file mode (see files_mode)
#   gh > refresh            rebuild the cache now
#
# Reads only the cache; `gh` is called here solely to check the login when no
# cache exists yet (file mode adds read-only tree/branch lookups).

source "${0:A:h}/lib/common.zsh"
source $GJ_WF_DIR/lib/gh.zsh
source $GJ_WF_DIR/lib/files.zsh
typeset -i HAS_UPDATER=0
[[ -r $GJ_WF_DIR/lib/update.zsh ]] && source $GJ_WF_DIR/lib/update.zsh && HAS_UPDATER=1

typeset -r Q=${${1:-}##[[:space:]]#}
typeset -ri MAX_REPOS=30

# Start refresh.sh in the background unless one started in the last minute.
spawn_refresh() {
  age_of $REFRESH_MARK && (( REPLY < 60 )) && return 0
  touch -- $REFRESH_MARK
  /usr/bin/nohup $GJ_WF_DIR/refresh.sh </dev/null >/dev/null 2>&1 &!
}

repo_item() {  # slug description
  local slug=$1 desc=$2 url="https://github.com/$1"
  local sub="↩ open · ⌘ Actions · ⌥ pull requests · ⌃ copy URL"
  [[ -n $desc ]] && sub="$desc · $sub"
  item "$slug" "$sub" "$url" true repo cmd="$url/actions" alt="$url/pulls" ctrl="$url" ac="$slug " uid="$slug"
}

# score SLUG QUERY → REPLY (lower is better); returns 1 if no match.
score() {
  local s=${(L)1} q=$2 name=${(L)1#*/}
  if   [[ $name == $q ]];        then REPLY=0
  elif [[ $s == $q ]];           then REPLY=0
  elif [[ $name == ${q}* ]];     then REPLY=1
  elif [[ $s == ${q}* ]];        then REPLY=2
  elif [[ $name == *${q}* ]];    then REPLY=3
  elif [[ $s == *${q}* ]];       then REPLY=4
  else
    # subsequence: every query character appears in order
    local pat=${(j:*:)${(s::)q}}
    [[ $s == *${~pat}* ]] || return 1
    REPLY=5
  fi
}

search_repos() {
  local q=${(L)${Q//[[:space:]]/}}
  # Glob-quote the query so characters like * [ ( are matched literally.
  local qq=${(b)q}
  local -a ranked=()
  local line slug branch desc
  while IFS=$'\t' read -r slug branch desc; do
    valid_slug "$slug" || continue
    if [[ -z $q ]]; then ranked+=("9"$'\t'"$slug"$'\t'"$desc"); continue; fi
    score "$slug" "$qq" || continue
    ranked+=("$REPLY"$'\t'"$(( 1000 + ${#slug} ))"$'\t'"$slug"$'\t'"$desc")
  done < $REPOS_FILE
  ranked=(${(o)ranked})
  local r f
  for r in ${ranked[1,MAX_REPOS]}; do
    f=(${(ps:\t:)r})
    if [[ -z $q ]]; then repo_item "$f[2]" "${f[3]:-}"
    else repo_item "$f[3]" "${f[4]:-}"; fi
  done
  # A full owner/repo that isn't in the cache can still be opened by URL.
  if [[ -n $Q && $Q != *[[:space:]]* ]] && valid_slug "$Q" && ! (( ${ranked[(I)*$'\t'$Q$'\t'*]} )); then
    local -a before=("${(@)ITEMS}")
    ITEMS=()
    repo_item "$Q" "Not in your cached list"
    ITEMS+=("${(@)before}")
  fi
  (( $#ITEMS )) || item "No repo matches “$Q”" "Type owner/repo to open any repo · “> refresh” to rebuild the list" "" false info
}

if [[ $Q == (#s)'>'[[:space:]]#(refresh|r)[[:space:]]#(#e) || $Q == (#s)'>'[[:space:]]#(#e) ]]; then
  item "Refresh repo list" "Lists your repos and ${CFG_ORGS} again with gh" refresh true refresh
  emit; exit 0
fi

if [[ $Q == (#b)([^[:space:]]##)[[:space:]]##/(*) ]]; then
  files_mode "$match[1]" "$match[2]"
  emit; exit 0
fi

if [[ ! -s $REPOS_FILE ]]; then
  if ! gh_ok; then
    item "GitHub CLI not ready: run gh auth login" "Needs gh at ${GH_BIN} and a login (gh auth login in a terminal)" "" false warning
    emit; exit 0
  fi
  spawn_refresh
  item "Building repo list…" "Listing your repos and ${CFG_ORGS} with gh (first run takes ~10s)" "" false refresh
  emit 0.5; exit 0
fi

age_of $REPOS_FILE
(( REPLY >= REPOS_TTL )) && spawn_refresh

search_repos

if [[ -s $ERRORS_FILE ]]; then
  local o
  for o in ${(f)"$(<$ERRORS_FILE)"}; do
    item "Couldn’t list $o (SSO not authorised for gh?)" "Run: gh auth refresh, or authorise the token for $o on github.com" "" false warning
  done
fi
[[ -z $Q ]] && (( HAS_UPDATER )) && update_notice "$GJ_WF_DIR/open.sh"
emit
