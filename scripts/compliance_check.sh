#!/usr/bin/env bash
# Compliance pre-build check
# Run before builds to verify compliance requirements are met.

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Compliance Check ==="
echo ""

# --- Encryption Standards ---
echo "[Encryption]"

# 1. iOS encryption declaration
if grep -q "ITSAppUsesNonExemptEncryption" ios/Runner/Info.plist 2>/dev/null; then
  if grep -A1 "ITSAppUsesNonExemptEncryption" ios/Runner/Info.plist | grep -q "false"; then
    pass "iOS ITSAppUsesNonExemptEncryption is false (standard encryption only)"
  else
    fail "iOS ITSAppUsesNonExemptEncryption is not false — review encryption usage"
  fi
else
  fail "iOS Info.plist missing ITSAppUsesNonExemptEncryption key"
fi

# 2. No banned crypto libraries
BANNED_CRYPTO="pointycastle|encrypt\b|cryptography:|crypto:|bcrypt"
if grep -rqE "$BANNED_CRYPTO" pubspec.yaml 2>/dev/null; then
  fail "pubspec.yaml contains a non-standard crypto dependency — only platform-provided encryption is allowed"
else
  pass "No non-standard crypto dependencies in pubspec.yaml"
fi

# 3. No deprecated cipher usage in Dart code
DEPRECATED_CIPHERS="DES|3DES|RC4|MD5|SHA1"
if grep -rqE "$DEPRECATED_CIPHERS" lib/ 2>/dev/null; then
  fail "Dart source references deprecated cipher/hash — review lib/ for: $DEPRECATED_CIPHERS"
else
  pass "No deprecated cipher references in lib/"
fi

echo ""

# --- Geographic Restrictions ---
echo "[Geographic Distribution]"

# 4. Steering file documents France exclusion
if grep -qi "france" .kiro/steering/compliance.md 2>/dev/null; then
  pass "Compliance steering file documents France distribution restriction"
else
  fail "Compliance steering file missing France distribution restriction"
fi

# 5. iOS Info.plist contains ITSExcludedTerritories with FR
if grep -q "ITSExcludedTerritories" ios/Runner/Info.plist 2>/dev/null; then
  if grep -A3 "ITSExcludedTerritories" ios/Runner/Info.plist | grep -q "FR"; then
    pass "iOS Info.plist excludes France (FR) in ITSExcludedTerritories"
  else
    fail "iOS Info.plist ITSExcludedTerritories does not include FR"
  fi
else
  fail "iOS Info.plist missing ITSExcludedTerritories key"
fi

echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Compliance check FAILED. Fix the issues above before building."
  exit 1
fi
echo "All compliance checks passed."
