#!/bin/bash
# Quickcast fork: applies the Tinycast→Quickcast rename to a checked-out upstream tree.
# Usage: Scripts/rename-upstream-tree.sh <worktree>. See CLAUDE.md › Merging upstream.
set -euo pipefail
cd "$1"
rm -rf Tinycast.xcodeproj
for word in Tinycast tinycast; do
    find . -path ./.git -prune -o -depth -name "*$word*" -print | while read -r p; do
        d=$(dirname "$p"); b=$(basename "$p")
        [ "$word" = Tinycast ] && mv "$p" "$d/${b//Tinycast/Quickcast}" || mv "$p" "$d/${b//tinycast/quickcast}"
    done
done
find . -path ./.git -prune -o -type f -print0 | xargs -0 grep -Il -i tinycast 2>/dev/null | while read -r f; do
    perl -pi -e '
        s#com\.abueammar\.tinycast#com.vuhpquang.quickcast#g;
        s#com\.tinycast\.app#com.vuhpquang.quickcast#g;
        s#com\.tinycast\b#com.vuhpquang.quickcast#g;
        s#tinycast\.dev#\x00TCDEV\x00#g;
        s#abue-ammar/tinycast#\x00TCGH\x00#g;
        s#Tinycast#Quickcast#g; s#tinycast#quickcast#g; s#TINYCAST#QUICKCAST#g;
        s#\x00TCDEV\x00#tinycast.dev#g; s#\x00TCGH\x00#abue-ammar/tinycast#g;
    ' "$f"
done
