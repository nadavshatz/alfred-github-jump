# lib/gh.zsh — the only place GitHub Jump talks to GitHub.
#
# Everything goes through the user's own `gh` CLI, which reads its token from
# the macOS Keychain; this workflow never sees, stores or logs a token.
# Only the read-only invocations below exist, and every user-derived value is
# validated before it is placed in an argument (never as a flag).

unset GH_DEBUG GH_TOKEN GITHUB_TOKEN GH_HOST GH_REPO 2>/dev/null
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 NO_COLOR=1

typeset -r GH_BIN="${gh_path:-/opt/homebrew/bin/gh}"

_gh() {
  [[ $GH_BIN == /* && -x $GH_BIN ]] || return 127
  $GH_BIN "$@"
}

# gh_ok: binary present (absolute path) and logged in.
gh_ok() { _gh auth status >/dev/null 2>&1 }

# gh_login → REPLY=the signed-in user's login.
gh_login() {
  REPLY=
  local l
  l=$(_gh api -X GET user --jq .login 2>/dev/null) || return 1
  valid_org "$l" || return 1
  REPLY=$l
}

# gh_repos ORG → TSV "slug<TAB>default branch<TAB>description" per repo.
gh_repos() {
  valid_org "${1:-}" || return 1
  _gh repo list "$1" --limit 2000 --no-archived \
    --json nameWithOwner,defaultBranchRef,description \
    --jq '.[] | [.nameWithOwner, (.defaultBranchRef.name // ""), ((.description // "") | gsub("[\t\n\r]"; " "))] | @tsv'
}

# gh_default_branch SLUG → REPLY=default branch.
gh_default_branch() {
  REPLY=
  valid_slug "${1:-}" || return 1
  local b
  b=$(_gh api -X GET "repos/$1" --jq .default_branch 2>/dev/null) || return 1
  [[ -n $b && $b != -* ]] || return 1
  REPLY=$b
}

# gh_tree SLUG BRANCH → file paths, one per line. Returns 2 when GitHub
# truncated the tree (very large repos), 1 on failure.
gh_tree() {
  valid_slug "${1:-}" || return 1
  [[ -n ${2:-} && $2 != -* && $2 != *..* ]] || return 1
  local out first
  out=$(_gh api -X GET "repos/$1/git/trees/$(urlencode_path "$2")?recursive=1" \
          --jq '"truncated=\(.truncated)", (.tree[] | select(.type == "blob") | .path)' 2>/dev/null) || return 1
  first=${out%%$'\n'*}
  [[ $out == *$'\n'* ]] && print -r -- ${out#*$'\n'}
  [[ $first == truncated=true ]] && return 2
  return 0
}
