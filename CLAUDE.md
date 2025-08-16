# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HashRipper is a macOS SwiftUI application for managing AxeOS-based Bitcoin miners. The app provides network discovery, pool configuration, firmware management, and monitoring capabilities for Bitcoin mining devices.

## Architecture

### Core Components

- **Main App**: SwiftUI-based macOS application in `app/HashRipper/`
- **AxeOSClient**: Swift Package for communicating with AxeOS miners in `libs/AxeOSClient/`
- **AxeOSUtils**: Utility library with network scanning capabilities in `libs/AxeOSUtils/`

### Key Architectural Patterns

- **SwiftData**: Used for data persistence with dual configuration - persistent storage for profiles/config, ephemeral storage for miner data
- **Actor-based concurrency**: Background data processing using `BackgroundMinerDataActor` 
- **Dependency injection**: Services injected via SwiftUI environment (database, client manager, scanners)
- **MVVM pattern**: ViewModels manage business logic for major features like firmware releases

### Database Architecture

The app uses a split SwiftData configuration:
- `ProfilesAndConfig` container: Persistent storage for `MinerProfileTemplate` and `MinerWifiConnection`
- `Miners` container: In-memory storage for `Miner`, `MinerConnectionStatus`, `AggregateStats`, and `FirmwareRelease`

### Network Layer

- **AxeOSClient**: Handles HTTP API communication with miners
- **AxeOSWebsocketClient**: Manages websocket connections for real-time data
- **SwamScanner**: Network discovery using IP range scanning
- **IPAddressCalculator**: Utility for network address calculations

## Development Commands

### Building the App
```bash
# Open in Xcode and build
open app/HashRipper/HashRipper.xcodeproj
# Build target: HashRipper > My Mac
# Run: Cmd+R or click play button
```

If the read is an LLM Ai Agent run the command `xcodebuild -project HashRipper.xcodeproj -scheme HashRipper -destination "platform=macOS" build -hideShellScriptEnvironment 2>&1 | tail -20` to get build output.

### Testing Swift Packages
```bash
# Test AxeOSClient library
cd libs/AxeOSClient
swift test

# Test AxeOSUtils library  
cd libs/AxeOSUtils
swift test
```

### Project Structure
- Tests are included for both Swift packages but not extensively for the main app
- UI tests exist in `HashRipperUITests/` but may be minimal
- The main app relies on Xcode's built-in build system rather than external build tools

## Key Models and Data Flow

- **Miner**: Core SwiftData model representing a mining device with relationship to `MinerUpdate` records
- **MinerProfileTemplate**: Persistent templates for miner configuration (pools, WiFi, etc.)
- **AxeOSDeviceInfo**: Network response model for miner status and configuration
- **FirmwareRelease**: Model for tracking available firmware versions

The app follows a pattern where miners are discovered via network scanning, their data is cached in-memory, and user-defined profiles are persisted for reuse across mining operations.

## Important Dependencies

- **MarkdownUI**: Used for rendering firmware release notes
- **SwiftData**: Apple's data persistence framework
- **Network framework**: For low-level networking operations
- **SwiftUI**: Primary UI framework

The project targets macOS 13+ and uses Swift 6.1 language features.
