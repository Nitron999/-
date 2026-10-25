name: Build APK

on:
  push:
    branches: [ "main" ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.x'
          channel: 'stable'

      - name: Generate Android project files
        run: flutter create . --org com.zhigomer.app --project-name zhigomer --platforms=android

      - name: Configure SDK 34 and Permissions
        run: |
          sed -i 's/flutter.compileSdkVersion.*/flutter.compileSdkVersion=34/g' android/local.properties || true
          sed -i 's/flutter.targetSdkVersion.*/flutter.targetSdkVersion=34/g' android/local.properties || true
          sed -i 's/flutter.compileSdkVersion/34/g' android/app/build.gradle || true
          sed -i 's/flutter.targetSdkVersion/34/g' android/app/build.gradle || true
          sed -i '/<application/i \    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />' android/app/src/main/AndroidManifest.xml

      - name: Install dependencies
        run: flutter pub get

      - name: Build APK
        run: flutter build apk --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
