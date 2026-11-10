#!/usr/bin/env bash
# Checks docs/manual-qa.md's map from each QA row to the tests or live scenarios that cover it:
# every test it names exists (anchored, so a commented-out test fails), every Tests token is a test
# class or Class.testMethod, every Live token is a qa-live.sh scenario that lists the row, every
# automated row cites something, and the row numbers equal docs/qa-rows.txt. scripts/check.sh fast
# runs it; check-qa-mapping-selftest.sh plants errors in copies to show each part bites.
#
#   scripts/qa/check-qa-mapping.sh [DOC] [ROWS]
set -uo pipefail
cd "$(dirname "$0")/../.."
doc="${1:-docs/manual-qa.md}"
rows_file="${2:-docs/qa-rows.txt}"

# Exit 0 means it found something and 1 means it found nothing; anything else stops the check.
found() {
  local status=0
  "$@" || status=$?
  if ((status > 1)); then
    echo "Scan failed with exit $status: $*" >&2
    exit 2
  fi
  return "$status"
}

manual_qa_names_real_tests() {
  local failed=0 table cell row token class method scenario rows_of_scenario
  table="$(sed -n '/^## Automated and live rows/,/^## Coverage/p' "$doc" |
    awk -F'|' 'NF > 5 && $2 ~ /[0-9]/')"

  # Every token in the Tests column is Class.testMethod, defined as a test (not commented out), or
  # a test class whose file exists.
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

  # Every live scenario named exists, and lists the rows that cite it.
  local listing
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

  # Every automated row cites something.
  while IFS= read -r row; do
    echo "Manual QA: row $row names no test and no live scenario" >&2
    failed=1
  done < <(awk -F'|' '$4 !~ /`/ && $5 !~ /`/ {gsub(/ /, "", $2); print $2}' <<<"$table")

  # No row disappears: the doc's row numbers are exactly the committed list's.
  if ! found cmp -s <(grep -oE '^\| ([0-9]+\.[0-9]+[a-z]?|E\.[0-9]+) ' "$doc" |
    tr -d '| ' | sort) <(sort "$rows_file"); then
    echo "Manual QA: $doc's rows differ from $rows_file:" >&2
    diff <(grep -oE '^\| ([0-9]+\.[0-9]+[a-z]?|E\.[0-9]+) ' "$doc" | tr -d '| ' | sort) \
      <(sort "$rows_file") >&2 || true
    failed=1
  fi
  return "$failed"
}

manual_qa_names_real_tests
