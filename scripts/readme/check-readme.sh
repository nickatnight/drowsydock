#!/usr/bin/env bash
# Checks README.md's links and its images in docs/readme/.
#
# A relative link or image must name a file or folder in git's index, spelled exactly as git has
# it, because that is what GitHub serves: a new file needs `git add` first. A #anchor must name one
# of the README's # headings, as GitHub spells its anchor (lowercase, punctuation and trailing
# spaces dropped, other spaces as hyphens, -1, -2 for repeats). Links in fenced code, inline code
# and HTML comments don't count, http(s) and mailto links aren't followed, and a fragment on a link
# to another file isn't checked.
# Not understood, so a link written as GitHub spells it fails the check: setext headings, explicit
# HTML ids, non-ASCII letters in anchors, links in indented code blocks, %-encoded paths.
# Not read at all, so they pass unchecked: srcset, unquoted or line-split attributes, a fence
# closed by a longer fence, and a code span that crosses a line break.
# The banner and the icon must each stay under 1,000,000 bytes. banner.sh --check, which compares
# both byte for byte with what banner.sh writes, stops a hand-edited banner or icon. Nothing checks
# what banner.sh's own template puts in the banner.
set -euo pipefail
cd "$(dirname "$0")/../.."

readme=README.md
failed=0

readme_without_fences_or_comments() {
  perl -0pe 's/^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[ \t]*$//gms; s/<!--.*?-->//gs' -- "$readme"
}

links() {
  readme_without_fences_or_comments | perl -pe 's/`[^`\n]*`//g' | perl -ne '
    print "$1\n" while /\]\(\s*<?([^)\s>]+)/g;
    print "$2\n" while /\b(?:href|src)\s*=\s*(["\x27])(.*?)\1/g;
    print "$1\n" if /^ {0,3}\[(?!\^)[^\]]+\]:\s*<?([^\s>]+)/;
  '
}

anchors="$(readme_without_fences_or_comments | sed -nE 's/^ {0,3}#{1,6}[[:space:]]+//p' |
  sed -E 's/([[:space:]]+#+)?[[:space:]]*$//; s/\[([^]]*)\]\([^)]*\)/\1/g' |
  tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g' |
  awk '{ repeat = seen[$0]++; print (repeat ? $0 "-" repeat : $0) }')"

tracked="$(git -c core.quotePath=false ls-files --cached </dev/null)"
folders="$(awk -F/ '{ path = $1; for (i = 2; i <= NF; i++) { print path; path = path "/" $i } }' \
  <<<"$tracked" | sort -u)"
known_paths="$tracked"$'\n'"$folders"

while IFS= read -r link <&3; do
  # Control characters are printed as ?, so a link can't pass a command to the CI log.
  shown_link="${link//[[:cntrl:]]/?}"
  case "$link" in
    http://* | https://* | mailto:*) ;;
    '#'*)
      if ! grep -qxF -- "${link#\#}" <<<"$anchors"; then
        echo "README: $shown_link names no heading in $readme" >&2
        failed=1
      fi
      ;;
    *)
      # GitHub serves the file without the query or fragment, and starts a leading / at the root.
      path="${link%%[#?]*}"
      path="${path#/}"
      path="${path#./}"
      path="${path%/}"
      if [[ -z $path ]] || { grep -qxF -- "$path" <<<"$known_paths" && [[ -e $path ]]; }; then
        continue
      fi
      # Whether a wrong-case path exists depends on the volume, so ask the index, ignoring case.
      if [[ -e $path ]] || grep -qixF -- "$path" <<<"$known_paths"; then
        echo "README: $shown_link isn't in git's index as spelled: check its case, keep it inside" \
          "the repo, or git add it" >&2
      else
        echo "README: $shown_link names no file or folder" >&2
      fi
      failed=1
      ;;
  esac
done 3< <(links)

for svg in docs/readme/banner.svg docs/readme/icon.svg; do
  if (($(wc -c <"$svg") >= 1000000)); then
    echo "README: $svg must stay under 1,000,000 bytes" >&2
    failed=1
  fi
done

if ! scripts/readme/banner.sh --check </dev/null; then
  failed=1
fi
exit "$failed"
