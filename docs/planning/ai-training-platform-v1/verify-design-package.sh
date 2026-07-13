#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

required=(
  README.md
  00-source-decision-baseline.md
  01-requirements-traceability.md
  02-functional-screen-design.md
  03-system-architecture-cdd-cdr.md
  04-ai-diagnosis-persona-recommendation.md
  05-document-ai-hwp-rag.md
  06-ai-gateway-model-selection.md
  07-data-api-interface-design.md
  08-security-privacy-operations.md
  09-test-procedure-acceptance.md
  10-delivery-implementation-plan.md
  11-codex-one-shot-implementation-prompt.md
)

for file in "${required[@]}"; do
  test -s "$root/$file" || { echo "FAIL: missing or empty $file"; exit 1; }
done
echo "PASS: required documents exist (${#required[@]})"

rfp_prefixes=(PLR ECR DER SIR DAR TER SER QUR COR PMR PSR)
expected_counts=(4 2 8 3 7 4 8 5 6 8 5)
total=0
for index in "${!rfp_prefixes[@]}"; do
  prefix="${rfp_prefixes[$index]}"
  expected="${expected_counts[$index]}"
  actual="$(grep -E "^\| ${prefix}-[0-9]{3} \|" "$root/01-requirements-traceability.md" | wc -l | tr -d ' ')"
  test "$actual" = "$expected" || { echo "FAIL: $prefix expected $expected got $actual"; exit 1; }
  total=$((total + actual))
done
test "$total" = 60 || { echo "FAIL: RFP requirement count $total"; exit 1; }
echo "PASS: 60 RFP requirements traced"

test "$(grep -E '^\| SYS-F-[0-9]{3} \|' "$root/01-requirements-traceability.md" | wc -l | tr -d ' ')" = 18
test "$(grep -E '^\| SYS-NF-[0-9]{3} \|' "$root/01-requirements-traceability.md" | wc -l | tr -d ' ')" = 15
echo "PASS: 33 system requirements present"

if grep -RniE '\b(TBD|TODO|FIXME|implement later|fill in details)\b' "$root" --include='*.md' --exclude='11-codex-one-shot-implementation-prompt.md'; then
  echo "FAIL: unresolved placeholder in target design"
  exit 1
fi
echo "PASS: no unresolved target-design placeholders"

for file in "$root"/*.md; do
  fences="$(grep -c '^```' "$file" || true)"
  test $((fences % 2)) = 0 || { echo "FAIL: unbalanced code fences in $(basename "$file")"; exit 1; }
done
echo "PASS: Markdown code fences balanced"

for file in "${required[@]}"; do
  while IFS= read -r link; do
    case "$link" in
      http*|mailto:*|'#'*) continue ;;
    esac
    target="${link%%#*}"
    test -e "$root/$target" || { echo "FAIL: broken link $file -> $link"; exit 1; }
  done < <(grep -oE '\]\([^)]+' "$root/$file" | sed 's/^]('// || true)
done
echo "PASS: relative Markdown links valid"

echo "RESULT: PASS"
