#!/usr/bin/env bash
# Runs scripts/qa/dock-preferences.sh against a scratch defaults domain in a temporary folder, never
# com.apple.dock: a save and an exact restore, a restore with nothing changed, a corrupt or
# truncated backup, an export that can't be written (a missing folder and a read-only one), an
# export that doesn't match, an import that fails, an import that "succeeds" without taking, a
# Ctrl-C between the delete and the import, the caller's traps after a restore, and the printed
# restore-by-hand command. scripts/check.sh fast runs it.
set -uo pipefail
cd "$(dirname "$0")/../.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# shellcheck source=scripts/qa/dock-preferences.sh
source scripts/qa/dock-preferences.sh
dock_domain="$scratch/dock"
dock_backup="$scratch/qa/dock-backup.plist"
restarts=0
dock_restart() { restarts=$((restarts + 1)); }

failed=0
expect() {
  if ! "${@:2}"; then
    echo "check-dock-restore: $1" >&2
    failed=1
  fi
}

expect_failure() {
  if "${@:2}"; then
    echo "check-dock-restore: $1" >&2
    failed=1
  fi
}

fresh_domain() {
  rm -rf "$scratch/dock.plist" "$scratch/qa"
  defaults write "$dock_domain" orientation -string bottom
  defaults write "$dock_domain" tilesize -int 48
  defaults write "$dock_domain" persistent-apps -array-add '<dict><key>tile-type</key><string>file-tile</string></dict>'
  restarts=0
}

original="$scratch/original.xml"

# A save, a harmless change, and a restore that removes it exactly.
fresh_domain
dock_domain_xml >"$original"
expect "the save succeeds" save_dock_backup
expect "the backup exists and matches the live domain" dock_matches_backup
expect "the backup is readable by its owner only" test "$(stat -f '%Lp' "$dock_backup")" = 600
defaults write "$dock_domain" qa-live-selftest -bool true
defaults write "$dock_domain" orientation -string left
expect "the restore succeeds" restore_dock
expect "the sentinel key is gone" bash -c '! defaults read "$1" qa-live-selftest 2>/dev/null' _ "$dock_domain"
expect "the domain equals the original" cmp -s "$original" <(dock_domain_xml)
expect "the backup is deleted after a verified restore" test ! -e "$dock_backup"
expect "the Dock is relaunched once" test "$restarts" -eq 1

# Nothing changed: no relaunch, and the backup goes.
fresh_domain
save_dock_backup
expect "an unchanged restore succeeds" restore_dock
expect "an unchanged restore relaunches nothing" test "$restarts" -eq 0
expect "an unchanged restore deletes the backup" test ! -e "$dock_backup"

# A backup that doesn't parse: the domain is left alone and the backup kept.
fresh_domain
save_dock_backup
defaults write "$dock_domain" orientation -string right
# "garbage" is a valid property list (a string), so plutil -lint alone would pass it.
echo "garbage" >"$dock_backup"
expect_failure "a corrupt backup fails the restore" restore_dock
printf '<?xml version="1.0"?>\n<plist version="1.0"><dict><key>a</key>' >"$dock_backup"
expect_failure "a truncated backup fails the restore" restore_dock
echo "garbage" >"$dock_backup"
expect "a corrupt backup leaves the domain changed, not wiped" \
  test "$(defaults read "$dock_domain" orientation)" = right
expect "a corrupt backup is kept" test -s "$dock_backup"
expect "a corrupt backup relaunches nothing" test "$restarts" -eq 0

# An export that can't be written: no backup, and the save reports it.
fresh_domain
dock_backup="/nonexistent-qa-folder/dock-backup.plist"
expect_failure "a save that can't write fails" save_dock_backup
expect "a failed save leaves no backup" test ! -e "$dock_backup"
dock_backup="$scratch/qa/dock-backup.plist"

# An export that writes something other than the live domain: the save fails and keeps nothing.
fresh_domain
defaults() {
  if [[ $1 == export && $3 != - ]]; then
    command defaults write "$scratch/other" orientation -string right
    command defaults export "$scratch/other" "$3"
    return
  fi
  command defaults "$@"
}
expect_failure "a backup that doesn't match the live domain fails the save" save_dock_backup
unset -f defaults
expect "a mismatched backup isn't kept" test ! -e "$dock_backup"

# An export into a read-only folder: `defaults export` exits 0 there without writing.
fresh_domain
mkdir -p "$scratch/readonly"
chmod 555 "$scratch/readonly"
dock_backup="$scratch/readonly/dock-backup.plist"
expect_failure "a save into a read-only folder fails" save_dock_backup
expect "a save into a read-only folder leaves no backup" test ! -e "$dock_backup"
chmod 755 "$scratch/readonly"
dock_backup="$scratch/qa/dock-backup.plist"

# An import that exits 0 but leaves the domain different: the compare catches it, the backup is
# kept and the Dock isn't relaunched.
fresh_domain
save_dock_backup
defaults write "$dock_domain" orientation -string left
defaults() {
  if [[ $1 == import && $2 == "$dock_domain" ]]; then
    command defaults write "$dock_domain" orientation -string right
    return 0
  fi
  command defaults "$@"
}
expect_failure "an import that doesn't take fails the restore" restore_dock
unset -f defaults
expect "an import that doesn't take keeps the backup" test -s "$dock_backup"
expect "an import that doesn't take relaunches nothing" test "$restarts" -eq 0
rm -f "$dock_backup"

# The command printed for restoring by hand after a kill -9 puts the domain back exactly and
# removes the backup. killall is stubbed: it must never reach the real Dock.
fresh_domain
dock_domain_xml >"$original"
save_dock_backup
defaults write "$dock_domain" orientation -string left
defaults write "$dock_domain" qa-live-selftest -bool true
(
  killall() { :; }
  eval "$(dock_restore_command)"
)
expect "the printed command restores the domain exactly" cmp -s "$original" <(dock_domain_xml)
expect "the printed command removes the backup" test ! -e "$dock_backup"

# A restore leaves the caller's traps as they were: qa-live.sh restores mid-run and still needs
# its Ctrl-C handler afterwards.
fresh_domain
save_dock_backup
defaults write "$dock_domain" orientation -string left
trap 'echo caller-int' INT
before_traps="$(trap -p INT)"
restore_dock
expect "the caller's INT trap is back after a restore" test "$(trap -p INT)" = "$before_traps"
trap - INT

# An import that fails after the delete: the backup is kept, and nothing is relaunched.
fresh_domain
save_dock_backup
defaults write "$dock_domain" orientation -string left
defaults() {
  if [[ $1 == import && $2 == "$dock_domain" ]]; then return 1; fi
  command defaults "$@"
}
expect_failure "a failed import fails the restore" restore_dock
unset -f defaults
expect "a failed import keeps the backup" test -s "$dock_backup"
expect "a failed import relaunches nothing" test "$restarts" -eq 0
expect "a retry with a working import restores" restore_dock
expect "the retry deletes the backup" test ! -e "$dock_backup"

# A Ctrl-C between the delete and the import is ignored, so the restore still completes.
fresh_domain
save_dock_backup
defaults write "$dock_domain" orientation -string left
interrupted="$(
  DOMAIN="$dock_domain" BACKUP="$dock_backup" bash -c '
    source scripts/qa/dock-preferences.sh
    dock_domain="$DOMAIN"
    dock_backup="$BACKUP"
    dock_restart() { :; }
    defaults() {
      if [[ $1 == import && $2 == "$dock_domain" ]]; then kill -INT $$; fi
      command defaults "$@"
    }
    restore_dock && echo restored
  ' 2>/dev/null
)"
expect "a Ctrl-C during the restore doesn't stop it" test "$interrupted" = restored
expect "the interrupted restore put the domain back" \
  test "$(defaults read "$dock_domain" orientation)" = bottom

exit "$failed"
