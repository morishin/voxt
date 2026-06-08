# Release & Distribution Guide (For Developers)

Voxt is distributed **outside the App Store**. A Developer ID-signed, Apple-notarized `.zip` is distributed via
**GitHub Releases (`morishin/voxt`)**. The app checks the latest GitHub release to display whether an update is available.

## Distribution Overview

```
Developer pushes a v* tag
        │
        ▼
GitHub Actions (macos-26 hosted runner / .github/workflows/release.yml)
  1. Import Developer ID certificate into a temporary keychain
  2. xcodebuild archive (Release, manual signing, --timestamp, Hardened Runtime)
  3. xcodebuild -exportArchive (ExportOptions.plist / developer-id)
  4. xcrun notarytool submit --wait (submit notarization request to Apple)
  5. xcrun stapler staple (attach ticket to .app)
  6. gh release create attaches Voxt.zip to Releases
        │
        ▼
User downloads Voxt.zip from Releases
        │
        ▼
App (Settings → About) checks releases/latest and displays update availability
```

No self-hosted runner is used. The workflow runs entirely on GitHub-hosted `macos-26` (with Xcode 26).

## Prerequisites

- Apple Developer Program membership (Team ID: `4GERXBURZN`)
- **Developer ID Application** certificate + private key
- Xcode 26 / macOS 26 required for local development and manual builds (for Apple Intelligence / FoundationModels)

## GitHub Secrets (Registered in `morishin/voxt` Settings → Secrets and variables → Actions)

The release workflow uses the following 6 repository secrets. They are not passed to PRs from forks, making it safe for a public repository.

| Secret Name | Content | How to Create |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application certificate (.p12) | Export the certificate from Keychain Access under "My Certificates" as `.p12` → `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password set when exporting the `.p12` above | Set in the `.p12` export dialog |
| `KEYCHAIN_PASSWORD` | Password for the temporary keychain created on CI | Any string is fine |
| `APPLE_ID` | Apple ID (email address) used for notarization | Developer account email |
| `APPLE_APP_PASSWORD` | **App-specific password** for notarization (not the regular login password) | Generate at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | Team ID (`4GERXBURZN`) | Apple Developer Membership page |

> The Team ID itself is not sensitive and is also written in `project.pbxproj` under `DEVELOPMENT_TEAM`,
> but it is also stored as a secret to centralize references from the workflow.

## Release Procedure

1. Bring `main` up to date and confirm that all changes intended for the release have been merged.
2. Tag the version and push (the tag name becomes the app version as-is).
   ```sh
   git switch main && git pull
   git tag v1.0
   git push origin v1.0
   ```
3. Monitor the `Release` workflow progress in the **Actions** tab on GitHub (notarization may take a few minutes).
4. After completion, confirm that `Voxt.zip` is attached to **Releases**.

### About Version Numbers
- The workflow overwrites `MARKETING_VERSION` with the tag name (e.g., `v1.2` → `1.2`), so there is no need to manually update `project.pbxproj`.
- This ensures the app's `CFBundleShortVersionString` matches the release tag, so the update check works correctly.
- `CURRENT_PROJECT_VERSION` (build number) uses the Actions run number.

## How the In-App Update Check Works

- Implementation: `Voxt/Services/UpdateChecker.swift`
- Sends a HEAD request to `https://github.com/morishin/voxt/releases/latest` and extracts the version from the end of the redirect URL (`/releases/tag/vX.Y`).
- Compares it against the current `CFBundleShortVersionString` using `.numeric` comparison, and if a newer version is found, displays "Update Available" in Settings → About with a link to the release page.
- **If the referenced repository changes**, update `latestReleaseURL` in `UpdateChecker.swift`.
- `com.apple.security.network.client` is added to `Voxt/Voxt.entitlements` for this external network request.

## Manual Local Release (Without CI)

Fallback for when CI is unavailable or in an emergency. Run on a Mac with Xcode 26.

```sh
xcodebuild archive -project Voxt.xcodeproj -scheme Voxt -configuration Release \
  -archivePath /tmp/Voxt.xcarchive -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=4GERXBURZN OTHER_CODE_SIGN_FLAGS="--timestamp"

xcodebuild -exportArchive -archivePath /tmp/Voxt.xcarchive \
  -exportPath /tmp/export -exportOptionsPlist ExportOptions.plist

ditto -c -k --keepParent /tmp/export/Voxt.app /tmp/Voxt.zip
xcrun notarytool submit /tmp/Voxt.zip --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN --wait
xcrun stapler staple /tmp/export/Voxt.app
ditto -c -k --keepParent /tmp/export/Voxt.app /tmp/Voxt.zip   # re-zip after stapling

gh release create v1.0 /tmp/Voxt.zip --title v1.0 --generate-notes
```

## Troubleshooting

- **Signing fails**: The certificate may be expired, or the private key for the Developer ID Application may be missing from "My Certificates." Check with `security find-identity -v -p codesigning`.
- **Notarization returns `Invalid`**: Retrieve the log to identify the cause.
  ```sh
  xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN
  ```
  Common causes: Hardened Runtime disabled, missing secure timestamp, unsigned binaries included in the signed target, etc. This project already has `ENABLE_HARDENED_RUNTIME=YES` and `--timestamp` configured.
- **`macos-26` runner not found**: Check the availability of GitHub runner images ([actions/runner-images](https://github.com/actions/runner-images)). If the provided label has changed, update `runs-on` in `release.yml`.
- **App stays "Up to date" and does not detect updates**: Check whether Releases has a release in `vX.Y` tag format and whether the reference URL in `UpdateChecker.swift` is correct.
