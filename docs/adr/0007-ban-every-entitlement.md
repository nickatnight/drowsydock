# ADR-0007: Ban every entitlement in the development bundle

## Status

Accepted (job 003, follow-up G7 from job 002). Supersedes the entitlement part of ADR 0005. The hardened-runtime part of ADR 0005 stands.

## Context

ADR 0005 made `scripts/check.sh task` fail on four entitlements that weaken the hardened runtime: `allow-dyld-environment-variables`, `disable-library-validation`, `allow-unsigned-executable-memory` and `get-task-allow`. Others, such as `com.apple.security.cs.allow-jit` and `com.apple.security.cs.debugger`, passed. ADR 0005 left "fail on any entitlement" as follow-up G7.

`scripts/bundle.sh` passes no `--entitlements` file, so the signed bundle carries no entitlement blob at all (`codesign -d --entitlements - --xml` prints 0 bytes). Any entitlement therefore means someone changed the signing step. The spec's Boundaries section already lists "adding entitlements" under "Ask first".

## Decision

- `scripts/check.sh task` fails when `codesign -d --entitlements - --xml build/DrowsyDock.app` prints anything. It lists the entitlement keys it found.
- The CONSTRAINTS.md Bundle row says so.
- An entitlement that the app really needs (for example Apple Events, if a later slice ever needs it) is added by asking first, then by changing this check and recording the reason in a new ADR.

## Alternatives considered

- **Keep the list of four.** A list only catches the entitlements someone thought of. A new weakening entitlement, or a typo in the list, would pass.
- **Allow an empty dictionary.** It grants nothing, but it still means the signing changed, and allowing it would need XML parsing in shell.

## Consequences

- The check is simpler and stricter: one test on the blob's length, with no list to keep current.
- `scripts/release.sh` (plan slice 18) must also sign without entitlements, or change this check with an ADR.
