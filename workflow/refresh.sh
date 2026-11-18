#!/bin/zsh -f
# refresh.sh — rebuild the repo list (and the local clone index) in the cache.
#
# Lists the signed-in user's repos plus every configured org with `gh repo
# list`. An org that fails (SSO not authorised, typo) is recorded in the
# errors file; the others are still written. Runs in the background from the
# Script Filter, or on demand via "gh > refresh".

source "${0:A:h}/lib/common.zsh"
source $GJ_WF_DIR/lib/gh.zsh

touch -- $REFRESH_MARK
gh_ok || exit 1

local -a owners=() failed=()
gh_login && owners+=($REPLY)
for o in ${(s:,:)CFG_ORGS}; do
  o=${${o##[[:space:]]#}%%[[:space:]]#}
  [[ -n $o ]] || continue
  if valid_org "$o"; then owners+=($o); else failed+=($o); fi
done
owners=(${(u)owners})

tmp=$REPOS_FILE.build.$$
: > $tmp
for o in $owners; do
  gh_repos $o >> $tmp 2>/dev/null || failed+=($o)
done
if [[ -s $tmp ]]; then
  sort -u -t $'\t' -k1,1 -- $tmp | atomic_write $REPOS_FILE
fi
rm -f -- $tmp

if (( $#failed )); then print -rl -- $failed | atomic_write $ERRORS_FILE
else rm -f -- $ERRORS_FILE; fi

# Local clones: map origin remotes under the code dir to their checkout path.
local -a clones=()
local d url slug
for d in $CFG_CODE_DIR/*(N/); do
  [[ -e $d/.git ]] || continue
  url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
  case $url in
    git@github.com:*)      slug=${url#git@github.com:} ;;
    ssh://git@github.com/*) slug=${url#ssh://git@github.com/} ;;
    https://github.com/*)  slug=${url#https://github.com/} ;;
    *) continue ;;
  esac
  slug=${${slug%/}%.git}
  valid_slug "$slug" && clones+=("$slug"$'\t'"$d")
done
print -rl -- $clones | atomic_write $CLONES_FILE
rm -f -- $REFRESH_MARK
exit 0
