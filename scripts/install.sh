#!/bin/bash
# Installs build/mdreview.app into /Applications, links the CLI onto PATH and copies the agent skill.
# No sudo; rerunnable. Run `make app` first (`make install` does).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d build/mdreview.app ] || { echo "install: build/mdreview.app is missing; run make app" >&2; exit 1; }

# ditto into a clean destination so a rerun replaces the app instead of merging into the old one.
rm -rf /Applications/mdreview.app
ditto build/mdreview.app /Applications/mdreview.app

if bin=$(brew --prefix 2>/dev/null)/bin && [ -w "$bin" ]; then :; else bin=$HOME/.local/bin; fi
mkdir -p "$bin"
ln -sf /Applications/mdreview.app/Contents/Resources/mdreview "$bin/mdreview"

mkdir -p ~/.claude/skills/mdreview
ditto skills/mdreview ~/.claude/skills/mdreview

echo "Installed /Applications/mdreview.app, $bin/mdreview and ~/.claude/skills/mdreview"
case ":$PATH:" in *":$bin:"*) ;; *) echo "Add $bin to your PATH: export PATH=\"$bin:\$PATH\"" ;; esac
