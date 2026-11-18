#!/bin/zsh -f
# GitHub Jump test-suite. Runs on macOS or Linux with zsh + jq + git; gh, curl
# and open are mocked (tests/mocks) and nothing touches the network.
#
#   zsh tests/run_tests.sh

setopt extended_glob no_unset
ROOT=${0:A:h:h}
WF=$ROOT/workflow
SANDBOX=$(mktemp -d)
trap 'rm -rf $SANDBOX' EXIT

export MOCK_DIR=$SANDBOX/mock
export gh_path=$ROOT/tests/mocks/gh GJ_CURL=$ROOT/tests/mocks/curl GJ_OPEN=$ROOT/tests/mocks/open
export alfred_workflow_cache=$SANDBOX/cache alfred_workflow_data=$SANDBOX/data
export alfred_workflow_version=1.0.0 update_mode=off orgs=TailorBrands code_dir=$SANDBOX/code
mkdir -p $MOCK_DIR $code_dir

integer pass=0 fail=0
ok()   { print -P "%F{green}✔%f $1"; (( ++pass )) }
bad()  { print -P "%F{red}✘ $1%f"; [[ -n ${2:-} ]] && print -r -- "   $2"; (( ++fail )) }
check() { local d=$1; shift; if "$@"; then ok $d; else bad $d; fi }
wait_for() { integer i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.1; done; return 1 }
reset_all() { rm -rf $MOCK_DIR $alfred_workflow_cache; mkdir -p $MOCK_DIR }
ghlog() { cat $MOCK_DIR/gh.log 2>/dev/null }
fixtures() {
  print -r -- $'TailorBrands/canon\tmaster\tGitOps repo' > $MOCK_DIR/repos_TailorBrands
  print -r -- $'TailorBrands/canon-tools\tmain\t' >> $MOCK_DIR/repos_TailorBrands
  print -r -- $'TailorBrands/papel\tmaster\tMarketing sites' >> $MOCK_DIR/repos_TailorBrands
  print -r -- $'nadavshatz/insomniac\tmain\tAlfred mac no-sleep workflow' > $MOCK_DIR/repos_nadavshatz
  print nadavshatz > $MOCK_DIR/login
}
lib() { ( source $WF/lib/common.zsh; source $WF/lib/gh.zsh; "$@" ) }

# --- unit: helpers -------------------------------------------------------------
check "js escapes" eval '[[ $(lib js "a\"b\\c") == "\"a\\\"b\\\\c\"" ]]'
for s in TailorBrands/canon nadavshatz/alfred-netinfo a.b/c_d-e; do
  check "valid_slug accepts $s" lib valid_slug $s
done
for s in '-R/x' 'a/../b' '../x' 'a/.' 'a/b;rm' 'a/b c' 'a' 'a/b/c' '--jq/x' ''; do
  check "valid_slug rejects '$s'" eval '! lib valid_slug "$s"'
done
check "valid_org accepts TailorBrands" lib valid_org TailorBrands
for s in '-R' 'a b' 'a/b' '' 'a;b'; do check "valid_org rejects '$s'" eval '! lib valid_org "$s"'; done
check "urlencode_path keeps slashes, encodes space # % ?" \
  eval '[[ $(lib urlencode_path "docs/my file#1%?.md") == "docs/my%20file%231%25%3F.md" ]]'
out=$(lib eval 'item T S https://github.com/a/b true repo cmd=https://github.com/a/b/actions alt=https://github.com/a/b/pulls ctrl=https://github.com/a/b ac="a/b " uid=a/b; emit')
check "item with mods emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
check "item mods: cmd/alt/ctrl args" \
  eval '[[ $(print -r -- $out | jq -r ".items[0].mods | [.cmd.arg,.alt.arg,.ctrl.arg] | @tsv") == "https://github.com/a/b/actions	https://github.com/a/b/pulls	https://github.com/a/b" ]]'
check "item autocomplete + uid" eval '[[ $(print -r -- $out | jq -r ".items[0] | [.autocomplete,.uid] | @tsv") == "a/b 	a/b" ]]'

# --- unit: gh wrapper allowlist ------------------------------------------------
reset_all; fixtures
lib gh_repos TailorBrands > $SANDBOX/r.out
check "gh_repos argv is exactly the allowlisted form" \
  eval '[[ ${(j:|:)${(f)"$(ghlog)"}} == "repo|list|TailorBrands|--limit|2000|--no-archived|--json|nameWithOwner,defaultBranchRef,description|--jq|"*"|--" ]]'
check "gh_repos returns TSV" eval '[[ $(head -1 $SANDBOX/r.out) == $'"'"'TailorBrands/canon\tmaster\tGitOps repo'"'"' ]]'
reset_all
check "gh_repos refuses '-R' without calling gh" eval '! lib gh_repos -R && [[ -z $(ghlog) ]]'
check "gh_repos refuses 'a b' without calling gh" eval '! lib gh_repos "a b" && [[ -z $(ghlog) ]]'
print -l src/a.go README.md > $MOCK_DIR/tree_a__b
lib gh_tree a/b main > $SANDBOX/t.out; rc=$?
check "gh_tree argv" eval '[[ ${(j:|:)${(f)"$(ghlog)"}} == "api|-X|GET|repos/a/b/git/trees/main?recursive=1|--jq|"*"|--" ]]'
check "gh_tree lists paths, rc 0" eval '[[ $rc == 0 && $(<$SANDBOX/t.out) == $'"'"'src/a.go\nREADME.md'"'"' ]]'
touch $MOCK_DIR/tree_a__b.truncated
lib gh_tree a/b main >/dev/null; rc=$?
check "gh_tree truncated → rc 2" eval '[[ $rc == 2 ]]'
reset_all
check "gh_tree refuses ../x" eval '! lib gh_tree ../x main && [[ -z $(ghlog) ]]'
check "gh_tree refuses branch starting with -" eval '! lib gh_tree a/b -x && [[ -z $(ghlog) ]]'
lib gh_tree a/b 'feat/x y' >/dev/null
check "gh_tree percent-encodes the branch" eval '[[ $(ghlog) == *"repos/a/b/git/trees/feat/x%20y?recursive=1"* ]]'
check "gh_ok false for relative gh_path" eval '! gh_path=gh lib gh_ok'
check "gh_ok false when not logged in" eval 'touch $MOCK_DIR/noauth; ! lib gh_ok; rm $MOCK_DIR/noauth'
check "gh_ok true with mock" lib gh_ok
check "GH_DEBUG is unset for gh calls" eval '[[ $(GH_DEBUG=api lib eval "print -r -- \${GH_DEBUG-unset}") == unset ]]'

# --- refresh -------------------------------------------------------------------
reset_all; fixtures
$WF/refresh.sh
R=$alfred_workflow_cache/repos.tsv
check "refresh writes repos for login + orgs" eval '[[ $(cut -f1 $R | LC_ALL=C sort | paste -sd" " -) == "TailorBrands/canon TailorBrands/canon-tools TailorBrands/papel nadavshatz/insomniac" ]]'
check "repos.tsv is mode 600" eval '[[ $(stat -f %Lp $R 2>/dev/null || stat -c %a $R) == 600 ]]'
check "cache dir is mode 700" eval '[[ $(stat -f %Lp $alfred_workflow_cache 2>/dev/null || stat -c %a $alfred_workflow_cache) == 700 ]]'
check "no errors file when all orgs succeed" eval '[[ ! -e $alfred_workflow_cache/errors ]]'
reset_all; fixtures
orgs='TailorBrands,SsoOrg,bad org' $WF/refresh.sh
check "one org failing keeps the others" eval '[[ $(wc -l < $R) -eq 4 ]]'
check "failing and invalid orgs recorded in errors file" eval '[[ $(LC_ALL=C sort $alfred_workflow_cache/errors | tr "\n" "|") == "SsoOrg|bad org|" ]]'
check "invalid org name never reaches gh" eval '[[ $(ghlog) != *"bad org"* ]]'
reset_all; fixtures; touch $MOCK_DIR/noauth
$WF/refresh.sh; rc=$?
check "refresh without auth exits non-zero and writes nothing" eval '[[ $rc != 0 && ! -e $R ]]'

# --- search --------------------------------------------------------------------
search() { $WF/search.sh "${1:-}" }
stitles() { search "${1:-}" | jq -r '.items[].title' }
seed() {  # fresh cache with the fixture repos
  reset_all; fixtures; mkdir -p -m 700 $alfred_workflow_cache
  cat $MOCK_DIR/repos_TailorBrands $MOCK_DIR/repos_nadavshatz > $R
}
seed
out=$(search canon)
check "search emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
check "exact repo name ranks first, prefix next" \
  eval '[[ $(print -r -- $out | jq -r "[.items[].uid] | .[0:2] | join(\" \")") == "TailorBrands/canon TailorBrands/canon-tools" ]]'
check "repo item: ↩ homepage, ⌘ actions, ⌥ pulls, ⌃ copy" \
  eval '[[ $(print -r -- $out | jq -r ".items[0] | [.arg,.mods.cmd.arg,.mods.alt.arg,.mods.ctrl.arg] | @tsv") == "https://github.com/TailorBrands/canon	https://github.com/TailorBrands/canon/actions	https://github.com/TailorBrands/canon/pulls	https://github.com/TailorBrands/canon" ]]'
check "repo item shows description" eval '[[ $(print -r -- $out | jq -r ".items[0].subtitle") == "GitOps repo"* ]]'
check "repo item autocompletes to 'slug '" eval '[[ $(print -r -- $out | jq -r ".items[0].autocomplete") == "TailorBrands/canon " ]]'
check "subsequence match: 'ins' → insomniac" eval '[[ $(stitles ins | head -1) == "nadavshatz/insomniac" ]]'
check "case-insensitive: 'PAPEL'" eval '[[ $(stitles PAPEL | head -1) == "TailorBrands/papel" ]]'
check "owner match: 'nadav' → insomniac" eval '[[ $(stitles nadav | head -1) == "nadavshatz/insomniac" ]]'
check "no match → 'No repo matches' item" eval '[[ $(stitles zzzqqq) == "No repo matches “zzzqqq”"* ]]'
check "empty query lists repos" eval '(( $(search | jq ".items|length") >= 4 ))'
check "typed slug not in cache is still offered" \
  eval '[[ $(search other/thing | jq -r ".items[0] | [.title,.arg] | @tsv") == "other/thing	https://github.com/other/thing" ]]'
rm -f $MOCK_DIR/gh.log
for q in '-R x' 'a/b;rm' '--jq .' '../../etc' '$(id)' '`id`'; do search "$q" | jq -e . >/dev/null || bad "invalid JSON for '$q'"; done
check "hostile queries never reach gh" eval '[[ -z $(ghlog) ]]'
check "'> refresh' offers a refresh item" eval '[[ $(search "> refresh" | jq -r ".items[0] | [.title,.arg] | @tsv") == "Refresh repo list	refresh" ]]'
print SsoOrg > $alfred_workflow_cache/errors
check "orgs that failed are reported" eval '[[ $(stitles) == *"Couldn’t list SsoOrg (SSO not authorised for gh?)"* ]]'
rm $alfred_workflow_cache/errors

# first run: no cache
reset_all; fixtures
out=$(search canon)
check "no cache → 'Building repo list…' and rerun" \
  eval '[[ $(print -r -- $out | jq -r ".items[0].title") == "Building repo list…" && $(print -r -- $out | jq -r .rerun) == 0.5 ]]'
search canon >/dev/null
check "background refresh builds the cache" wait_for '[[ -s $R ]]'
check "only one refresh started for rapid keystrokes" eval '[[ $(grep -cx TailorBrands $MOCK_DIR/gh.log) == 1 ]]'
check "after refresh, results appear" eval '[[ $(stitles canon | head -1) == TailorBrands/canon ]]'

# stale cache → served, refreshed in background
seed; touch -t 202001010000 $R; rm -f $MOCK_DIR/gh.log
check "stale cache still answers" eval '[[ $(stitles canon | head -1) == TailorBrands/canon ]]'
check "stale cache triggers a refresh" wait_for '[[ $(ghlog) == *TailorBrands* ]]'

# gh not ready
reset_all; touch $MOCK_DIR/noauth
check "not logged in → explains gh auth login" eval '[[ $(stitles canon | head -1) == "GitHub CLI not ready: run gh auth login" ]]'
reset_all
check "missing gh binary → same explanation" eval '[[ $(gh_path=/nonexistent/gh stitles canon | head -1) == "GitHub CLI not ready: run gh auth login" ]]'

# --- open.sh -------------------------------------------------------------------
reset_all
act() { $WF/open.sh "$1" }
act https://github.com/TailorBrands/canon/actions >/dev/null
check "open.sh opens github URLs" eval '[[ $(<$MOCK_DIR/open.log) == "https://github.com/TailorBrands/canon/actions" ]]'
rm -f $MOCK_DIR/open.log
for u in file:///etc/passwd 'https://github.com.evil.com/x' 'http://github.com/a' '-a Calculator' 'https://github.com/a b'; do
  act "$u" >/dev/null 2>&1 && bad "open.sh accepted '$u'"
done
check "open.sh refuses non-github / malformed URLs" eval '[[ ! -e $MOCK_DIR/open.log ]]'
reset_all; fixtures
check "open.sh refresh rebuilds and reports" eval '[[ $(act refresh) == "Repo list refreshed: 4 repos" && -s $R ]]'

# --- file mode -----------------------------------------------------------------
seed
CL=$code_dir/canon
mkdir -p $CL/prod/app $CL/docs
git -C $CL init -q && git -C $CL remote add origin git@github.com:TailorBrands/canon.git
touch $CL/prod/app/values.yaml $CL/docs/'my file#1.md' $CL/README.md
git -C $CL add -A && git -C $CL -c user.email=t@t -c user.name=t commit -q -m init
print -r -- $'TailorBrands/canon\t'$CL > $alfred_workflow_cache/clones.tsv
rm -f $MOCK_DIR/gh.log
out=$(search 'TailorBrands/canon /values')
check "file mode emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
check "local clone file found, blob URL on default branch" \
  eval '[[ $(print -r -- $out | jq -r ".items[0] | [.title,.arg] | @tsv") == "prod/app/values.yaml	https://github.com/TailorBrands/canon/blob/master/prod/app/values.yaml" ]]'
check "local clone needs no gh call" eval '[[ -z $(ghlog) ]]'
check "file item ⌃ copies the URL" eval '[[ $(print -r -- $out | jq -r ".items[0].mods.ctrl.arg") == "https://github.com/TailorBrands/canon/blob/master/prod/app/values.yaml" ]]'
check "path with space and # is URL-encoded" \
  eval '[[ $(search "TailorBrands/canon /my file" | jq -r ".items[0].arg") == "https://github.com/TailorBrands/canon/blob/master/docs/my%20file%231.md" ]]'
check "file mode is case-insensitive" eval '[[ $(search "TailorBrands/canon /READ" | jq -r ".items[0].title") == README.md ]]'

# uncloned repo → GitHub tree (cached)
print -l src/main.go src/values.go > $MOCK_DIR/tree_TailorBrands__papel
out=$(search 'TailorBrands/papel /values')
check "uncloned repo uses the tree API" eval '[[ $(print -r -- $out | jq -r ".items[0].arg") == "https://github.com/TailorBrands/papel/blob/master/src/values.go" ]]'
search 'TailorBrands/papel /main' >/dev/null
check "tree is cached (one API call for two queries)" eval '[[ $(grep -c "git/trees" $MOCK_DIR/gh.log) == 1 ]]'
check "tree cache file is mode 600" eval '[[ $(stat -f %Lp $alfred_workflow_cache/trees/TailorBrands__papel.txt 2>/dev/null || stat -c %a $alfred_workflow_cache/trees/TailorBrands__papel.txt) == 600 ]]'
touch $MOCK_DIR/tree_TailorBrands__papel.truncated; rm -rf $alfred_workflow_cache/trees
check "truncated tree adds an info item" eval '[[ $(stitles "TailorBrands/papel /") == *"Tree truncated by GitHub: clone it under "* ]]'

# repo not in the cache → default branch looked up
print -l lib/x.rb > $MOCK_DIR/tree_other__thing; print develop > $MOCK_DIR/branch_other__thing
check "unknown repo: default branch looked up via gh" \
  eval '[[ $(search "other/thing /x" | jq -r ".items[0].arg") == "https://github.com/other/thing/blob/develop/lib/x.rb" ]]'
check "unreachable repo → warning" eval '[[ $(stitles "nope/nope /x") == "Couldn’t read nope/nope"* ]]'
rm -f $MOCK_DIR/gh.log
check "invalid slug in file mode → no gh call" \
  eval '[[ $(stitles "a/../b /x") == "Not a valid owner/repo: a/../b" && -z $(ghlog) ]]'
check "no matching file → info item" eval '[[ $(stitles "TailorBrands/canon /zzzz") == "No file matches “zzzz”"* ]]'

print "\n$pass passed, $fail failed"
(( fail == 0 ))
