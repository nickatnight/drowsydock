# Shell functions that scripts/check.sh, scripts/release.sh and the live QA scripts source.

step() { printf '\n==> %s\n' "$*"; }

# Prints the lines of the given scripts that run a command by its full path under /bin, /sbin,
# /usr/bin or /usr/sbin, and returns 0 if there are any. A stub or shim on PATH can't intercept
# such a call. A #! line doesn't count.
calls_by_full_path() {
  grep -nE '(^|[[:space:];|&(`])/(usr/)?(s)?bin/' "$@" | grep -v '^[^:]*:1:#!'
}

# Runs a scan (grep, awk): 0 means it found something, 1 that it found nothing, and any other
# status (a file it couldn't read) exits 2 rather than reading as "nothing found". Inside a pipe or
# a process substitution that exit ends only the subshell, so the caller sees 2 as "not found".
found_or_abort() {
  local status=0
  "$@" || status=$?
  if ((status > 1)); then
    echo "Scan failed with exit $status: $*" >&2
    exit 2
  fi
  return "$status"
}
