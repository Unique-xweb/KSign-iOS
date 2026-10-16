# [LISTN] KSign - On-Device iOS IPA Signing & Sideloading Architecture

KSign is an autonomous on-device iOS application built for IPA signing, Mach-O modification, tweak/dylib injection, and local sideloading via `itms-services` without a tethered computer.

---

## Technical Architecture Overview

```
                      +---------------------------------------+
                      |               KSignApp                |
                      |          (SwiftUI 4-Tab UX)           |
                      +-------------------+-------------------+
                                          |
        +---------------------------------+---------------------------------+
        |                                 |                                 |
+-------v-------+                 +-------v-------+                 +-------v-------+
|   Files Tab   |                 |   Apps Tab    |                 | Certs/Settings|
|  Import/Unpack|                 | Local Install |                 | P12/Prov/TLS  |
+-------+-------+                 +-------+-------+                 +-------+-------+
        |                                 |                                 |
        +---------------------------------+---------------------------------+
                                          |
                      +-------------------v-------------------+
                      |          AppSignerService             |
                      |   Orchestrator & Archive Builder      |
                      +-------------------+-------------------+
                                          |
       +----------------------------------+----------------------------------+
       |                                  |                                  |
+------v------+                    +------v------+                    +------v------+
| ZipArchive  |                    | DylibInject |                    | PlistHelper |
| (Deflate/   |                    | (LC_LOAD_   |                    | (CodeRes /  |
|  Inflate)   |                    |  DYLIB)     |                    |  SHA-256)   |
+------+------+                    +------+------+                    +------+------+
       |                                  |                                  |
       +----------------------------------+----------------------------------+
                                          |
                      +-------------------v-------------------+
                      |      CoreSignEngine (Obj-C++)         |
                      +-------------------+-------------------+
                                          |
                 +------------------------+------------------------+
                 |                                                 |
       +---------v---------+                             +---------v---------+
       |   MachOModifier   |                             |CodeDirectorySigner|
       |  (64-bit Header / |                             | (4KB SHA256 Slots |
       |  __LINKEDIT edit) |                             |  OpenSSL CMS Env) |
       +-------------------+                             +-------------------+
```

---

## Directory Layout

```
├── .github/
│   └── workflows/
│       └── build.yml               # Automated CI runner for building KSign.ipa
├── project.yml                     # XcodeGen project specification
├── scripts/
│   ├── setup_dependencies.sh       # Dependency bootstrapper
│   └── build_ipa.sh                # Xcode archive & IPA packager
├── Resources/
│   ├── Info.plist                  # iOS metadata, file associations, network permissions
│   └── KSign.entitlements          # App groups and task-allow entitlements
├── Sources/
│   ├── CoreSignEngine/             # C++20 Core Mach-O & Cryptographic Engine
│   │   ├── include/
│   │   │   ├── CoreSignEngine.h
│   │   │   ├── MachOModifier.h
│   │   │   └── CodeDirectorySigner.h
│   │   ├── CoreSignEngine.mm
│   │   ├── MachOModifier.cpp
│   │   └── CodeDirectorySigner.cpp
│   └── KSignApp/                   # Swift 5.9 Application Layer
│       ├── KSignApp.swift          # Main entrypoint
│       ├── KSign-Bridging-Header.h
│       ├── Models/
│       ├── ViewModels/
│       ├── Services/
│       ├── Helpers/
│       └── Views/
```

---

## Automated CI/CD Compilation (GitHub Actions)

Since development hosts can be Windows or Linux, `.github/workflows/build.yml` runs on `macos-14`:

1. Installs `xcodegen` via Homebrew.
2. Resolves dependencies and OpenSSL XCFramework.
3. Generates the `.xcodeproj` file.
4. Invokes `xcodebuild` clean archive with ad-hoc signing (`CODE_SIGNING_ALLOWED=NO`).
5. Extracts and compresses into `KSign.ipa`.
6. Uploads the IPA as a build artifact and publishes GitHub Releases on tags (`v*`).

---

## Local Build & Export Instructions

On a macOS system with Xcode installed:

```bash
# 1. Clone repository
git clone <repo-url>
cd <repo-dir>

# 2. Run dependency setup
chmod +x scripts/setup_dependencies.sh scripts/build_ipa.sh
./scripts/setup_dependencies.sh

# 3. Generate Xcode project & compile IPA
./scripts/build_ipa.sh
```

Output binary: `build/KSign.ipa`
