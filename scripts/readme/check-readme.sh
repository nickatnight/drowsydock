#!/usr/bin/env bash
#   scripts/readme/check-readme.sh [README]   default README.md; paths resolve from the repo root
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
# The banner and the icon must each stay under 1,000,000 bytes and hold none of these, in any
# letter case: <script
# or <foreignObject, bare or after ASCII letters and a colon (svg:); javascript:; @import; an
# on...= attribute (on, ASCII letters, optional whitespace, =, at a line's start or after
# whitespace); <!DOCTYPE; <!ENTITY; an image with nothing between base64, and its quote; url(
# followed, after optional whitespace, quote and whitespace, by a character other than #, a quote
# or whitespace; a quoted href= or src= value that doesn't start with # or data:image/png;base64,;
# and an http:// or https:// URL other than http://www.w3.org/2000/svg. The guard reads one line
# at a time and decodes nothing, so forms like these can pass: an href set by animation (<set to=,
# <animate values=), a CSS image-set() string, an attribute or url( split from its = or value by a
# line break, a non-ASCII namespace prefix, and a keyword written with a CSS escape (\75rl(), an
# XML character reference (u&#114;l() or a CDATA, comment or processing-instruction break.
# banner.sh --check, which compares both byte for byte with what banner.sh writes, is what stops
# a hand-edited banner or icon.
set -euo pipefail
cd "$(dirname "$0")/../.."

readme="${1:-README.md}"
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

letters_prefix='([a-z]+:)?'
script="<${letters_prefix}script"
javascript='javascript:'
import='@import'
empty_image="base64,[\"']"
foreign_url_function="url\\([[:space:]]*[\"']?[[:space:]]*[^#\"'[:space:]]"
event_handler='(^|[[:space:]])on[a-z]+[[:space:]]*='
foreign_object="<${letters_prefix}foreignObject"
document_type='<!(DOCTYPE|ENTITY)'
forbidden_pattern="$script|$javascript|$import|$empty_image|$foreign_url_function"
forbidden_pattern+="|$event_handler|$foreign_object|$document_type"
assets="${README_ASSETS:-docs/readme}"
for svg in "$assets/banner.svg" "$assets/icon.svg"; do
  if (($(wc -c <"$svg") >= 1000000)); then
    echo "README: $svg must stay under 1,000,000 bytes" >&2
    failed=1
  fi
  forbidden="$(grep -oiE -- "$forbidden_pattern" "$svg" || true)"
  hrefs="$(grep -oiE -- "(href|src)[[:space:]]*=[[:space:]]*[\"'][^\"']*" "$svg" || true)"
  foreign_hrefs="$(grep -viE -- "[\"'](#|data:image/png;base64,)" <<<"$hrefs" || true)"
  urls="$(grep -oiE -- "https?://[^\"' )<>]+" "$svg" || true)"
  foreign_urls="$(grep -vxF -- 'http://www.w3.org/2000/svg' <<<"$urls" || true)"
  if [[ -n $forbidden || -n $foreign_hrefs || -n $foreign_urls ]]; then
    echo "README: $svg must not hold a script, an external reference or an empty image" >&2
    failed=1
  fi
done

if ! scripts/readme/banner.sh --check </dev/null; then
  failed=1
fi
exit "$failed"
