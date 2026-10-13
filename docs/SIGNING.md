# Signing and notarization

The builds are **ad-hoc signed**. They run, but macOS Gatekeeper shows
"the developer cannot be verified" on first launch, and users must
right-click → Open once.

This page covers what changes once you have a paid Apple Developer account
($99/year).

## Why ad-hoc signing causes a recurring problem

TCC — the system that stores permission grants — identifies an app by its code
signature. An ad-hoc signature has no stable team identity, so **the identity
changes every time you rebuild**.

The practical effect: you grant GazeFocus Accessibility permission, rebuild it,
and the running app is refused even though System Settings still shows the
checkbox ticked. During development the fix is to remove the entry with the −
button and re-add it. A Developer ID signature makes the identity stable and
the problem disappears.

## With a Developer ID

### 1. Install the certificate

Join the Apple Developer Program, then create a **Developer ID Application**
certificate and install it in your keychain. Confirm it is there:

```sh
security find-identity -v -p codesigning
```

### 2. Build signed

`build-app.sh` already reads an identity from the environment:

```sh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./scripts/build-app.sh GazeFocus com.gazefocus.app "GazeFocus"
```

The hardened runtime is already enabled and each app already has an
entitlements file. GazeFocus declares the camera entitlement; all three are
unsandboxed, which is required — reading other processes' counters and driving
the Accessibility API are both incompatible with the sandbox.

### 3. Remove the timestamp override

`build-app.sh` passes `--timestamp=none`, which is fine for ad-hoc builds but
**must be removed for distribution** — notarization requires a secure
timestamp. In `SIGN_ARGS`, use `--timestamp` whenever `CODESIGN_IDENTITY` is
something other than `-`.

### 4. Notarize

Apple must scan the build before Gatekeeper will accept it silently.

```sh
# One-time: store an app-specific password (appleid.apple.com -> Sign-In and Security)
xcrun notarytool store-credentials "notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

./scripts/make-dmg.sh GazeFocus

xcrun notarytool submit dist/GazeFocus.dmg --keychain-profile "notary" --wait
```

If it is rejected, read the log — it names the exact binary and reason:

```sh
xcrun notarytool log <submission-id> --keychain-profile "notary"
```

### 5. Staple

Stapling attaches the ticket so the check also works offline:

```sh
xcrun stapler staple dist/GazeFocus.dmg
xcrun stapler validate dist/GazeFocus.dmg
```

### 6. Verify what a user will actually see

```sh
spctl --assess --type open --context context:primary-signature -v dist/GazeFocus.dmg
```

`accepted` means no warning on first launch.

## A note on AFK and private API

AFK calls `SACLockScreenImmediate` from `login.framework`, resolved at runtime
with `dlopen`/`dlsym`. This is a private symbol.

That is fine for Developer ID distribution outside the App Store — notarization
does not reject private API use. It **would** be rejected by App Store review.
If you ever want App Store distribution, AFK would need to fall back to
synthesizing ⌃⌘Q, which it already does when the symbol cannot be resolved.
