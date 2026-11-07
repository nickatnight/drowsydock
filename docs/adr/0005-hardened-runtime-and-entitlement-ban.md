# ADR-0005: Sign with the hardened runtime and ban the entitlements that weaken it

## Status

Accepted (job 002, round-1 security review, 2026-11-06). The entitlement ban is superseded by ADR 0007, which bans every entitlement.

## Context

From plan slice 4 on, DrowsyDock holds the Accessibility grant. That grant lets a process read every app's interface and post input events. TCC ties the grant to the main executable's code identity. `docs/dev-signing.md` gives the user a stable self-signed identity, so the grant survives rebuilds.

Without the hardened runtime, dyld honours `DYLD_INSERT_LIBRARIES`. Any process running as the same user could then start DrowsyDock with its own library and use the grant without a prompt. The round-1 security review showed this with a proof of concept: a constructor in an injected dylib ran inside the app.

## Decision

- `scripts/bundle.sh` always signs with `codesign --options runtime`, whatever `SIGN_IDENTITY` is.
- `scripts/check.sh task` fails when:
  - `codesign -dv` doesn't show the `runtime` flag, or
  - the signed entitlements contain `allow-dyld-environment-variables`, `disable-library-validation`, `allow-unsigned-executable-memory` or `get-task-allow`.
- The CONSTRAINTS.md Bundle row states both rules.

## Alternatives considered

- **Rely on Developer ID notarization later** (plan slice 18). Development builds would stay injectable until then, and the self-signed identity makes their grant last indefinitely.
- **Fail on any entitlement at all.** That is stricter and simpler, because `bundle.sh` passes none today. It is left as follow-up G7, because the spec doesn't ask for it and some entitlements are harmless (Apple Events, for example).

## Consequences

- The injection proof of concept no longer runs against the bundle (`flags=0x10002(adhoc,runtime)`), and the app still launches.
- Library validation applies. The app loads only system libraries, so nothing breaks today, but a future dylib or plug-in would need the same signing team.
- `com.apple.security.cs.allow-jit` and `com.apple.security.cs.debugger` pass the check. Neither allows injection into the app (follow-up G7).
- The release script (plan slice 18) must keep `--options runtime`. Notarization requires it anyway.
