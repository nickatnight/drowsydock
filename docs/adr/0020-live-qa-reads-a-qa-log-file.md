# ADR-0020: The live QA script reads a log file the app writes only when launched with `--qa-log`

## Status

Accepted (job 004, rework 2, 2026-11-10). Supersedes the part of ADR 0018 in which the script reads the app's results with `log stream`, and its consequence that the script needs an administrator account. The rest of ADR 0018 stands: the menu through System Events, the Dock through `dock preferences`, the backup and restore, and `qa-helper`.

## Context

`scripts/qa-live.sh` checks most of its rows by reading what the app logs: `Started:`, `Changed:`, `Overlay: …`, `Accessibility granted:` and the Dock tracker's lines. The latency checks also need the time the app logged each line. Until this rework the script read them with `log stream`.

macOS lets only administrators run `log stream` and `log show`. The owner's account is a standard account, so on it the preflight stopped with "Must be admin to run 'stream' command". Only `--only restore-selftest`, which reads no log, could run. Running from another account doesn't help, because that account has its own Dock and its own DrowsyDock (follow-up J4).

Reading the unified log without `log`, through `OSLogStore`, was tried in a probe on macOS 27.0.1 from a standard account. `OSLogStore(scope: .currentProcessIdentifier)` threw even for the probe's own entries, and the other scopes need an administrator.

## Decision

- **The app writes a QA log only when launched with `--qa-log`.** `open build/DrowsyDock.app --args --qa-log` makes it append every log line to a file too. Without the argument it creates no folder or file and sets no mirror, so normal use is unchanged. The argument only adds output; it changes no behaviour and accepts no input.
- **One call sends each line to both places.** Every log line in `Sources` goes through `MirroredLogger` (DockOverlayKit), which sends it to its `os.Logger` and then to `MirroredLogger.mirror`. The app sets the mirror to `QALogFile` at launch, before `AppCoordinator` logs its first line. `scripts/check.sh fast` fails if any other file imports `os` or `OSLog` or calls `NSLog`, so a new line can't skip the mirror.
- **The path is fixed:** `~/Library/Logs/DrowsyDock/qa.log`. Nothing can point the app at another file.
- **The line format is pure and tested.** `QALogLine` (DrowsyDockCore) writes `2026-11-10T01:31:07.123+01:00 DrowsyDock[812] notice battery: Changed: …`. That is the local time to the millisecond with its UTC offset, then the process and its pid, the level, the category and the message. A line break in a message becomes `\n`, so one message is one line. `qa-helper log-time` parses the time.
- **The writer protects the user's files.** `QALogFile`, in the app target:
  - creates the folder with mode 0700 and the file with 0600, and narrows either one that is wider;
  - opens both with `O_NOFOLLOW`, so a symbolic link at either path is refused, not followed;
  - checks the opened descriptors, not the paths: the folder must be a folder and the file a regular file, both owned by the user, and the file may have no other hard link. `O_NONBLOCK` keeps a FIFO at the path from blocking the launch, and the type check then refuses it;
  - starts the file over, with a note line, before a line would take it past 1 MiB. An `Overlay:` line lists every icon's frame: it is about 470 bytes for one icon and about 30 bytes more per icon, so the limit holds about 1,000 of them for a Dock of 20 icons.

  When it refuses the path, the app logs `No QA log: …` to the unified log and runs on without the file.
- **The script reads only its own lines from the file.**
  - The preflight notes the file's size when the run starts, and `mark_log` takes byte offsets after that. A read starts at that offset, or at 0 when the app has started the file over since.
  - It keeps only lines from the pid that `launch_app` found running this build's binary. That rules out another DrowsyDock and earlier runs.
  - Latency comes from each line's own time, as before.
  - At exit the script copies the run's lines to `build/qa/app.log` and relaunches the app without `--qa-log`.
- No entitlement is added, and the hardened runtime stays on (ADR 0005, ADR 0007).

## Alternatives considered

- **Write the file on every launch.** Every user would get a growing log file that only QA reads. The argument keeps normal use unchanged.
- **Take the path from the argument (`--qa-log PATH`).** Any process that can launch the app could then make it append to a file of its choosing. A fixed path under `~/Library/Logs` gives the script all it needs.
- **`sudo log stream`, or making the account an administrator for the run.** Both need the admin rights the owner doesn't want to use.
- **Read the app's stdout or stderr.** `open` drops both. Starting the executable directly from the terminal would make the terminal the process TCC holds responsible, so the app's own Accessibility grant would not be what the run tests.
- **A per-run token in each line instead of the pid.** The script finds the pid from this build's binary path, so the pid also shows which build wrote the line. A token would show only which launch did.

## Consequences

- Every `qa-live.sh` scenario runs from a standard account, with no `sudo`.
- Without `--qa-log`, the unified log gets the same text as before. Each message is now built as a `String` before `os.Logger` sees it, even at debug level when the system doesn't keep debug lines. The debug lines fire on state changes and power notifications, not on every frame.
- `--qa-log` adds one `fstat` and one `write` on the main thread per line, only while it is on.
- `~/Library/Logs/DrowsyDock/qa.log` stays after a run, at most 1 MiB. Deleting the folder is safe; the next `--qa-log` launch creates it again.
- If the app starts the file over in the middle of a check, the lines between the mark and the start-over are lost and that check can fail. A run that hits the limit that often should get a larger limit.
- A run killed with `kill -9` leaves the app running with `--qa-log` until it quits.
- `scripts/qa/check-app-log.sh` replays `Tests/LiveQAKitTests/Fixtures/qa.log` through the script's log reads. `QALogFixtureTests` pin that the fixture is what `QALogLine` writes and what `qa-helper` reads.
