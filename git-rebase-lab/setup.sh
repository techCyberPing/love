#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="rebase-origin"
BASE_BRANCH="master"
LAB_PREFIX="lab"
PRACTICE_DIR="rebase-practice"

die() {
  echo "error: $*" >&2
  exit 1
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "run this script inside the Git working tree"
cd "$ROOT"

GIT_DIR="$(git rev-parse --absolute-git-dir)"
META_DIR="$GIT_DIR/rebase-lab"
REMOTE_REPO="$META_DIR/origin.git"
STATE_FILE="$META_DIR/state"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "tracked files or the index have changes; commit or stash them first"
fi

for state_dir in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ -e "$GIT_DIR/$state_dir" ]]; then
    die "another Git operation is in progress: $state_dir"
  fi
done

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  existing_url="$(git remote get-url "$REMOTE_NAME")"
  if [[ "$existing_url" != "$REMOTE_REPO" ]]; then
    die "remote '$REMOTE_NAME' already exists and is not managed by this lab: $existing_url"
  fi
fi

detect_original_branch() {
  local branch=""
  if [[ -f "$STATE_FILE" ]]; then
    branch="$(sed -n 's/^original_branch=//p' "$STATE_FILE")"
    if [[ -n "$branch" ]] && git show-ref --verify --quiet "refs/heads/$branch"; then
      printf '%s\n' "$branch"
      return
    fi
  fi

  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  if [[ -n "$branch" && "$branch" != "$LAB_PREFIX/"* ]]; then
    printf '%s\n' "$branch"
    return
  fi

  printf '%s\n' "$BASE_BRANCH"
}

ORIGINAL_BRANCH="$(detect_original_branch)"

echo "Returning to original branch: $ORIGINAL_BRANCH"
git checkout --quiet "$ORIGINAL_BRANCH"

delete_lab_branches() {
  local branch
  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    git branch -D "$branch" >/dev/null
  done < <(git for-each-ref \
    --format='%(refname:short)' \
    "refs/heads/$LAB_PREFIX/")
}

echo "Removing previous lab branches and local remote..."
delete_lab_branches
git remote remove "$REMOTE_NAME" 2>/dev/null || true
rm -rf -- "$REMOTE_REPO"
git for-each-ref --format='%(refname)' refs/rebase-lab/ |
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    git update-ref -d "$ref"
  done

mkdir -p "$META_DIR"
printf 'original_branch=%s\nremote=%s\n' \
  "$ORIGINAL_BRANCH" "$REMOTE_REPO" >"$STATE_FILE"

commit() {
  local when="$1"
  shift
  git add -A -- "$PRACTICE_DIR"
  GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" \
    git commit --quiet "$@"
}

write_common_project() {
  cat > "$PRACTICE_DIR/package.json" <<'EOF'
{
  "name": "rebase-practice",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "node tests/run-tests.js"
  }
}
EOF

  cat > "$PRACTICE_DIR/src/pricing.js" <<'EOF'
'use strict';

const DEFAULT_TAX_RATE = 0.08;

function calculatePrice(amount, taxRate = DEFAULT_TAX_RATE) {
  return Number((amount * (1 + taxRate)).toFixed(2));
}

module.exports = { calculatePrice, DEFAULT_TAX_RATE };
EOF

  cat > "$PRACTICE_DIR/src/checkout.js" <<'EOF'
'use strict';

const { calculatePrice } = require('./pricing');

function checkout(amount) {
  return { total: calculatePrice(amount) };
}

module.exports = { checkout };
EOF

  cat > "$PRACTICE_DIR/tests/run-tests.js" <<'EOF'
'use strict';

require('./pricing.test');
require('./checkout.test');

console.log('all tests passed');
EOF

  cat > "$PRACTICE_DIR/tests/pricing.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { calculatePrice } = require('../src/pricing');

assert.equal(calculatePrice(100), 108);
EOF

  cat > "$PRACTICE_DIR/tests/checkout.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { checkout } = require('../src/checkout');

assert.equal(checkout(100).total, 108);
EOF

  cat > "$PRACTICE_DIR/config/defaults.json" <<'EOF'
{
  "currency": "USD",
  "taxRate": 0.08
}
EOF
}

echo "Creating $LAB_PREFIX/main from $BASE_BRANCH..."
git checkout --quiet "$BASE_BRANCH"
git checkout --quiet -b "$LAB_PREFIX/main"

mkdir -p "$PRACTICE_DIR/src" "$PRACTICE_DIR/tests" "$PRACTICE_DIR/config"
write_common_project
commit "2026-01-01T09:00:00+08:00" -m "lab: bootstrap pricing practice"

mkdir -p "$PRACTICE_DIR/ops"
cat > "$PRACTICE_DIR/ops/release.json" <<'EOF'
{
  "service": "pricing",
  "environment": "staging"
}
EOF
commit "2026-01-01T09:05:00+08:00" -m "lab: add release metadata"

git checkout --quiet -b "$LAB_PREFIX/feature/pricing"
cat > "$PRACTICE_DIR/src/pricing.js" <<'EOF'
'use strict';

const DEFAULT_TAX_RATE = 0.08;

function calculatePrice(amount, taxRate = DEFAULT_TAX_RATE, member = false) {
  const membershipDiscount = member ? 0.9 : 1;
  return Number((amount * membershipDiscount * (1 + taxRate)).toFixed(2));
}

module.exports = { calculatePrice, DEFAULT_TAX_RATE };
EOF
cat > "$PRACTICE_DIR/tests/pricing.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { calculatePrice } = require('../src/pricing');

assert.equal(calculatePrice(100), 108);
assert.equal(calculatePrice(100, 0.08, true), 97.2);
EOF
commit "2026-01-02T09:10:00+08:00" -m "lab: add membership discount"

cat > "$PRACTICE_DIR/tests/pricing.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { calculatePrice } = require('../src/pricing');

assert.equal(calculatePrice(100), 108);
assert.equal(calculatePrice(100, 0.08, true), 97.2);
assert.equal(calculatePrice(50, 0.1, true), 49.5);
EOF
commit "2026-01-02T09:12:00+08:00" -m "fixup! lab: add membership discount"

cat > "$PRACTICE_DIR/src/pricing.js" <<'EOF'
'use strict';

const DEFAULT_TAX_RATE = 0.08;

function calculatePrice(amount, taxRate = DEFAULT_TAX_RATE, member = false, coupons = []) {
  const membershipDiscount = member ? 0.9 : 1;
  const couponDiscount = coupons.reduce(
    (discount, couponRate) => discount * (1 - couponRate),
    1,
  );
  return Number(
    (amount * membershipDiscount * couponDiscount * (1 + taxRate)).toFixed(2),
  );
}

module.exports = { calculatePrice, DEFAULT_TAX_RATE };
EOF
cat > "$PRACTICE_DIR/tests/pricing.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { calculatePrice } = require('../src/pricing');

assert.equal(calculatePrice(100), 108);
assert.equal(calculatePrice(100, 0.08, true), 97.2);
assert.equal(calculatePrice(50, 0.1, true), 49.5);
assert.equal(calculatePrice(100, 0.08, false, [0.1, 0.2]), 77.76);
EOF
commit "2026-01-02T09:20:00+08:00" -m "lab: support coupon stacking"

git checkout --quiet "$LAB_PREFIX/main"
cat > "$PRACTICE_DIR/src/pricing.js" <<'EOF'
'use strict';

const DEFAULT_TAX_RATE = 0.08;

function calculatePrice(amount, { taxRate = DEFAULT_TAX_RATE } = {}) {
  return Number((amount * (1 + taxRate)).toFixed(2));
}

module.exports = { calculatePrice, DEFAULT_TAX_RATE };
EOF
cat > "$PRACTICE_DIR/src/checkout.js" <<'EOF'
'use strict';

const { calculatePrice } = require('./pricing');
const defaults = require('../config/defaults.json');

function checkout(amount) {
  return { total: calculatePrice(amount, { taxRate: defaults.taxRate }) };
}

module.exports = { checkout };
EOF
cat > "$PRACTICE_DIR/tests/pricing.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { calculatePrice } = require('../src/pricing');

assert.equal(calculatePrice(100), 108);
assert.equal(calculatePrice(100, { taxRate: 0.1 }), 110);
EOF
commit "2026-01-03T10:00:00+08:00" -m "lab: make tax options explicit"

cat > "$PRACTICE_DIR/config/defaults.json" <<'EOF'
{
  "currency": "USD",
  "taxRate": 0.08,
  "regions": {
    "US": { "currency": "USD", "taxRate": 0.08 },
    "DE": { "currency": "EUR", "taxRate": 0.19 }
  }
}
EOF
cat > "$PRACTICE_DIR/src/reporting.js" <<'EOF'
'use strict';

function summarize(rows) {
  return {
    count: rows.length,
    total: rows.reduce((sum, row) => sum + row.amount, 0),
  };
}

module.exports = { summarize };
EOF
cat > "$PRACTICE_DIR/tests/reporting.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { summarize } = require('../src/reporting');

assert.deepEqual(
  summarize([{ amount: 10 }, { amount: 20 }]),
  { count: 2, total: 30 },
);
EOF
cat > "$PRACTICE_DIR/tests/run-tests.js" <<'EOF'
'use strict';

require('./pricing.test');
require('./checkout.test');
require('./reporting.test');

console.log('all tests passed');
EOF
commit "2026-01-03T10:10:00+08:00" -m "lab: add regional reporting defaults"

cat > "$PRACTICE_DIR/tests/checkout.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { checkout } = require('../src/checkout');

assert.equal(checkout(100).total, 108);
assert.equal(checkout(0).total, 0);
EOF
commit "2026-01-03T10:20:00+08:00" -m "lab: cover checkout edge cases"

MAIN_M4="$(git rev-parse HEAD)"

git checkout --quiet -b "$LAB_PREFIX/feature/reporting" "$MAIN_M4"
cat > "$PRACTICE_DIR/src/reporting.js" <<'EOF'
'use strict';

function summarize(rows) {
  const activeRows = rows.filter((row) => row.active !== false);
  return {
    count: rows.length,
    active: activeRows.length,
    total: rows.reduce((sum, row) => sum + row.amount, 0),
  };
}

module.exports = { summarize };
EOF
cat > "$PRACTICE_DIR/tests/reporting.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { summarize } = require('../src/reporting');

assert.deepEqual(
  summarize([
    { amount: 10, active: true },
    { amount: 20, active: false },
  ]),
  { count: 2, active: 1, total: 30 },
);
EOF
commit "2026-01-04T11:00:00+08:00" -m "lab: report active subscriptions"

git checkout --quiet -b "$LAB_PREFIX/chore/reporting-fixtures"
mkdir -p "$PRACTICE_DIR/tests/fixtures"
cat > "$PRACTICE_DIR/tests/fixtures/reporting.js" <<'EOF'
'use strict';

module.exports = [
  { account: "alpha", amount: 40, active: true },
  { account: "beta", amount: 60, active: false },
];
EOF
commit "2026-01-04T11:05:00+08:00" -m "lab: add shared reporting fixtures"

git checkout --quiet "$LAB_PREFIX/feature/reporting"
GIT_AUTHOR_DATE="2026-01-04T11:10:00+08:00" \
  GIT_COMMITTER_DATE="2026-01-04T11:10:00+08:00" \
  git merge --quiet --no-ff "$LAB_PREFIX/chore/reporting-fixtures" \
    -m "lab: merge reporting fixtures"

cat > "$PRACTICE_DIR/tests/reporting.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const fixtures = require('./fixtures/reporting');
const { summarize } = require('../src/reporting');

assert.deepEqual(summarize(fixtures), {
  count: 2,
  active: 1,
  total: 100,
});
EOF
commit "2026-01-04T11:15:00+08:00" -m "lab: cover reporting fixtures"

git checkout --quiet "$LAB_PREFIX/main"
cat > "$PRACTICE_DIR/src/reporting.js" <<'EOF'
'use strict';

function summarize({ rows = [] } = {}) {
  return {
    count: rows.length,
    total: rows.reduce((sum, row) => sum + row.amount, 0),
  };
}

module.exports = { summarize };
EOF
cat > "$PRACTICE_DIR/tests/reporting.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { summarize } = require('../src/reporting');

assert.deepEqual(summarize(), { count: 0, total: 0 });
assert.deepEqual(
  summarize({ rows: [{ amount: 10 }, { amount: 20 }] }),
  { count: 2, total: 30 },
);
EOF
commit "2026-01-05T12:00:00+08:00" -m "lab: make reporting input explicit"

echo "Creating stacked branch..."
git checkout --quiet "$LAB_PREFIX/feature/pricing"
git checkout --quiet -b "$LAB_PREFIX/feature/pricing-part2"
cat > "$PRACTICE_DIR/src/pricing-api.js" <<'EOF'
'use strict';

const { calculatePrice, DEFAULT_TAX_RATE } = require('./pricing');

function explainPrice(amount, {
  taxRate = DEFAULT_TAX_RATE,
  member = false,
  coupons = [],
} = {}) {
  const total = calculatePrice(amount, taxRate, member, coupons);
  return {
    amount,
    discount: amount - total,
    total,
  };
}

module.exports = { explainPrice };
EOF
cat > "$PRACTICE_DIR/tests/pricing-api.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { explainPrice } = require('../src/pricing-api');

assert.deepEqual(explainPrice(100, { taxRate: 0, member: true }), {
  amount: 100,
  discount: 10,
  total: 90,
});
EOF
cat > "$PRACTICE_DIR/tests/run-tests.js" <<'EOF'
'use strict';

require('./pricing.test');
require('./checkout.test');
require('./pricing-api.test');

console.log('all tests passed');
EOF
commit "2026-01-06T09:00:00+08:00" -m "lab: expose pricing explanation API"

cat > "$PRACTICE_DIR/tests/pricing-api.test.js" <<'EOF'
'use strict';

const assert = require('node:assert/strict');
const { explainPrice } = require('../src/pricing-api');

assert.deepEqual(explainPrice(100, { taxRate: 0, member: true }), {
  amount: 100,
  discount: 10,
  total: 90,
});

assert.deepEqual(explainPrice(0, { taxRate: 0 }), {
  amount: 0,
  discount: 0,
  total: 0,
});
EOF
commit "2026-01-06T09:05:00+08:00" -m "lab: cover zero-value pricing explanation"

echo "Creating local practice remote..."
git init --quiet --bare --initial-branch=main "$REMOTE_REPO"
git remote add "$REMOTE_NAME" "$REMOTE_REPO"

git push --quiet "$REMOTE_NAME" \
  "$LAB_PREFIX/main:refs/heads/main" \
  "$LAB_PREFIX/feature/reporting:refs/heads/feature/reporting"

F1_SHA="$(git rev-parse "$LAB_PREFIX/feature/pricing~2")"
git push --quiet "$REMOTE_NAME" \
  "$LAB_PREFIX/feature/pricing~2:refs/heads/feature/pricing"

git checkout --quiet -b "$LAB_PREFIX/teammate" "$F1_SHA"
mkdir -p "$PRACTICE_DIR/docs"
cat > "$PRACTICE_DIR/docs/pricing-rollout.md" <<'EOF'
# Pricing rollout

The pricing change is limited to accounts in the staging beta group.
Support should report calculation mismatches with the account and cart IDs.
EOF
commit "2026-01-06T10:00:00+08:00" -m "lab: document pricing rollout"
git push --quiet "$REMOTE_NAME" "$LAB_PREFIX/teammate:refs/heads/feature/pricing"

# Make developer-facing remote-tracking data intentionally stale.
git update-ref "refs/remotes/$REMOTE_NAME/feature/pricing" "$F1_SHA"

git checkout --quiet "$LAB_PREFIX/feature/pricing"
git branch --set-upstream-to="$REMOTE_NAME/feature/pricing" \
  "$LAB_PREFIX/feature/pricing"
git branch --set-upstream-to="$REMOTE_NAME/feature/reporting" \
  "$LAB_PREFIX/feature/reporting"
git checkout --quiet "$LAB_PREFIX/main"
git branch --set-upstream-to="$REMOTE_NAME/main" "$LAB_PREFIX/main"

git update-ref \
  refs/rebase-lab/feature-pricing-before-sync \
  "$LAB_PREFIX/feature/pricing"

git checkout --quiet "$ORIGINAL_BRANCH"

cat <<EOF

Rebase lab ready.

Repository: $ROOT
Original branch restored: $ORIGINAL_BRANCH
Practice remote: $REMOTE_REPO

Main branches:
  $LAB_PREFIX/main
  $LAB_PREFIX/feature/pricing
  $LAB_PREFIX/feature/pricing-part2
  $LAB_PREFIX/feature/reporting

Start:
  cd "$ROOT"
  git checkout $LAB_PREFIX/feature/pricing
  node rebase-practice/tests/run-tests.js
  ./git-rebase-lab/inspect.sh

Reset lab:
  ./git-rebase-lab/reset.sh

Remove lab completely:
  ./git-rebase-lab/cleanup.sh
EOF
