# Development Guide

This document provides an overview of the development process, code structure, and architecture of **Nadeko~don**, a Download Manager built with Flutter and Rust.

## Architecture Overview

Nadeko~don uses a hybrid architecture:
-   **Frontend**: Flutter (Dart) for the user interface and OS integration (system tray, window management).
-   **Backend**: Rust for high-performance logic, including download management, file operations, database handling, and networking.
-   **Communication**: [Rinf](https://pub.dev/packages/rinf) (Rust in Flutter) is used for seamless communication between Dart and Rust using signals (Protobuf messages).

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
    -   `src/downloader/`: Core download logic (Download Manager, Workers).
    -   `src/utils/`: Utility modules (Database, Server, Settings, YouTube-DL).
    -   `src/signals/`: Signal definitions and handlers.

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

## Development Workflow

-   **Building**: `rinf gen`, `flutter build`
-   **Linting**: `flutter analyze`, `cargo clippy`
-   **Code Style**: Guidelines for Dart and Rust.

## Getting Started

1.  **Install Dependencies**:
    ```bash
    flutter pub get
    # Rust dependencies are handled automatically by cargo
    ```

2.  **Generate Bindings**:
    ```bash
    rinf gen
    ```

3.  **Run Locally**:
    ```bash
    flutter run
    ```
