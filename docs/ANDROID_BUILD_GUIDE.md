# OneDesk Android 로컬 빌드 가이드 (macOS)

## 요구 사항

- macOS (Apple Silicon / aarch64)
- Xcode Command Line Tools
- Homebrew
- Android Studio (SDK, NDK 포함)

## 1. Rust 설치

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.75.0
source "$HOME/.cargo/env"
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 3.1.2 --locked
```

## 2. Android SDK / NDK 설치

Android Studio에서 SDK Manager를 통해 설치하거나 수동 설치:

- **SDK**: `~/Library/Android/sdk`
- **NDK**: `~/Library/Android/sdk/ndk/27.0.12077973` (r27c)

```bash
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973
export ANDROID_NDK=$ANDROID_NDK_HOME
```

## 3. 빌드 도구 설치

```bash
brew install llvm pkg-config cmake nasm
brew install --cask flutter
```

## 4. vcpkg 설정

```bash
git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg
cd ~/vcpkg
git checkout 120deac3062162151622ca4860575a33844ba10b
./bootstrap-vcpkg.sh
export VCPKG_ROOT=~/vcpkg
```

## 5. CRLF 패치 파일 변환 (중요)

Windows에서 작성된 패치 파일이 CRLF 줄바꿈을 사용하면 빌드가 실패합니다.

```bash
cd /path/to/onedesk
find res/vcpkg -name "*.patch" -exec perl -pi -e 's/\r\n/\n/g' {} +
find res/vcpkg -type f \( -name "*.cmake" -o -name "*.in" -o -name "*.json" -o -name "*.diff" \) -exec perl -pi -e 's/\r\n/\n/g' {} +
find res/vcpkg/ffmpeg/patch -name "*.patch" -exec perl -pi -e 's/\r\n/\n/g' {} +
```

## 6. vcpkg Android 의존성 설치

```bash
export VCPKG_ROOT=~/vcpkg
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973
export ANDROID_NDK=$ANDROID_NDK_HOME

$VCPKG_ROOT/vcpkg install --triplet arm64-android --x-install-root="$VCPKG_ROOT/installed"
```

설치되는 패키지:
- **aom**: AV1 비디오 코덱
- **cpu-features**: CPU 기능 감지 (Android 전용)
- **ffmpeg**: 비디오 인코딩/디코딩 (MediaCodec 하드웨어 가속)
- **libjpeg-turbo**: JPEG 이미지 처리
- **libvpx**: VP8/VP9 비디오 코덱
- **libyuv**: YUV 이미지 변환
- **oboe**: 오디오 입출력 (Android 전용)
- **opus**: 오디오 코덱

## 7. Rust 크로스 컴파일

```bash
export VCPKG_ROOT=~/vcpkg
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973
export ANDROID_NDK=$ANDROID_NDK_HOME
export AARCH64_LINUX_ANDROID_OPENSSL_NO_VENDOR=0
export OPENSSL_NO_VENDOR=0
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot -I$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include -I$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include/aarch64-linux-android"

cargo ndk --platform 21 --target aarch64-linux-android build --release --features flutter,hwcodec
```

주요 환경 변수:
- `AARCH64_LINUX_ANDROID_OPENSSL_NO_VENDOR=0`: OpenSSL을 vendored 모드로 소스 빌드 (`.cargo/config.toml`의 `OPENSSL_NO_VENDOR=1` 오버라이드)
- `BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android`: bindgen이 Android NDK sysroot 헤더를 찾을 수 있도록 설정

## 8. .so 파일 복사

```bash
mkdir -p flutter/android/app/src/main/jniLibs/arm64-v8a
cp target/aarch64-linux-android/release/liblibonedesk.so \
   flutter/android/app/src/main/jniLibs/arm64-v8a/libonedesk.so
```

## 9. Flutter APK 빌드

```bash
cd flutter
flutter clean
flutter pub get
flutter build apk --release
```

## 10. 디바이스 설치

```bash
# 연결된 디바이스 확인
~/Library/Android/sdk/platform-tools/adb devices

# APK 설치
~/Library/Android/sdk/platform-tools/adb install -r \
  flutter/build/app/outputs/flutter-apk/app-release.apk
```

## 전체 빌드 한 줄 명령어

```bash
# 환경 변수 설정
export VCPKG_ROOT=~/vcpkg
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.0.12077973
export ANDROID_NDK=$ANDROID_NDK_HOME
export AARCH64_LINUX_ANDROID_OPENSSL_NO_VENDOR=0
export OPENSSL_NO_VENDOR=0
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot -I$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include -I$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/include/aarch64-linux-android"

# 클린 빌드
cargo clean && \
cargo ndk --platform 21 --target aarch64-linux-android build --release --features flutter,hwcodec && \
cp target/aarch64-linux-android/release/liblibonedesk.so flutter/android/app/src/main/jniLibs/arm64-v8a/libonedesk.so && \
cd flutter && flutter clean && flutter pub get && flutter build apk --release && \
cd .. && ~/Library/Android/sdk/platform-tools/adb install -r flutter/build/app/outputs/flutter-apk/app-release.apk
```

## 빌드 결과물

- Rust `.so`: `target/aarch64-linux-android/release/liblibonedesk.so` (~27MB)
- APK: `flutter/build/app/outputs/flutter-apk/app-release.apk` (~134MB)

## 환경 변수 요약

| 변수 | 값 | 설명 |
|------|-----|------|
| VCPKG_ROOT | ~/vcpkg | vcpkg 설치 경로 |
| ANDROID_NDK_HOME | ~/Library/Android/sdk/ndk/27.0.12077973 | Android NDK 경로 |
| OPENSSL_NO_VENDOR | 0 | OpenSSL vendored 빌드 활성화 |
| AARCH64_LINUX_ANDROID_OPENSSL_NO_VENDOR | 0 | 타겟별 OpenSSL vendored 오버라이드 |
| BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android | --sysroot=... | NDK sysroot 헤더 경로 |

## 트러블슈팅

### OpenSSL 빌드 실패 (C:/tools/vcpkg/... 경로)
`.cargo/config.toml`에 Windows 경로가 하드코딩되어 있습니다. `AARCH64_LINUX_ANDROID_OPENSSL_NO_VENDOR=0`으로 vendored 빌드를 사용하세요.

### bindgen 'stdlib.h' / 'inttypes.h' not found (macOS에서 빌드 시)
원본 RustDesk는 Android를 Ubuntu CI에서만 빌드합니다. macOS에서는 Xcode의 `libclang`이 NDK sysroot와 충돌하여 `kcp-sys`와 `scrap`의 bindgen이 실패합니다.

**해결**: `libs/scrap/build.rs`와 `libs/kcp-sys/build.rs`에 Android NDK sysroot를 직접 `clang_arg`로 추가하는 패치가 적용되어 있습니다. `kcp-sys`는 `Cargo.toml`의 `[patch]` 섹션으로 로컬 복사본(`libs/kcp-sys`)을 사용합니다.

`BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android`도 설정하세요.

### cargo-ndk 미설치
```bash
cargo install cargo-ndk --version 3.1.2 --locked
```

### aarch64-linux-android 타겟 미설치
```bash
rustup target add aarch64-linux-android
```

### vcpkg arm64-android 패키지 미설치
6단계의 vcpkg install 명령을 실행하세요. `~/vcpkg/installed/arm64-android/` 디렉토리가 존재해야 합니다.
