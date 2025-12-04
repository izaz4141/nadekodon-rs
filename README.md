# Nadeko~don

**Nadeko~don** is a modern, cross-platform Download Manager built with Flutter and Rust. It leverages the performance of Rust for backend operations (downloading, file management) and the flexibility of Flutter for a beautiful user interface.

## Key Features

- **High Performance**: Powered by a Rust backend for efficient download handling.
- **Cross-Platform**: Runs on Linux, Windows, and Android.
- **Browser Integration**: Includes a local server to communicate with browser extensions [**NadeCon**](https://github.com/izaz4141/NadeCon) for seamless download capture.
- **System Tray Support**: Minimizes to the system tray for background operation.

## Getting Started

To run and build this app, you need to have:
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Rust toolchain](https://www.rust-lang.org/tools/install)
- [Rinf CLI](https://pub.dev/packages/rinf)

### Prerequisites

Check your system readiness:

```shell
rustc --version
flutter doctor
cargo install rinf_cli
```

### Build Commands

**Generate Rust-Dart Signals:**
```shell
rinf gen
```

**Run the App:**
```shell
flutter run
```

**Build for Production:**
```shell
flutter build <platform>
```

