step() { printf '\n==> %s\n' "$*"; }

# Prints the lines of the given scripts that run a command by its full path under /bin, /sbin,
# /usr/bin or /usr/sbin, and returns 0 if there are any. A stub or shim on PATH can't intercept
# such a call. A #! line doesn't count.
calls_by_full_path() {
  grep -nE '(^|[[:space:];|&(`])/(usr/)?(s)?bin/' "$@" | grep -v '^[^:]*:1:#!'
}

found_or_abort() {
  local status=0
  "$@" || status=$?
  if ((status > 1)); then
    echo "Scan failed with exit $status: $*" >&2
    exit 2
  fi
  return "$status"
}
