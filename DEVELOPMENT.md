# Development Guide

This document provides an overview of the development process, code structure, and architecture of **Nadeko~don**, a Download Manager built with Flutter and Rust.

## Architecture Overview

Nadeko~don uses a hybrid architecture:
-   **Frontend**: Flutter (Dart) for the user interface and OS integration (system tray, window management).
-   **Backend**: Rust for high-performance logic, including download management, file operations, database handling, and networking.
-   **Communication**: [Rinf](https://pub.dev/packages/rinf) (Rust in Flutter) is used for seamless communication between Dart and Rust using signals.

## Project Structure

The project follows a standard Flutter + Rust structure:

-   **`lib/`**: Flutter (Dart) source code.
    -   `main.dart`: Application entry point. Initializes Rust, settings, and services.
    -   `app.dart`: Main `Nadeko~don` widget. Handles app lifecycle, intents, and deep links.
    -   `ui/`: UI components (Pages, Widgets, Dialogs).
    -   `utils/`: Utility classes (Settings, Logger, Notifications).
    -   `src/bindings/`: Generated Dart bindings for Rust signals.
-   **`native/hub/`**: Rust source code (crate name: `hub`).
    -   `src/lib.rs`: Rust entry point. Spawns async tasks for various services.
    -   `src/downloader/`: Signal handlers for download operations.
    -   `src/utils/`: Utility modules (Database, Server, Settings, YouTube-DL, Security).
    -   `src/signals/`: Signal definitions and handlers (DartSignal/RustSignal).
-   **`native/core/`**: Core download logic (crate name: `nadekodon-core`).
    -   Shared library providing download management, worker implementations, and data types.
    -   `src/downloader/`: Download manager, workers (HTTP, HLS, Torrent), and controls.
    -   `src/signals/`: Signal message structures.
    -   `src/utils/`: Database, settings, URL handling, YT-DLP integration.
-   **`native/server/`**: Standalone HTTP server (crate name: `nadekodon-server`).
    -   Runs independently for browser extension (NadeCon) integration.
    -   `src/server/`: HTTP server implementation.
    -   `src/qbittorrent/`: qBittorrent API client for torrent management.

## Key Components

### Frontend (Flutter)

-   **Entry Point**: `main()` in `lib/main.dart` sets up the environment, initializes the Rust backend via `initializeRust`, and starts services like `NotificationService` and `WindowManager`.
-   **State Management**: The app uses `rinf` signals to receive updates from the Rust backend. For example, `RequestAddDownload.rustSignalStream` listens for download requests.
-   **UI**: Built with Material Design 3. Theming is handled in `lib/theme/app_theme.dart` and supports dynamic colors.

### Backend (Rust)

-   **Entry Point**: `main()` in `native/hub/src/lib.rs` is the async entry point. It spawns several long-running tasks:
    -   `start_download_manager`: Manages the state of all downloads.
    -   `spawn_download_worker`: Handles the actual data transfer.
    -   `start_database_manager`: Manages SQLite database operations using `sqlx`.
    -   `start_server_listener`: Runs a local server (for browser extension integration).
    -   `handle_ytdl_query`: Integrates with `yt-dlp` for media extraction.
-   **Concurrency**: Uses `tokio` for asynchronous execution.

## Communication (Rinf)

Communication happens via "Signals".
-   **Dart to Rust**: Dart sends signals (e.g., `InitDatabase`, `StartServer`) to trigger actions in Rust.
-   **Rust to Dart**: Rust sends signals to update the UI (e.g., download progress, status updates).

Signals are defined in `native/core/src/signals/` and `native/hub/src/signals/` using Rinf's derive macros.

## Browser Extension Integration

Nadeko~don supports browser extension integration via the **NadeCon** browser extension. The standalone HTTP server (`native/server/`) provides a REST API for:

-   Adding downloads from the browser
-   Querying download status
-   Managing torrent downloads via qBittorrent integration

The server runs on a configurable port (default 8080) and supports API key authentication.

## Build Guide

This guide provides instructions for setting up the development environment, building, and running the project.

### 1. Prerequisites

Before you begin, ensure you have the following tools installed on your system:

-   **Flutter**: The project uses a specific Flutter version managed by FVM (Flutter Version Manager).
-   **Rust**: The Rust toolchain is required for the backend. You can install it via [rustup](https://rustup.rs/).
-   **Rinf**: The `rinf` CLI is needed to generate the communication bridge between Rust and Dart. Install it with: `cargo install rinf_cli`
-   **FVM**: Flutter Version Manager is used to ensure the correct Flutter SDK version is used. Follow the [FVM installation guide](https://fvm.app/docs/getting_started/installation).

### 2. Setup

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/izaz4141/nadekodon-rs.git
    cd nadekodon-rs
    ```

2.  **Install the correct Flutter SDK version:**
    ```sh
    fvm install
    ```

The project requires **Flutter 3.38.5** (configured in `.fvmrc`).

### 3. Development Workflow

#### Signal Generation
The communication between Dart and Rust is handled by `rinf`. Signals are defined using Rust struct attributes (`#[derive(DartSignal)]`, `#[derive(RustSignal)]`). After modifying signal definitions, regenerate the bindings:
```sh
rinf gen
```

#### Running the App
To run the application in debug mode, use the following command:
```sh
fvm flutter run
```

#### Building for Release
To create a release build for your target platform, use the platform-specific command:
```sh
# Linux (x64)
fvm flutter build linux --release --target-platform linux-x64

# Windows
fvm flutter build windows --release

# Android (ARM64)
fvm flutter build apk --release --target-platform android-arm64
```

#### Building Standalone Server
The `nadekodon-server` binary provides HTTP API for browser extension integration:
```sh
cargo build -p nadekodon-server --release
```

#### Docker Build
Build the server using Docker:
```sh
docker build -t nadekodon-server .
```

#### Formatting and Linting
To maintain code quality and consistency, please format and lint your code before committing.

-   **Format Dart & Rust:**
    ```sh
    fvm dart format lib
    cargo fmt --all
    ```

-   **Lint Dart:**
    ```sh
    fvm flutter analyze
    ```

-   **Lint Rust:**
    ```sh
    cargo check
    ```

## Miscellanous

### Icons
-   Generating android icon: `magick assets/icons/nadeko-don-1024.png -resize 75% -background none -gravity center -extent 1024x1024 assets/icons/nadeko-don-sm-1024.png`
-   Generating flutter icons: `fvm dart run flutter_launcher_icons`