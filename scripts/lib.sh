# Shell functions that scripts/check.sh, scripts/release.sh and the live QA scripts source.

step() { printf '\n==> %s\n' "$*"; }

# Prints the lines of the given scripts that name a command by an absolute path whose last folder
# is bin or sbin, bare, quoted or assigned, and returns 0 if there are any. That covers /usr/bin,
# /usr/local/bin, and Xcode's and the Command Line Tools' usr/bin, where notarytool and stapler
# live. A stub or shim on PATH can't intercept such a call. A #! line doesn't count. A file it
# can't read exits 2. A path built at run time, such as one from `xcode-select -p` or
# $DEVELOPER_DIR, isn't seen.
calls_by_full_path() {
  local matches status=0
  matches="$(grep -HnE "(^|[[:space:];|&(\`\"'=])(/[[:alnum:]._-]+)*/(s)?bin/" "$@")" || status=$?
  if ((status > 1)); then
    echo "calls_by_full_path: grep failed with exit $status: $*" >&2
    exit 2
  fi
  ((status == 0)) || return 1
  grep -v '^[^:]*:1:#!' <<<"$matches"
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
