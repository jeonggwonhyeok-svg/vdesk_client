# OneDesk iOS 로컬 빌드 가이드

## 요구 사항

- macOS (Apple Silicon / aarch64)
- Xcode + iOS SDK
- Homebrew

## 1. Rust 설치 (v1.75+)

iOS 빌드는 Rust 1.75 이상이 필요합니다. macOS에서는 1.81 권장.

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.81.0
source "$HOME/.cargo/env"
rustup component add rustfmt
rustup target add aarch64-apple-ios
```

## 2. 빌드 도구 설치

```bash
brew install nasm yasm pkg-config cmake cocoapods
brew install --cask flutter
```

설치되는 도구:
- **nasm**: 어셈블리 컴파일러 (aom, libjpeg-turbo 등)
- **yasm**: 어셈블리 컴파일러 (libvpx 등)
- **pkg-config**: 라이브러리 경로 검색
- **cmake**: vcpkg 의존성 빌드
- **CocoaPods**: iOS Flutter 플러그인 의존성 관리
- **Flutter 3.41.0**: UI 프레임워크

## 3. vcpkg 설정

```bash
git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg
cd ~/vcpkg
git checkout 120deac3062162151622ca4860575a33844ba10b
./bootstrap-vcpkg.sh
```

## 4. CRLF 패치 파일 변환 (중요)

Windows에서 작성된 패치 파일이 CRLF 줄바꿈을 사용하면 macOS에서 ffmpeg 빌드가 실패합니다.
반드시 LF로 변환해야 합니다.

```bash
cd /path/to/onedesk
find res/vcpkg -name "*.patch" -exec perl -pi -e 's/\r\n/\n/g' {} +
find res/vcpkg -type f \( -name "*.cmake" -o -name "*.in" -o -name "*.json" -o -name "*.diff" \) -exec perl -pi -e 's/\r\n/\n/g' {} +
find res/vcpkg/ffmpeg/patch -name "*.patch" -exec perl -pi -e 's/\r\n/\n/g' {} +
```

## 5. vcpkg 의존성 설치 (arm64-ios)

```bash
export VCPKG_ROOT=~/vcpkg
$VCPKG_ROOT/vcpkg install --triplet arm64-ios --x-install-root="$VCPKG_ROOT/installed"
```

설치되는 패키지:
- **aom**: AV1 비디오 코덱
- **ffmpeg**: 비디오 인코딩/디코딩
- **libjpeg-turbo**: JPEG 이미지 처리
- **libvpx**: VP8/VP9 비디오 코덱
- **libyuv**: YUV 이미지 변환
- **opus**: 오디오 코덱

> **참고**: `arm64-ios`는 vcpkg community triplet입니다. 경고가 표시되지만 정상 동작합니다.

## 6. Flutter-Rust 브릿지 생성

```bash
# 브릿지 도구 설치
cargo install cargo-expand --version 1.0.95 --locked
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked

# Flutter 의존성 설치 (extended_text 패치 필요)
cd flutter
sed -i '' -e 's/extended_text: 14.0.0/extended_text: 13.0.0/g' pubspec.yaml
flutter pub get
cd ..

# 브릿지 코드 생성
flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/ios/Runner/bridge_generated.h
```

> **참고**: `bridge_generated.h`가 `flutter/ios/Runner/`에 생성되어야 합니다.
> 이미 `flutter/macos/Runner/bridge_generated.h`가 있다면 복사해도 됩니다:
> ```bash
> cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h
> ```

## 7. iOS 프로젝트 설정 (중요)

### 7-1. sqflite 프레임워크 참조 제거

`sqflite` 패키지가 `sqflite_darwin`으로 이름이 변경되었으므로, Xcode 프로젝트에 남아있는 구버전 참조를 제거해야 합니다.

**`flutter/ios/Runner.xcodeproj/project.pbxproj`:**

3곳의 `OTHER_LDFLAGS`에서 sqflite 관련 2줄을 제거:
```
// 제거할 줄
"-framework",
"\"sqflite\"",
```

### 7-2. CocoaPods 설치

```bash
cd flutter/ios
pod install
cd ../..
```

## 8. Rust 라이브러리 빌드

```bash
export VCPKG_ROOT=~/vcpkg
cargo build --features flutter,hwcodec --release --target aarch64-apple-ios --lib
```

빌드 결과: `target/aarch64-apple-ios/release/liblibonedesk.a`

빌드 시간: 약 2분 (Apple Silicon 기준)

## 9. Flutter iOS 앱 빌드

```bash
cd flutter
flutter pub get
flutter build ipa --release --no-codesign
```

빌드 과정:
1. CocoaPods 의존성 확인 (`pod install`)
2. Xcode 아카이브 생성 (`xcodebuild archive`)
3. `--no-codesign`으로 코드사인 생략

## 10. 코드사인 및 IPA 생성 (배포 시)

`--no-codesign`으로 빌드한 경우 아카이브만 생성됩니다.
실제 기기 배포 또는 App Store 배포를 위해서는 Apple Developer 인증서가 필요합니다.

```bash
# 코드사인 포함 빌드
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist
```

또는 Xcode에서 직접 아카이브를 열어 배포할 수 있습니다:
```bash
open flutter/build/ios/archive/Runner.xcarchive
```

## 빌드 결과물

- Xcode Archive: `flutter/build/ios/archive/Runner.xcarchive` (~254MB)
- IPA 파일: `flutter/build/ios/ipa/*.ipa` (코드사인 시)

## 빌드 정보

| 항목 | 값 |
|------|-----|
| Version | 1.4.4 |
| Build Number | 62 |
| Display Name | OneDesk |
| Bundle ID | com.carriez.flutterHbb |
| Deployment Target | iOS 13.0 |

## 환경 변수 요약

| 변수 | 값 | 설명 |
|------|-----|------|
| VCPKG_ROOT | ~/vcpkg | vcpkg 설치 경로 |
| RUST_VERSION | 1.75+ | Rust 최소 버전 |
| FLUTTER_VERSION | 3.41.0 | Flutter 버전 |
| VCPKG_COMMIT_ID | 120deac3... | vcpkg 커밋 해시 |

## 트러블슈팅

### bridge_generated.h not found
`flutter/ios/Runner/bridge_generated.h` 파일이 없는 경우입니다.
6단계에서 브릿지 코드를 생성하거나, macOS 버전을 복사하세요:
```bash
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h
```

### Framework 'sqflite' not found
`project.pbxproj`에 구버전 `sqflite` 프레임워크 참조가 남아있습니다.
7-1 단계에서 `-framework "sqflite"` 관련 줄을 제거하세요.

### ffmpeg 빌드 실패 (configure syntax error)
패치 파일의 CRLF 줄바꿈이 원인입니다. 4단계의 CRLF 변환을 실행하세요.

### CocoaPods xcconfig 경고
`pod install` 후 xcconfig 관련 경고가 표시될 수 있습니다.
빌드에는 영향이 없으나, 필요시 `flutter/ios/Flutter/Release.xcconfig`에 Pods 설정을 포함하세요:
```
#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
```

### arm64-ios community triplet 경고
vcpkg에서 `arm64-ios`는 community triplet이므로 경고가 표시됩니다.
정상적으로 빌드되며 무시해도 됩니다.
