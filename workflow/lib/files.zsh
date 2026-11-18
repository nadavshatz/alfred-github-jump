# lib/files.zsh — file mode: "owner/repo /path-query".
#
# Lists files from a local clone (git ls-files, no network) when one exists
# under the code dir, otherwise from GitHub's tree API through gh_tree, cached
# for TREE_TTL. Links always point at the repo's default branch.

typeset -ri MAX_FILES=40
typeset -r TREES_DIR="$GJ_CACHE/trees"

# branch_of SLUG → REPLY (cached repo list first, then gh).
branch_of() {
  REPLY=
  local slug branch rest
  if [[ -r $REPOS_FILE ]]; then
    while IFS=$'\t' read -r slug branch rest; do
      [[ ${(L)slug} == ${(L)1} && -n $branch ]] && { REPLY=$branch; return 0 }
    done < $REPOS_FILE
  fi
  gh_default_branch "$1"
}

# clone_of SLUG → REPLY=local checkout path.
clone_of() {
  REPLY=
  [[ -r $CLONES_FILE ]] || return 1
  local slug dir
  while IFS=$'\t' read -r slug dir; do
    [[ ${(L)slug} == ${(L)1} && -d $dir ]] && { REPLY=$dir; return 0 }
  done < $CLONES_FILE
  return 1
}

# list_files SLUG BRANCH → FILES array; TRUNCATED=1 if GitHub cut the tree.
typeset -ga FILES=()
typeset -gi TRUNCATED=0
list_files() {
  FILES=() TRUNCATED=0
  if clone_of "$1"; then
    FILES=(${(f)"$(git -C "$REPLY" ls-files 2>/dev/null)"})
    (( $#FILES )) && return 0
  fi
  [[ -d $TREES_DIR ]] || mkdir -p -m 700 -- $TREES_DIR
  local f="$TREES_DIR/${1/\//__}.txt"
  if ! age_of $f || (( REPLY >= TREE_TTL )); then
    local out rc
    out=$(gh_tree "$1" "$2"); rc=$?
    (( rc == 1 )) && return 1
    print -r -- $out | atomic_write $f
    if (( rc == 2 )); then touch -- $f.truncated; else rm -f -- $f.truncated; fi
  fi
  FILES=(${(f)"$(<$f)"})
  [[ -e $f.truncated ]] && TRUNCATED=1
  return 0
}

# fscore PATH QUERY(lowercase, glob-quoted) → REPLY; 1 = no match.
fscore() {
  local p=${(L)1} q=$2 b=${(L)1:t}
  if   [[ $p == $q || $b == $q ]]; then REPLY=0
  elif [[ $b == ${q}* ]];          then REPLY=1
  elif [[ $b == *${q}* ]];         then REPLY=2
  elif [[ $p == *${q}* ]];         then REPLY=3
  else
    local pat=${(j:*:)${(s::)q}}
    [[ $p == *${~pat}* ]] || return 1
    REPLY=4
  fi
}

files_mode() {  # SLUG PATHQUERY
  local slug=$1 raw=${2%%[[:space:]]#}
  if ! valid_slug "$slug"; then
    item "Not a valid owner/repo: $slug" "Use letters, digits, . _ - only, like TailorBrands/canon" "" false warning
    return
  fi
  local branch
  if ! branch_of "$slug" || ! { branch=$REPLY; list_files "$slug" "$branch" }; then
    item "Couldn’t read $slug" "Check the name, and that gh can see it (gh repo view $slug)" "" false warning
    return
  fi
  local q=${(b)${(L)raw}} p
  local -a ranked=()
  for p in $FILES; do
    [[ -n $p ]] || continue
    if [[ -z $q ]]; then ranked+=("9"$'\t'"$p"); continue; fi
    fscore "$p" "$q" || continue
    ranked+=("$REPLY"$'\t'"$(( 10000 + ${#p} ))"$'\t'"$p")
  done
  [[ -n $q ]] && ranked=(${(o)ranked})
  local r url base="https://github.com/$slug/blob/$(urlencode_path "$branch")/"
  for r in ${ranked[1,MAX_FILES]}; do
    p=${r##*$'\t'}
    url="$base$(urlencode_path "$p")"
    item "$p" "$slug@$branch · ↩ open on GitHub · ⌃ copy URL" "$url" true file ctrl="$url" ac="$slug /$p" uid="$slug/$p"
  done
  (( $#ITEMS )) || item "No file matches “$raw”" "in $slug@$branch" "" false info
  (( TRUNCATED )) && item "Tree truncated by GitHub: clone it under $CFG_CODE_DIR for the full list" \
    "Very large repo; only part of its files are listed" "" false info
}
