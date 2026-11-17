#!/bin/bash
# Fails when the README drifts from the tree: the make-target table versus the Makefile,
# Layout paths that don't exist, and Sources/ directories that Layout doesn't mention.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
problem() { echo "docs-check: $*" >&2; fail=1; }

makefile_targets=$(grep -E '^[a-z][a-z-]*:' Makefile | cut -d: -f1 | sort -u)
readme_targets=$(grep -oE '^\| `make [a-z][a-z-]*' README.md | cut -c9- | sort -u)
for target in $(comm -23 <(echo "$makefile_targets") <(echo "$readme_targets")); do
    problem "make $target is missing from the README table"
done
for target in $(comm -13 <(echo "$makefile_targets") <(echo "$readme_targets")); do
    problem "the README table lists make $target, which the Makefile doesn't define"
done

# Each Layout bullet resolves its paths against the directory of its parent bullet. A bullet that
# starts with `dir/` becomes the base for its own later names and for its children.
layout=$(awk '/^## Layout/ { on = 1; next } /^## / { on = 0 } on' README.md)
mentioned=""
parent=""
while IFS= read -r line; do
    [[ $line =~ ^(\ *)-\  ]] || continue
    indent=${BASH_REMATCH[1]}
    [ -z "$indent" ] && parent=""
    base=$parent
    first=1
    for token in $(grep -oE '`[^`]+`' <<<"$line" | tr -d '`'); do
        if [[ $first == 1 && $token == */ ]]; then
            first=0
            base=$parent$token
            [ -z "$indent" ] && parent=$base
            [ -e "$base" ] || problem "README Layout names $base, which doesn't exist"
            mentioned="$mentioned ${base%/}"
            continue
        fi
        first=0
        [[ $token == */* || $token =~ \.(swift|yml|md|sh)$ ]] || continue
        [ -e "$base$token" ] || [ -e "$token" ] || problem "README Layout names $token, which doesn't exist"
    done
done <<<"$layout"

for dir in $(find Sources -mindepth 1 -type d); do
    [[ " $mentioned " == *" $dir "* ]] || problem "README Layout doesn't mention $dir/"
done

exit $fail
