# Releasing DrowsyDock

DrowsyDock ships as a zip of the app, signed with Emgee Labs LLC's Developer ID certificate, notarized by Apple and stapled. `scripts/release.sh` does every step from the build to `dist/DrowsyDock-<version>.zip`. This page covers what it needs from you once, the release sequence, and what to do when Apple rejects a build.

Agents and CI run only `scripts/release.sh --dry-run`. It signs ad hoc, skips every step that needs Apple, and writes `dist/DrowsyDock-<version>-dryrun.zip`, which is not for distribution. `scripts/check.sh task` runs it before every commit.

## 1. Enroll Emgee Labs LLC in the Apple Developer Program

DrowsyDock is published by Emgee Labs LLC, so the LLC enrolls as an **organization**. Organization enrollment needs the LLC's D-U-N-S number.

- **The D-U-N-S number.** As of 2026-11-22 the application is with D&B. When D&B issues the number, check that Apple's [D-U-N-S lookup](https://developer.apple.com/enroll/duns-lookup/) finds it before you enroll. Apple gets D&B's records with a delay, so a number D&B has issued can be missing from the lookup for a while. Enroll once the lookup shows it.
- **The legal entity name** you enter must match the D-U-N-S record exactly: `Emgee Labs LLC`, spelled and punctuated as D&B has it. A trade name or a different spelling stops the enrollment.
- **A website** on the organization's domain, publicly reachable: https://emgeelabs.io.
- **Legal authority.** The person who enrolls must be able to bind the LLC to Apple's agreements, for example as its owner. Apple may phone to confirm this. That person becomes the Account Holder.
- Enroll at https://developer.apple.com/programs/enroll/, signed in with the Apple ID that will be the Account Holder, and choose the organization option.

### One signing team

Releases are signed only with Emgee Labs LLC's Developer ID, and no release goes out before the LLC's enrollment. macOS ties a user's Accessibility grant to the app's code signature, which names the signing team's ID, so every release must come from the same team for users to keep their grant.

## 2. Create the Developer ID Application certificate

Create a **Developer ID Application** certificate. It is the one for apps distributed outside the Mac App Store. Don't use the others:

- **Apple Development** signs builds for your own devices. Gatekeeper rejects it on other Macs.
- **Mac App Distribution** is for the Mac App Store only.
- **Developer ID Installer** signs `.pkg` installers. DrowsyDock ships a zip.

Only the **Account Holder** can create a Developer ID certificate, so the person who enrolled does this:

1. In Xcode, open Settings ▸ Accounts, add the Account Holder's Apple ID, and select the Emgee Labs LLC team.
2. Click Manage Certificates, then + ▸ Developer ID Application. Xcode creates the private key in your login keychain and the certificate on Apple's side.
3. Back up the certificate with its private key: in Keychain Access, find "Developer ID Application: Emgee Labs LLC (TEAMID)", export it as a `.p12` with a strong password, and store it outside this repository, in your password manager for example. Without the private key you can't sign again, and a new certificate means a new private key. `.gitignore` and `scripts/check.sh` refuse `.p12` files in the repository.

Then check that the keychain has the identity:

```sh
security find-identity -v -p codesigning
```

One line should read `"Developer ID Application: Emgee Labs LLC (TEAMID)"`, where `TEAMID` is your team's 10-character ID. That whole quoted name is your `DEVELOPER_ID`. It is not a secret, but keep it out of the repository anyway: the repository writes only the `TEAMID` placeholder.

When you renew the certificate, the old and the new one can both be valid for a while, with the same name. The script's check still passes, but `codesign` then stops with "ambiguous" because two identities match `DEVELOPER_ID`. Export a backup of the old certificate, then delete it from your keychain, so only the new one matches.

## 3. Save the notary credentials in your keychain

`notarytool` reads its credentials from a keychain profile, and `scripts/release.sh` only knows the profile's name. Create the profile once, by hand, in your own terminal. Never put the password or the key in a script, a file in this repository, or CI.

Pick one of the two ways.

**An app-specific password.** At https://account.apple.com, open Sign-In and Security ▸ App-Specific Passwords and create one named "notarytool". Then run this, replacing `APPLE_ID` and `TEAMID`, and paste the password when it asks:

```sh
xcrun notarytool store-credentials drowsydock-notary --apple-id APPLE_ID --team-id TEAMID
```

**An App Store Connect API key.** In App Store Connect, open Users and Access ▸ Integrations ▸ Team Keys, create a key with the Developer role, and download its `AuthKey_KEYID.p8`. Apple lets you download it only once. Then run:

```sh
xcrun notarytool store-credentials drowsydock-notary \
  --key ~/Downloads/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER_ID
```

After that, the keychain holds the key. Move the `.p8` file into your password manager and delete it from Downloads. Never copy it into this repository.

Either way, check the profile:

```sh
xcrun notarytool history --keychain-profile drowsydock-notary
```

It lists your past submissions, none at first, and fails if the credentials are wrong.

## 4. Cut a release

Each release needs a new version. `scripts/release.sh` reads `CFBundleShortVersionString` from `Resources/Info.plist` and refuses to run unless the tree is clean and the tag `v<that version>` is at `HEAD`. Push the tag only after the release script succeeds, so a failed run can be fixed and tagged again.

```sh
# 1. Bump both versions (example: 0.2.0, build 2), check, and commit.
plutil -replace CFBundleShortVersionString -string 0.2.0 Resources/Info.plist
plutil -replace CFBundleVersion -string 2 Resources/Info.plist
scripts/check.sh task
git commit -am "chore: release 0.2.0"
# Merge it to main the usual way, then check out main at that commit.

# 2. Tag the release commit.
git tag -a v0.2.0 -m "DrowsyDock 0.2.0"

# 3. Build, sign, notarize, staple and zip. This takes a few minutes, most of it waiting for Apple.
DEVELOPER_ID="Developer ID Application: Emgee Labs LLC (TEAMID)" \
  NOTARY_PROFILE=drowsydock-notary scripts/release.sh

# 4. Push the tag and publish the zip and its checksum.
git push origin v0.2.0
gh release create v0.2.0 dist/DrowsyDock-0.2.0.zip dist/DrowsyDock-0.2.0.zip.sha256 \
  --verify-tag --title "DrowsyDock 0.2.0" --notes "What changed in 0.2.0."
```

Raise `CFBundleVersion` with every release too, so each build has its own number. `--verify-tag` makes `gh` stop if the tag isn't on GitHub yet, instead of creating it from the default branch.

Before you announce the release, do manual QA row 18.1 in [manual-qa.md](manual-qa.md): download the zip from the release page and open it on a Mac that has never run DrowsyDock.

### What the script checks

| Step | It stops when |
|---|---|
| Preflight | `DEVELOPER_ID` or `NOTARY_PROFILE` is unset; `DEVELOPER_ID` doesn't start with `Developer ID Application:` or isn't in `security find-identity -v -p codesigning`; `notarytool`, `stapler`, `ditto` or `spctl` is missing; the tree has uncommitted or untracked files; `v<version>` isn't at `HEAD`. It checks all of these before building. |
| Build | `scripts/bundle.sh` fails. It builds into `build/release/DrowsyDock.app` (`BUNDLE_DIR=build/release`), so the `build/DrowsyDock.app` you run day to day keeps its own signature. It signs with `DEVELOPER_ID`, the hardened runtime, no entitlements, and Apple's secure timestamp (`SIGN_TIMESTAMP=1`). |
| Verify | `codesign --verify --strict --deep` fails; the hardened runtime is missing; there are entitlements; the binary lacks `arm64` or `x86_64`; the first authority isn't `Developer ID Application`; `TeamIdentifier` isn't set; there is no `Timestamp=`. |
| Notarize | `notarytool submit --wait --timeout 2h` answers anything but `Accepted`. The script then prints the notary log. If Apple hasn't finished after 2 hours, it stops and prints the `notarytool info` command for the submission instead. |
| Staple and assess | `stapler staple` or `stapler validate` fails, or `spctl --assess --type execute -v` doesn't report `source=Notarized Developer ID`. |
| Package | Nothing left to check. It writes `dist/DrowsyDock-<version>.zip` and `dist/DrowsyDock-<version>.zip.sha256`. |

A run that gets past preflight first deletes `dist/DrowsyDock-<version>.zip` and its `.sha256`, so after a failed build, check, notarization or staple, `dist/` has no zip for that version. A run that fails preflight leaves `dist/` as it was. Running the script again starts over.

## 5. When Apple rejects a build

If notarization ends with any status other than `Accepted`, usually `Invalid`, the script prints Apple's log and the command that reads it again:

```sh
xcrun notarytool log SUBMISSION_ID --keychain-profile drowsydock-notary
```

The log is JSON. Read its `issues` list: each issue has a `severity`, the `path` inside the zip, a `message` and often a `docUrl` to Apple's explanation. The usual messages, and what to fix:

| Message | Cause |
|---|---|
| The signature does not include a secure timestamp. | The build was signed without `--timestamp`. `release.sh` sets `SIGN_TIMESTAMP=1`, so check that `bundle.sh` still passes it. |
| The executable does not have the hardened runtime enabled. | `--options runtime` is missing from `bundle.sh`'s `codesign` line. |
| The binary is not signed with a valid Developer ID certificate. | The certificate expired, was revoked, or isn't a Developer ID Application certificate. |

To see earlier submissions and their IDs: `xcrun notarytool history --keychain-profile drowsydock-notary`. If the script stopped because Apple hadn't finished after 2 hours, check that submission with `xcrun notarytool info SUBMISSION_ID --keychain-profile drowsydock-notary`, and run the script again once it shows `Accepted` or a rejection. A new run submits again.

Fix the cause, commit, and move the tag to the new commit before you run the script again: `git tag -d v0.2.0`, then `git tag -a v0.2.0 -m "DrowsyDock 0.2.0"`. This is safe as long as you haven't pushed the tag.

The script's self-test runs it against stub tools modelled on Apple's documented output, because no agent or CI run can call Apple. Your first real run is the first time it meets the real `notarytool`, `stapler` and `spctl`. If the script misreads their output, for example if it reports `notarytool submit exited 0 without a status` after an accepted submission, note the output in row 18.1 and report it, so the stubs and the script can be fixed.
