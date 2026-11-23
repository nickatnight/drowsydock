# Functions that scripts/check.sh, scripts/release.sh and the live QA scripts share. Sourcing it
# defines them and does nothing else.

step() { printf '\n==> %s\n' "$*"; }

# Runs a scan (grep, awk). Exit 0 means it found something and 1 means it found nothing. Any
# other status, such as a file it could not open, stops the run instead of reading as "nothing
# found".
found() {
  local status=0
  "$@" || status=$?
  if ((status > 1)); then
    echo "Scan failed with exit $status: $*" >&2
    exit 2
  fi
  return "$status"
}
