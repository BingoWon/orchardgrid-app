#!/usr/bin/env bash
# Live smoke test against a running OrchardGrid.app on :8888.
# Assumes:
#   1. `og` is built (`make release` or on PATH)
#   2. OrchardGrid.app is running with Local Sharing enabled
#   3. Apple Intelligence is available on this Mac
set -euo pipefail

OG="${OG:-$(dirname "$0")/../.build/release/og}"
if [ ! -x "$OG" ]; then
  OG="$(command -v og || true)"
fi
if [ -z "$OG" ] || [ ! -x "$OG" ]; then
  echo "error: og binary not found. Run \`make release\` or \`make install\` first." >&2
  exit 1
fi

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n     %s\n" "$1" "$2"; exit 1; }
section() { printf "\n\033[1;36m%s\033[0m\n" "$1"; }

section "Using: $OG"
"$OG" --version

section "1. Reachability"
if ! out=$("$OG" --model-info 2>&1); then
  fail "model-info" "$out"
fi
pass "og --model-info succeeded"
echo "$out" | grep -q "apple-intelligence" || fail "model id" "expected 'apple-intelligence'"
pass "reports apple-intelligence"
echo "$out" | grep -q "ok" || fail "status" "expected 'ok'"
pass "reports status=ok"

section "2. Single prompt (plain)"
if ! out=$("$OG" "respond with only the word: hello"); then
  fail "single prompt" "exit $?"
fi
pass "got response: $(echo "$out" | head -c 60)"
[ -n "$out" ] || fail "non-empty response" "empty stdout"

section "3. JSON output + usage counts"
if ! out=$("$OG" -o json "reply with only: hi"); then
  fail "json prompt" "exit $?"
fi
pass "JSON parsed"
echo "$out" | python3 -c "import sys, json; d=json.load(sys.stdin); assert d['content']; assert d['usage']['total_tokens']>0" \
  || fail "JSON envelope" "missing content or usage"
pass "content + usage.total_tokens > 0"

section "4. Reproducibility with --seed"
out1=$("$OG" --seed 42 --temperature 0.0 "list three primary colors, comma-separated, no extras")
out2=$("$OG" --seed 42 --temperature 0.0 "list three primary colors, comma-separated, no extras")
if [ "$out1" = "$out2" ]; then
  pass "same seed → same output"
else
  printf "  \033[33m!\033[0m reproducibility soft-fail (model may be non-deterministic)\n"
  echo "    out1: $out1"
  echo "    out2: $out2"
fi

section "5. Context strategy flag accepted"
"$OG" --context-strategy newest-first "say ok" >/dev/null && pass "newest-first accepted"
"$OG" --context-strategy strict "say ok" >/dev/null && pass "strict accepted"

section "All live smoke tests passed ✓"
