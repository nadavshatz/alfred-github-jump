#!/usr/bin/env python3
"""Regenerate workflow/info.plist (dev-only, stdlib only).

Object graph:
  Script Filter search.sh ──↩ / ⌘↩ / ⌥↩──▶ Run Script open.sh ──▶ Notification
                          ──⌃↩──────────▶ Copy to Clipboard
"""
import plistlib
from pathlib import Path

VERSION = "1.0.0"
CMD, ALT, CTRL = 1048576, 524288, 262144
U = lambda n: f"9C3B6E00-{n:04d}-4000-8000-{n:012d}"
SF, RUN, NOTE, CLIP = (U(i) for i in range(1, 5))

README = """GitHub Jump — open any of your GitHub repos, their Actions, pull requests or a file.

  gh <name>                 fuzzy-match your repos and your orgs' repos
      ↩ homepage · ⌘↩ Actions · ⌥↩ pull requests · ⌃↩ copy URL
  gh owner/repo /path       find a file (local clone if you have one, else GitHub)
  gh > refresh              rebuild the repo list now

Uses your existing GitHub CLI login (`gh auth login`). The workflow never sees,
stores or logs a token: it only runs a fixed set of read-only `gh` commands,
with every repo name validated first.

Source & docs: https://github.com/nadavshatz/alfred-github-jump"""

objects = [
    {"type": "alfred.workflow.input.scriptfilter", "uid": SF, "version": 3, "config": {
        "alfredfiltersresults": False, "alfredfiltersresultsmatchmode": 0,
        "argumenttreatemptyqueryasnil": True, "argumenttrimmode": 0, "argumenttype": 1,
        "escaping": 102, "keyword": "{var:keyword}", "queuedelaycustom": 3,
        "queuedelayimmediatelyinitially": True, "queuedelaymode": 0, "queuemode": 1,
        "runningsubtext": "Searching repos…", "script": "", "scriptargtype": 1,
        "scriptfile": "search.sh", "subtext": "Open a repo, its Actions, pull requests or a file",
        "title": "GitHub Jump", "type": 8, "withspace": True}},
    {"type": "alfred.workflow.action.script", "uid": RUN, "version": 2, "config": {
        "concurrently": False, "escaping": 102, "script": "", "scriptargtype": 1,
        "scriptfile": "open.sh", "type": 8}},
    {"type": "alfred.workflow.output.notification", "uid": NOTE, "version": 1, "config": {
        "lastpathcomponent": False, "onlyshowifquerypopulated": True,
        "removeextension": False, "text": "{query}", "title": "GitHub Jump"}},
    {"type": "alfred.workflow.output.clipboard", "uid": CLIP, "version": 3, "config": {
        "autopaste": False, "clipboardtext": "{query}",
        "ignoredynamicplaceholders": False, "transient": False}},
]


def link(dst, mods=0, sub=""):
    return {"destinationuid": dst, "modifiers": mods, "modifiersubtext": sub, "vitoclose": False}


connections = {
    SF: [link(RUN), link(RUN, CMD, "Open Actions"), link(RUN, ALT, "Open pull requests"),
         link(CLIP, CTRL, "Copy URL")],
    RUN: [link(NOTE)],
}


def textfield(var, label, default, desc, required=True):
    return {"type": "textfield", "variable": var, "label": label, "description": desc,
            "config": {"default": default, "placeholder": default, "required": required, "trim": True}}


user_config = [
    textfield("keyword", "Keyword", "gh", ""),
    textfield("orgs", "Organizations", "TailorBrands",
              "Comma-separated. Your own repos are always included.", required=False),
    textfield("code_dir", "Local clones", "~/code",
              "Folder whose git clones are used for file search (no network needed for those)."),
    textfield("gh_path", "GitHub CLI", "/opt/homebrew/bin/gh",
              "Absolute path to gh. Log in once with `gh auth login`."),
    {"type": "popupbutton", "variable": "update_mode", "label": "Updates",
     "description": "Checks GitHub Releases once a day. Installing always goes through Alfred's own update prompt.",
     "config": {"default": "notify", "pairs": [["Tell me in Alfred", "notify"],
                                              ["Download and open automatically", "auto"],
                                              ["Never check", "off"]]}},
]

pos = {SF: (40, 120), RUN: (300, 60), NOTE: (520, 60), CLIP: (300, 220)}

plist = {
    "bundleid": "io.github.nadavshatz.github-jump",
    "category": "Productivity",
    "connections": connections,
    "createdby": "Nadav Shatz",
    "description": "Open GitHub repos, Actions, pull requests and files via the gh CLI",
    "disabled": False,
    "name": "GitHub Jump",
    "objects": objects,
    "readme": README,
    "uidata": {u: {"xpos": x, "ypos": y} for u, (x, y) in pos.items()},
    "userconfigurationconfig": user_config,
    "version": VERSION,
    "webaddress": "https://github.com/nadavshatz/alfred-github-jump",
}

out = Path(__file__).resolve().parent.parent / "workflow" / "info.plist"
out.write_bytes(plistlib.dumps(plist, sort_keys=True))
print(f"wrote {out}")
