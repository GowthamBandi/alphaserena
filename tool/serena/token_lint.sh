#!/usr/bin/env bash
# Serena Design System — tokenization lint (M1). Enforces "tokens-as-contract".
# Fails (exit 1) if in-scope UI code hardcodes a color/font instead of using SDS tokens.
# Scope: lib/screens/** and lib/features/** (the UI layer). The generated token layer,
# lib/core/theme, and the SDS binding are EXEMPT (they legitimately define raw values).
#
# Flags:  Colors.<name> named constants ·  Color(0x...) literals (case-INSENSITIVE) ·
#         inline GoogleFonts.<font>(  ·  (extended) raw fontSize: literals.
# Usage:  tools/token_lint.sh <repo-lib-path>   e.g. tools/token_lint.sh "D:/flutter works/alphaserena/lib"
set -u
LIB="${1:-lib}"
scope=()
[ -d "$LIB/screens" ] && scope+=("$LIB/screens")
[ -d "$LIB/features" ] && scope+=("$LIB/features")
if [ ${#scope[@]} -eq 0 ]; then echo "token-lint: no screens/ or features/ under $LIB — nothing to scan"; exit 0; fi

# rg if available else grep -rEn. Case-insensitive for Color(0x...).
scan() { # <pattern> <flags>
  if command -v rg >/dev/null 2>&1; then rg -n ${2:-} -e "$1" "${scope[@]}" 2>/dev/null
  else grep -rEn ${2:-} -e "$1" "${scope[@]}" 2>/dev/null; fi
}

viol=0
report() { local label="$1" count="$2"; if [ "$count" -gt 0 ]; then echo "  ✗ $label: $count"; viol=$((viol+count)); else echo "  ✓ $label: 0"; fi; }

echo "token-lint scope: ${scope[*]}"
c_colors=$(scan 'Colors\.[a-zA-Z]' | wc -l)
c_hex=$(scan 'Color\(0[xX]' | wc -l)
c_gf=$(scan 'GoogleFonts\.[a-zA-Z]+\(' | wc -l)
c_fs=$(scan 'fontSize:[[:space:]]*[0-9]' | wc -l)
report "Colors.* named constants" "$c_colors"
report "Color(0x...) literals (case-insensitive)" "$c_hex"
report "inline GoogleFonts.*()" "$c_gf"
report "raw fontSize: literals (extended)" "$c_fs"

echo ""
if [ "$viol" -gt 0 ]; then
  echo "token-lint FAIL ✗  — $viol hardcoded value(s) in the UI layer. Use SerenaPalette / SerenaText tokens."
  exit 1
else
  echo "token-lint PASS ✓  — 0 hardcoded colors/fonts in the UI layer."
  exit 0
fi
