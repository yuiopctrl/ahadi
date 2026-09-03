#!/usr/bin/env bash
# Wraps `flutter build apk` and renames the produced APK from Flutter's
# default "app-<mode>.apk" naming to "changisha.apk".
#
# The rename can't be done from Gradle: `flutter build apk` checks for its
# hardcoded "app-<mode>.apk" path immediately after Gradle exits to confirm
# the build succeeded, so renaming/deleting it inside the Gradle run makes
# the command report a false failure (exit 1) even though the build worked.
# Doing the rename here, after `flutter build apk` has already finished and
# reported success, avoids that entirely.
#
# Usage: same arguments you'd pass to `flutter build apk`, e.g.:
#   scripts/build_apk.sh --release --dart-define=API_BASE_URL=https://api.yuiop.work/api/v1
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk "$@"

apk_dir="build/app/outputs/flutter-apk"
shopt -s nullglob
for f in "$apk_dir"/app-*.apk; do
  mv "$f" "$apk_dir/changisha.apk"
done
for f in "$apk_dir"/app-*.apk.sha1; do
  mv "$f" "$apk_dir/changisha.apk.sha1"
done
