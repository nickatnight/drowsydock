#!/usr/bin/env bash
#   scripts/readme/check-readme.sh [README]   default README.md; paths resolve from the repo root
#
# A relative link or image must name a file or folder in git's index, spelled exactly as git has
# it, because that is what GitHub serves: a new file needs `git add` first. A #anchor must name one
# of the README's headings. Links in fenced code, inline code and HTML comments don't count,
# http(s) and mailto links aren't followed, and a fragment on a link to another file isn't checked.
set -euo pipefail
cd "$(dirname "$0")/../.."

readme="${1:-README.md}"
failed=0

# The README without what GitHub doesn't render as links: fenced code (``` or ~~~), HTML comments
# and inline code spans.
readme_without_code_or_comments() {
  perl -0pe 's/^ {0,3}(`{3,}|~{3,})[^\n]*\n.*?^ {0,3}\1[ \t]*$//gms; s/<!--.*?-->//gs;
    s/`[^`\n]*`//g' -- "$readme"
}

# Inline links and images, href and src attributes in either quotes, and reference definitions.
links() {
  readme_without_code_or_comments | perl -ne '
    print "$1\n" while /\]\(\s*<?([^)\s>]+)/g;
    print "$2\n" while /\b(?:href|src)\s*=\s*(["\x27])(.*?)\1/g;
    print "$1\n" if /^ {0,3}\[[^\]]+\]:\s*<?([^\s>]+)/;
  '
}

# GitHub's anchor for each heading: lowercase, punctuation dropped, spaces as hyphens.
anchors="$(readme_without_code_or_comments | sed -nE 's/^#{1,6}[[:space:]]+//p' |
  tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9 _-]//g; s/ /-/g')"

# Every file in git's index, and every folder that holds one.
tracked="$(git -c core.quotePath=false ls-files --cached </dev/null)"
folders="$(awk -F/ '{ path = $1; for (i = 2; i <= NF; i++) { print path; path = path "/" $i } }' \
  <<<"$tracked" | sort -u)"

# The links arrive on fd 3, so no command in the loop can read them from stdin.
while IFS= read -r link <&3; do
  case "$link" in
    http://* | https://* | mailto:*) ;;
    '#'*)
      if ! grep -qxF -- "${link#\#}" <<<"$anchors"; then
        echo "README: $link names no heading in $readme" >&2
        failed=1
      fi
      ;;
    *)
      # GitHub serves the file without the query or fragment, and starts a leading / at the root.
      path="${link%%[#?]*}"
      path="${path#/}"
      path="${path#./}"
      path="${path%/}"
      if [[ -z $path ]] || { grep -qxF -- "$path" <<<"$tracked"$'\n'"$folders" && [[ -e $path ]]; }
      then
        continue
      fi
      if [[ -e $path ]]; then
        echo "README: $link isn't in git's index as spelled: check its case, keep it inside" \
          "the repo, or git add it" >&2
      else
        echo "README: $link names no file or folder" >&2
      fi
      failed=1
      ;;
  esac
done 3< <(links)

if ! scripts/readme/banner.sh --check </dev/null; then
  failed=1
fi
exit "$failed"
