# CLAUDE.md

이 파일은 Claude Code (claude.ai/code)가 이 저장소에서 작업할 때 참고하는 가이드입니다.

## 개발 명령어

### 빌드 명령어
- `cargo run` - 데스크톱 애플리케이션 빌드 및 실행 (libsciter 라이브러리 필요)
- `python3 build.py --flutter` - Flutter 버전 빌드 (데스크톱)
- `python3 build.py --flutter --release` - Flutter 버전 릴리스 모드 빌드
- `python3 build.py --hwcodec` - 하드웨어 코덱 지원 빌드
- `python3 build.py --vram` - VRAM 기능 빌드 (Windows 전용)
- `cargo build --release --features flutter,hwcodec` - 여러 기능을 포함한 Rust 빌드

### Flutter 명령어
- `cd flutter && flutter pub get` - Flutter 의존성 설치
- `cd flutter && flutter build windows --release` - Windows Flutter 앱 빌드
- `cd flutter && flutter build linux --release` - Linux Flutter 앱 빌드
- `cd flutter && flutter build macos --release` - macOS Flutter 앱 빌드
- `cd flutter && flutter build android` - Android APK 빌드
- `cd flutter && flutter build ios` - iOS 앱 빌드
- `cd flutter && flutter run` - Flutter 앱 개발 모드 실행

### 테스트
- `cargo test` - 모든 Rust 테스트 실행
- `cargo test <테스트명>` - 특정 테스트 실행
- `cargo test --package hbb_common` - 특정 패키지 테스트 실행
- `cd flutter && flutter test` - Flutter 테스트 실행

### 코드 생성
- Flutter-Rust 브릿지는 `src/bridge_generated.rs`와 `flutter/lib/generated_bridge.dart`를 생성함
- `src/flutter_ffi.rs` 수정 후 재생성: `flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart`

## 프로젝트 아키텍처

### Rust-Flutter 브릿지
애플리케이션은 `flutter_rust_bridge` (v1.80)를 사용하여 Flutter UI와 Rust 백엔드를 연결합니다:
- `src/flutter_ffi.rs` - Flutter에 노출되는 Rust FFI 함수
- `src/bridge_generated.rs` - 자동 생성된 브릿지 코드 (Rust 측)
- `flutter/lib/generated_bridge.dart` - 자동 생성된 브릿지 코드 (Dart 측)

### 핵심 라이브러리 (libs/)
- **hbb_common** - 공유 유틸리티: 비디오 코덱, 설정(`config.rs`), TCP/UDP 래퍼, protobuf, 파일 전송. git 서브모듈임.
- **scrap** - 플랫폼별 화면 캡처 (Windows DXGI/GDI, macOS Core Graphics/ScreenCaptureKit, Linux X11/Wayland)
- **enigo** - 크로스 플랫폼 키보드/마우스 입력 시뮬레이션
- **clipboard** - 크로스 플랫폼 클립보드 (Windows, Linux, macOS용 파일 복사/붙여넣기)
- **virtual_display** - Windows 가상 디스플레이 드라이버 (libs/virtual_display/dylib)
- **portable** - Windows 포터블 설치 프로그램 패커

### 서버 컴포넌트 (src/server/)
- `video_service.rs` - 화면 캡처 및 비디오 인코딩
- `audio_service.rs` - 오디오 캡처 및 스트리밍
- `input_service.rs` - 원격 입력 처리 (키보드/마우스)
- `clipboard_service.rs` - 클립보드 동기화
- `connection.rs` - 클라이언트 연결 관리
- `display_service.rs` - 디스플레이 열거 및 관리

### 플랫폼별 구현
- `src/platform/windows.rs` - Windows 전용 코드 (서비스, 레지스트리, 가상 디스플레이)
- `src/platform/linux.rs` - Linux 전용 코드 (X11/Wayland, PAM, systemd)
- `src/platform/macos.rs` - macOS 전용 코드 (접근성, launchd)

### UI 아키텍처
- **Sciter UI** (지원 중단): `src/ui/` - Sciter HTML/CSS/TIS를 사용한 레거시 UI
- **Flutter UI** (현재): `flutter/lib/`
  - `flutter/lib/desktop/` - 데스크톱 전용 페이지 및 위젯
  - `flutter/lib/mobile/` - 모바일 전용 페이지 및 위젯
  - `flutter/lib/common/` - 공유 위젯 및 유틸리티
  - `flutter/lib/models/` - 상태 관리 모델

### 주요 진입점
- `src/main.rs` - 애플리케이션 진입점
- `src/core_main.rs` - 코어 초기화 로직
- `src/rendezvous_mediator.rs` - 서버 통신 (NAT 트래버설, 릴레이)
- `src/client.rs` - 피어 연결 설정
- `src/ipc.rs` - UI와 서비스 간 프로세스 간 통신

## 빌드 설정

### 의존성
`VCPKG_ROOT` 환경 변수가 설정된 vcpkg 필요:
- **Windows**: `vcpkg install libvpx:x64-windows-static libyuv:x64-windows-static opus:x64-windows-static aom:x64-windows-static`
- **Linux/macOS**: `vcpkg install libvpx libyuv opus aom`

### Rust 요구사항
- 최소 Rust 버전: 1.75
- Sciter UI용: 플랫폼별 libsciter 라이브러리를 `target/debug/`에 다운로드

### 기능 플래그
- `flutter` - Flutter UI 활성화 (최신 빌드에 필수)
- `hwcodec` - 하드웨어 비디오 인코딩/디코딩 (Linux에서 libva-dev 필요)
- `vram` - VRAM 최적화 (Windows 전용)
- `unix-file-copy-paste` - Unix 파일 클립보드 지원
- `screencapturekit` - macOS ScreenCaptureKit (macOS 12.3 이상)
- `inline` - Sciter 리소스 인라인 (레거시 UI)

### 설정 시스템
모든 설정은 `libs/hbb_common/src/config.rs`에 있음:
- **Config/Config2** - 애플리케이션 설정 (ID, 암호화 키, 서버 설정)
- **LocalConfig** - 로컬 환경설정 (UI 옵션, 최근 피어)
- **PeerConfig** - 피어별 설정 (해상도, 키보드 모드)
- **UserDefaultConfig** - 새 피어의 기본 설정

### 다국어 지원
언어 파일 위치: `src/lang/`:
- `en.rs` (영어), `cn.rs` (중국어), `ja.rs` (일본어), `ko.rs` (한국어)
- 번역 추가 시 `template.rs`를 복사하여 값을 채움

## 무시 패턴
- `target/` - Rust 빌드 결과물
- `flutter/build/` - Flutter 빌드 출력
- `flutter/.dart_tool/` - Flutter 도구 파일
- `logs/` - 런타임 로그