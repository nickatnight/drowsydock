# Saves and restores a defaults domain exactly, for scripts/qa-live.sh, which changes the Dock's
# preferences (com.apple.dock) and must put them back. scripts/qa/check-dock-restore.sh runs these
# functions against a scratch domain in a temporary folder, never against com.apple.dock.
#
# Source it, then set dock_domain and dock_backup. dock_restart relaunches whatever reads the
# domain; the check redefines it.

dock_domain="com.apple.dock"
dock_backup=""

dock_restart() {
  killall Dock
}

# The command a person runs by hand to restore after a kill -9.
dock_restore_command() {
  printf 'plutil -lint -s %q && { defaults delete %q; defaults import %q %q; } && killall Dock && rm %q' \
    "$dock_backup" "$dock_domain" "$dock_domain" "$dock_backup" "$dock_backup"
}

dock_domain_xml() {
  defaults export "$dock_domain" - | plutil -convert xml1 -o - -
}

# Whether `defaults import` takes the backup: it must be a property list whose root is a dictionary.
# `plutil -lint` alone also passes a bare string. Tried on a throwaway domain, so a bad backup is
# found before the real domain is deleted.
dock_backup_is_importable() {
  local trial
  trial="$(mktemp -d)" || return 1
  defaults import "$trial/trial" "$dock_backup" 2>/dev/null
  local status=$?
  rm -rf "$trial"
  return "$status"
}

dock_matches_backup() {
  [[ -f $dock_backup ]] || return 1
  local live saved
  live="$(dock_domain_xml)" || return 1
  saved="$(plutil -convert xml1 -o - "$dock_backup")" || return 1
  [[ $live == "$saved" ]]
}

# Saves the domain to dock_backup through a temporary file in the same folder, so a run killed
# mid-export never leaves a partial backup. The backup must parse and match the live domain;
# otherwise nothing is kept and it returns 1. `defaults export` exits 0 even when it can't write,
# so only these checks catch a failed save.
save_dock_backup() {
  local temporary="$dock_backup.tmp"
  rm -f "$temporary"
  if ! mkdir -p "$(dirname "$dock_backup")" ||
    ! defaults export "$dock_domain" "$temporary" ||
    ! plutil -lint -s "$temporary" ||
    ! mv "$temporary" "$dock_backup" ||
    ! dock_backup_is_importable ||
    ! dock_matches_backup; then
    rm -f "$temporary" "$dock_backup"
    return 1
  fi
}

# Puts the domain back exactly as saved: delete it (an import only merges), import the backup,
# and compare. Only a matching compare relaunches the Dock and deletes the backup. Any failure
# keeps the backup, leaves the running Dock on its own copy, prints the command to retry, and
# returns 1. Signals are ignored while it runs, so a second Ctrl-C can't stop it between the
# delete and the import. Safe to run twice.
restore_dock() {
  [[ -f $dock_backup ]] || return 0
  if ! plutil -lint -s "$dock_backup" || ! dock_backup_is_importable; then
    printf 'The backup at %s is not a defaults dictionary. The Dock was left as it is and the backup kept.\n' \
      "$dock_backup" >&2
    return 1
  fi
  if dock_matches_backup; then
    rm -f "$dock_backup"
    return 0
  fi
  local saved_traps status=0
  saved_traps="$(trap -p INT TERM HUP)"
  trap '' INT TERM HUP
  defaults delete "$dock_domain" 2>/dev/null
  if defaults import "$dock_domain" "$dock_backup" && dock_matches_backup; then
    dock_restart
    rm -f "$dock_backup"
  else
    printf 'The restore did not take; the backup is kept at %s. Restore by hand with:\n  %s\n' \
      "$dock_backup" "$(dock_restore_command)" >&2
    status=1
  fi
  trap - INT TERM HUP
  eval "$saved_traps"
  return "$status"
}
