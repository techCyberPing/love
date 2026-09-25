#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || {
    echo "Run this script inside the project repository." >&2
    exit 1
  }
cd "$ROOT"

echo "Repository: $ROOT"
echo "Current HEAD:"
git status --short --branch
echo

echo "Lab branches:"
git branch --verbose --verbose --list 'lab/*'
echo

echo "Practice remote refs:"
git for-each-ref \
  --format='%(refname:short) %(objectname:short) %(subject)' \
  refs/remotes/rebase-origin/ 2>/dev/null || true
echo

echo "Saved starting tips:"
git for-each-ref \
  --format='%(refname:short) %(objectname:short) %(subject)' \
  refs/rebase-lab/ 2>/dev/null || true
echo

echo "Branch graph:"
git log \
  --graph \
  --oneline \
  --decorate \
  --all \
  -35
echo

echo "Current rebase status:"
if [[ -d "$(git rev-parse --absolute-git-dir)/rebase-merge" || \
      -d "$(git rev-parse --absolute-git-dir)/rebase-apply" ]]; then
  git status
  echo
  echo "Conflicted files:"
  git diff --name-only --diff-filter=U
else
  echo "No rebase in progress."
fi
