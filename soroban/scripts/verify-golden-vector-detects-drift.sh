#!/usr/bin/env bash
set -euo pipefail

# Demonstrates that the golden-vector tests detect wire-format changes, by making
# each change and confirming they fail.
#
# The concern this answers: the rest of the digest tests ask the contract for a
# hash and then sign what they got back, so they pass under any format change.
# Asserting that the golden tests "would catch it" is worth no more than the
# other tests were — so run it.
#
#   ./soroban/scripts/verify-golden-vector-detects-drift.sh
#
# Each mutation is applied to a real source file, `cargo test` is run, and the
# file is restored. Sources are copied aside first and restored by an EXIT trap,
# so an interrupted run does not leave the tree modified. Uncommitted work is
# safe — nothing here touches git.
#
# Deliberately not wired into CI: it rewrites tracked sources and runs the suite
# once per mutation. `golden-vector.js --check` is the CI-side guard, and it
# covers the failure this cannot — a pinned constant quietly updated to match
# whatever the code now produces.

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY_LIB="predicate-registry/src/lib.rs"
VALIDATION="predicate-registry/src/validation.rs"
TYPES="predicate-registry/src/types.rs"

BACKUP="$(mktemp -d)"
cp "$REGISTRY_LIB" "$BACKUP/lib.rs"
cp "$VALIDATION" "$BACKUP/validation.rs"
cp "$TYPES" "$BACKUP/types.rs"

restore() {
  cp "$BACKUP/lib.rs" "$REGISTRY_LIB"
  cp "$BACKUP/validation.rs" "$VALIDATION"
  cp "$BACKUP/types.rs" "$TYPES"
  rm -rf "$BACKUP"
}
trap restore EXIT

failures=0

# Rewrites a file, erroring out if the pattern did not match. A mutation that
# silently fails to apply would make this script report success while testing
# nothing — the same trap the golden vector exists to close.
apply() {
  local file="$1" from="$2" to="$3"
  python3 - "$file" "$from" "$to" <<'PY'
import pathlib, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
s = p.read_text()
if old not in s:
    sys.exit(f"mutation did not apply to {path}: pattern not found:\n{old}")
p.write_text(s.replace(old, new))
PY
}

# Asserts the golden tests fail, and that they are the only ones that do.
expect_golden_failure() {
  local label="$1"
  local output
  output="$(cargo test -p predicate-registry --lib 2>&1 || true)"

  local golden_failed=0 others_failed=0
  grep -qE '^test test::test_golden_vector_(digest|signature) \.\.\. FAILED' \
    <<<"$output" && golden_failed=1
  grep -E '\.\.\. FAILED' <<<"$output" | grep -qv 'test_golden_vector_' && others_failed=1

  if [ "$golden_failed" -eq 1 ]; then
    printf '  PASS  golden vector rejected it'
    [ "$others_failed" -eq 1 ] && printf ' (other tests failed too)'
    printf '\n'
  else
    printf '  FAIL  %s slipped through the golden vector\n' "$label"
    failures=$((failures + 1))
  fi
}

echo "Baseline: the suite is green before any mutation."
if ! cargo test -p predicate-registry --lib >/dev/null 2>&1; then
  echo "  FAIL  suite is already failing; fix that before trusting this script" >&2
  exit 1
fi
echo "  PASS"
echo

echo "1. Swap the two appends in compute_hash (reorders the preimage)."
apply "$VALIDATION" \
  '    payload.append(&e.ledger().network_id().to_xdr(e));
    // Statement fields in deterministic order
    payload.append(&statement.clone().to_xdr(e));' \
  '    payload.append(&statement.clone().to_xdr(e));
    payload.append(&e.ledger().network_id().to_xdr(e));'
expect_golden_failure "reordered preimage"
cp "$BACKUP/validation.rs" "$VALIDATION"
echo

echo "2. Rename a Statement field (#[contracttype] hashes field names as map keys)."
apply "$TYPES" 'encoded_sig_and_args' 'encoded_sig_and_arg'
apply "$REGISTRY_LIB" 'encoded_sig_and_args' 'encoded_sig_and_arg'
expect_golden_failure "renamed field"
cp "$BACKUP/types.rs" "$TYPES"
cp "$BACKUP/lib.rs" "$REGISTRY_LIB"
echo

if [ "$failures" -ne 0 ]; then
  echo "$failures mutation(s) went undetected — the golden vector is not doing its job." >&2
  exit 1
fi
echo "Both wire-format changes were detected."
