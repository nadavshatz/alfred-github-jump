# GitHub Jump for Alfred

Open any of your GitHub repos, their Actions, pull requests or a file, using
your existing GitHub CLI login.

| Type | Does |
|---|---|
| `gh canon` | fuzzy-match your repos and your orgs' repos |
| ↩ / ⌘↩ / ⌥↩ / ⌃↩ | homepage / Actions / pull requests / copy URL |
| `gh owner/repo /values` | find a file: local clone under `~/code` if present, else GitHub |
| `gh > refresh` | rebuild the repo list now (it also refreshes itself daily) |

## Setup

`gh auth login` once (Homebrew `gh`). Set your orgs (default `TailorBrands`),
clone folder and `gh` path in **Configure Workflow…**.

## Security

- The workflow never holds a GitHub token. `gh` reads its own token from the
  macOS Keychain; nothing is written to disk but repo names, default branches,
  descriptions and file paths.
- Only these `gh` calls exist: `auth status`, `api -X GET user`,
  `repo list <org>`, `api -X GET repos/<owner>/<repo>` and
  `api -X GET repos/<owner>/<repo>/git/trees/<branch>`. All are read-only.
- Anything you type is validated (`owner/repo` = `[A-Za-z0-9._-]`, no `.`/`..`
  parts, no leading `-`) before it is placed in an argument, never as a flag.
  `gh` must be an absolute path.
- The cache lives in Alfred's cache folder (dir `700`, files `600`).
- Only `https://github.com/…` URLs are ever opened.
- Updates come from this repo's GitHub Releases and are checked against the
  release's SHA-256, bundle id and version before Alfred is asked to install.

## Development

```sh
zsh tests/run_tests.sh       # mocked test-suite (zsh + jq + git)
zsh tests/build_test.sh      # packaging test
zsh scripts/build.sh         # dist/GitHub-Jump-<version>.alfredworkflow
python3 scripts/make_plist.py && swift scripts/make_icons.swift   # regenerate
```
