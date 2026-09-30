# RCall iOS

Native Swift client for the listener role.

## Build

```bash
xcodebuild \
  -project RCall.xcodeproj \
  -scheme RCall \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The backend URL (`https://rcall.tindapp.com`) is bundled in `Resources/Config.plist`. GitHub Actions builds the app with Xcode 27 for iOS 27. The downloaded IPA only needs signing and installation; no backend configuration patch is required. Apple account credentials stay in the local signing environment.
