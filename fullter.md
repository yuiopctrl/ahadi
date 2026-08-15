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


 ssh root@162.0.211.96
 su - deploy

1. Apply new Supabase migration/RPCs
2. Push code to Git
3. Pull on VPS
4. Rebuild/restart API
5. Test API health
6. Run Flutter again