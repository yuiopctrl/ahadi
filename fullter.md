cd ~/Desktop/customers/2026/ahadi/apps/mobile

# Quality checks
dart format lib test
flutter analyze
flutter test

# Development
flutter run \
  --dart-define=API_BASE_URL=https://api.yuiop.work/api/v1

# Release testing
flutter run --release \
  --dart-define=API_BASE_URL=https://api.yuiop.work/api/v1

# APK
flutter build apk \
  --release \
  --dart-define=API_BASE_URL=https://api.yuiop.work/api/v1