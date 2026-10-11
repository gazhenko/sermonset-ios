#!/bin/zsh
# Publishes site/ to the gh-pages branch (GitHub Pages serves it at /sower/).
# Usage: tools/site/publish.sh "message"
set -euo pipefail
cd "${0:A:h}/../.."
MSG=${1:-"Update site"}
WT=build/gh-pages
git fetch origin gh-pages 2>/dev/null || true
if [ ! -d "$WT/.git" ] && [ ! -f "$WT/.git" ]; then
  if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
    git worktree add -B gh-pages "$WT" origin/gh-pages
  else
    git worktree add --detach "$WT"
    (cd "$WT" && git checkout --orphan gh-pages && git rm -rfq . )
  fi
fi
rsync -a --delete --exclude .git site/ "$WT/"
cd "$WT"
git add -A
if git diff --cached --quiet; then echo "No site changes."; exit 0; fi
git commit -qm "$MSG" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin gh-pages
