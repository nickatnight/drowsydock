#!/usr/bin/env bash
#   scripts/readme/check-readme.sh [README]   default README.md; paths resolve from the repo root
set -euo pipefail
cd "$(dirname "$0")/../.."

readme="${1:-README.md}"
failed=0

readme_without_code_blocks() {
  awk '/^[[:space:]]*```/ { fenced = !fenced; next } !fenced' "$readme"
}

# GitHub's anchor for each heading: lowercase, punctuation dropped, spaces as hyphens.
anchors() {
  readme_without_code_blocks | sed -nE 's/^#{1,6}[[:space:]]+//p' | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}

links() {
  readme_without_code_blocks | grep -oE '\]\([^)[:space:]]+|(href|src)="[^"]*"' |
    sed -E 's/^\]\(//; s/^(href|src)="//; s/"$//' || true
}

while IFS= read -r link; do
  case "$link" in
    http://* | https://* | mailto:*) ;;
    '#'*)
      if ! anchors | grep -qxF "${link#\#}"; then
        echo "README: $link names no heading in $readme" >&2
        failed=1
      fi
      ;;
    *)
      path="${link%%#*}"
      if [[ ! -e $path ]]; then
        echo "README: $link names no file or folder" >&2
        failed=1
      elif git check-ignore -q "$path"; then
        echo "README: $link names a file git ignores, so GitHub doesn't have it" >&2
        failed=1
      fi
      ;;
  esac
done < <(links)

if ! scripts/readme/banner.sh --check; then
  failed=1
fi
exit "$failed"
