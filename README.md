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

The backend URL is stored in `Resources/Config.plist` and must be patched before signing for a real device.
