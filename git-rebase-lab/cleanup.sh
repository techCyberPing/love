#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="rebase-origin"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || {
    echo "Run this script inside the project repository." >&2
    exit 1
  }
cd "$ROOT"

GIT_DIR="$(git rev-parse --absolute-git-dir)"
META_DIR="$GIT_DIR/rebase-lab"
REMOTE_REPO="$META_DIR/origin.git"
STATE_FILE="$META_DIR/state"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Tracked files or the index have changes; commit or stash them first." >&2
  exit 1
fi

for state_dir in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ -e "$GIT_DIR/$state_dir" ]]; then
    echo "Another Git operation is in progress: $state_dir" >&2
    exit 1
  fi
done

ORIGINAL_BRANCH="master"
if [[ -f "$STATE_FILE" ]]; then
  saved_branch="$(sed -n 's/^original_branch=//p' "$STATE_FILE")"
  if [[ -n "$saved_branch" ]] && \
    git show-ref --verify --quiet "refs/heads/$saved_branch"; then
    ORIGINAL_BRANCH="$saved_branch"
  fi
fi

git checkout --quiet "$ORIGINAL_BRANCH"

while IFS= read -r branch; do
  [[ -n "$branch" ]] || continue
  git branch -D "$branch" >/dev/null
done < <(git for-each-ref --format='%(refname:short)' refs/heads/lab/)

git remote remove "$REMOTE_NAME" 2>/dev/null || true

while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  git update-ref -d "$ref"
done < <(git for-each-ref --format='%(refname)' refs/rebase-lab/)

rm -rf -- "$REMOTE_REPO" "$META_DIR"

echo "Removed lab branches, refs, and local practice remote."
echo "Restored branch: $ORIGINAL_BRANCH"
