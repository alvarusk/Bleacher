# iOS CI and Release

Bleacher uses two separate GitHub Actions workflows:

- `iOS CI` for pull requests
- `iOS Release` for release builds and TestFlight uploads

## Triggers

### CI

- `pull_request` to `main`
- Builds the app for the iOS Simulator
- Does not sign or export an IPA

### Release

- `push` to `main`
- `push` of tags matching `v*`
- `workflow_dispatch`
- Builds a signed archive on macOS
- Exports an `.ipa`
- Uploads the IPA to TestFlight with fastlane `pilot`

## Signing model

CI uses manual signing only. The Xcode project stays in manual mode and the workflow reinforces that setup during archive.

Required project values:

- Bundle id: `com.kingdomm.bleacher`
- Apple team: `R24Q9H7VFW`

## Required secrets

### Certificate

- `APPLE_CERTIFICATES_P12_BASE64`
- `APPLE_CERTIFICATES_P12_PASSWORD`

### App Store Connect API

- `APPSTORE_API_PRIVATE_KEY`
- `APPSTORE_API_KEY_ID`
- `APPSTORE_ISSUER_ID`

### Provisioning profile

- `APPLE_IOS_APPSTORE_PROFILE_BASE64`

## Versioning

The release workflow reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from the Xcode project.

- If the workflow runs from a tag, the tag must match `vMARKETING_VERSION`
- The build number is taken from `GITHUB_RUN_NUMBER` during CI

## Current scope

This first pass only uploads to TestFlight.

The App Store submission path is intentionally left out for now and can be added later once the upload path is validated end to end.
