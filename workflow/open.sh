#!/bin/zsh -f
# open.sh — Run Script action for GitHub Jump. Prints one line for Alfred's
# notification (empty for a plain open, so no notification is shown).
#
#   open.sh https://github.com/…        open in the default browser
#   open.sh refresh                      rebuild the repo cache now
#   open.sh "update_check [now]" | "update_install X.Y.Z"

source "${0:A:h}/lib/common.zsh"
typeset -r OPEN="${GJ_OPEN:-/usr/bin/open}"
arg=${1:-}

case $arg in
  refresh)
    if $GJ_WF_DIR/refresh.sh; then
      integer n=0
      [[ -r $REPOS_FILE ]] && n=${#${(f)"$(<$REPOS_FILE)"}}
      print "Repo list refreshed: $n repos"
      [[ -s $ERRORS_FILE ]] && print "Couldn’t list: ${(j:, :)${(f)"$(<$ERRORS_FILE)"}}"
    else
      print "Refresh failed: is gh installed and logged in? (gh auth login)"
    fi
    ;;
  update_check*|update_install*)
    source $GJ_WF_DIR/lib/update.zsh
    set -- ${(z)arg}
    case $1 in
      update_check)   update_cmd_check ${2:-} ;;
      update_install) update_cmd_install ${2:-} ;;
    esac
    ;;
  *)
    # Only https://github.com/<path>, with no whitespace or control characters.
    [[ $arg == https://github.com/[^[:space:][:cntrl:]]# ]] || { print "Refusing to open: not a github.com URL"; exit 1 }
    $OPEN "$arg"   # validated above: cannot start with "-"
    ;;
esac
