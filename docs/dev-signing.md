# Development signing

macOS keys an Accessibility grant to the app's code signature. `scripts/bundle.sh` signs ad hoc by default (`SIGN_IDENTITY=-`). An ad-hoc signature changes with every build, so macOS forgets the grant after each rebuild and you have to grant it again.

A self-signed code-signing certificate keeps the signature's identity the same across builds, so the grant survives rebuilds. It is for your own Mac only. It can't be used to distribute the app; that needs a Developer ID (see plan slice 18).

The scripts never create certificates or touch the keychain. You run these steps yourself, once.

## Hardened runtime

`scripts/bundle.sh` signs with `--options runtime`, whatever the identity, and `scripts/check.sh task` fails if the signature lacks the `runtime` flag. With the hardened runtime, dyld ignores `DYLD_INSERT_LIBRARIES` and the other `DYLD_*` variables. A stable identity is safe only because of this: without it, any process running as you could launch DrowsyDock with an injected library and use its Accessibility grant without a prompt. Don't add the `com.apple.security.cs.allow-dyld-environment-variables` or `com.apple.security.cs.disable-library-validation` entitlements.

## Create the certificate

1. Open Keychain Access and choose Keychain Access ▸ Certificate Assistant ▸ Create a Certificate….
2. Name: `DrowsyDock Dev`. Identity Type: Self Signed Root. Certificate Type: Code Signing.
3. Click Create, then Done. The certificate and its private key go into your login keychain.
4. Check that codesign can find it:

   ```
   security find-identity -p codesigning
   ```

   The list should include `"DrowsyDock Dev"`. It appears under "Matching identities" but may be missing from "Valid identities", because no trusted authority issued it. codesign accepts it anyway.

## Build with it

```
SIGN_IDENTITY="DrowsyDock Dev" scripts/bundle.sh
codesign --verify --strict build/DrowsyDock.app
codesign -dv build/DrowsyDock.app 2>&1 | grep Authority
```

The last command prints `Authority=DrowsyDock Dev`. The first time codesign uses the key, macOS asks whether it may. Choose Always Allow so later builds don't ask again.

`scripts/check.sh task` still signs ad hoc, because it calls `scripts/bundle.sh` without `SIGN_IDENTITY`. Export the variable in your shell if you want every build signed with the certificate:

```
export SIGN_IDENTITY="DrowsyDock Dev"
```

## Grant Accessibility once

1. `open build/DrowsyDock.app`, then choose `Grant Accessibility…` from the menu.
2. Turn DrowsyDock on in System Settings ▸ Privacy & Security ▸ Accessibility.
3. Rebuild with the same `SIGN_IDENTITY` and relaunch. The menu should still read `Accessibility: Granted`.

If an earlier ad-hoc build left a stale entry in the list, clear it and grant again:

```
tccutil reset Accessibility com.drowsydock.DrowsyDock
```

## The grant looks on, but the app is untrusted

After a rebuild with ad-hoc signing, System Settings ▸ Privacy & Security ▸ Accessibility can still show DrowsyDock switched on, while the menu keeps saying `Grant Accessibility…` and no overlay appears.

Why: TCC stores a grant against the app's code requirement, which it takes from the signature. An ad-hoc signature has no certificate, so its requirement pins the exact hash of the code (the `cdhash`), and every rebuild has a new hash. The list shows one row per bundle identifier and path, so the old row, with the old hash, stays on. The new build doesn't match it, so `AXIsProcessTrusted()` returns false. Turning the switch off and on again doesn't help, because it re-enables the old requirement.

Fix it by replacing the entry:

1. Quit DrowsyDock.
2. In the Accessibility list, select DrowsyDock and click −.
3. Launch the new build and choose `Grant Accessibility…`, then turn the new DrowsyDock entry on. Or click + and add `build/DrowsyDock.app`.

`tccutil reset Accessibility com.drowsydock.DrowsyDock` does the same as step 2.

A stable dev certificate avoids all this. With `SIGN_IDENTITY="DrowsyDock Dev"`, the code requirement names the certificate and the bundle identifier instead of a hash, so every rebuild still matches the grant.

## Never commit signing material

`.gitignore` excludes `*.p12`, `*.cer`, `*.p8` and provisioning profiles, and `scripts/check.sh` fails if one is tracked. Don't export the certificate into the repository.
