#!/usr/bin/env bash
# Checks docs/manual-qa.md's map from each QA row to the tests or live scenarios that cover it.
set -uo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib.sh
doc=docs/manual-qa.md

table="$(sed -n '/^## Automated and live rows/,/^## Coverage/p' "$doc" |
  awk -F'|' 'NF > 5 && $2 ~ /[0-9]/')"

tests_cells_name_real_tests() {
  local failed=0 token class method
  while IFS= read -r token; do
    class="${token%%.*}"
    if [[ $token == *.* ]]; then
      method="${token#*.}"
      if ! cat Tests/*/"$class.swift" 2>/dev/null | found grep -Eq "^[[:space:]]*func $method\("; then
        echo "Manual QA: $doc names $token, which no test file defines" >&2
        failed=1
      fi
    elif ! compgen -G "Tests/*/$class.swift" >/dev/null; then
      echo "Manual QA: $doc names test class $token, which has no file under Tests/" >&2
      failed=1
    fi
  done < <(awk -F'|' '{print $4}' <<<"$table" | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
  if awk -F'|' '{print $4}' <<<"$table" | grep -oE '`[^`]+`' | tr -d '`' |
    found grep -vqE '^[A-Za-z0-9]+Tests(\.test[A-Za-z0-9]+)?$'; then
    echo "Manual QA: a Tests cell names something that isn't a test class or Class.testMethod" >&2
    failed=1
  fi
  return "$failed"
}

live_cells_name_scenarios_that_list_the_row() {
  local failed=0 listing row cell scenario rows_of_scenario
  listing="$(scripts/qa-live.sh --list)"
  while IFS='|' read -r row cell; do
    while IFS= read -r scenario; do
      [[ -n $scenario ]] || continue
      if [[ ! $scenario =~ ^[a-z-]+$ ]]; then
        echo "Manual QA: row $row's Live cell names '$scenario', which isn't a scenario name" >&2
        failed=1
        continue
      fi
      rows_of_scenario="$(awk -v name="$scenario" '$1 == name' <<<"$listing")"
      if [[ -z $rows_of_scenario ]]; then
        echo "Manual QA: row $row names live scenario $scenario, which qa-live.sh lacks" >&2
        failed=1
      elif ! found grep -qE "(QA| )$row( |$)" <<<"$rows_of_scenario"; then
        echo "Manual QA: row $row cites live scenario $scenario, whose --list rows omit it" >&2
        failed=1
      fi
    done < <(grep -oE '`[^`]+`' <<<"$cell" | tr -d '`')
  done < <(awk -F'|' '{gsub(/ /, "", $2); print $2 "|" $5}' <<<"$table")
  return "$failed"
}

every_row_cites_something() {
  local failed=0 row
  while IFS= read -r row; do
    echo "Manual QA: row $row names no test and no live scenario" >&2
    failed=1
  done < <(awk -F'|' '$4 !~ /`/ && $5 !~ /`/ {gsub(/ /, "", $2); print $2}' <<<"$table")
  return "$failed"
}

failed=0
tests_cells_name_real_tests || failed=1
live_cells_name_scenarios_that_list_the_row || failed=1
every_row_cites_something || failed=1
exit "$failed"
