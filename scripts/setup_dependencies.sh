#!/usr/bin/env bash
# [LISTN] setup_dependencies.sh
# Target: macOS Darwin / iOS Toolchain Dependency Bootstrapper
# Purpose: Prepares XcodeGen, OpenSSL XCFramework, and compilation assets

set -euo pipefail

echo "[*] Initializing KSign dependency verification..."

# 1. Check for Homebrew & XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "[!] xcodegen not found. Attempting installation via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "[X] Error: Homebrew is required to install xcodegen. Install Homebrew or xcodegen manually."
        exit 1
    fi
else
    echo "[+] xcodegen found: $(xcodegen --version)"
fi

# 2. Check for zip / unzip utilities
for tool in zip unzip plutil security xcodebuild curl; do
    if ! command -v "$tool" &> /dev/null; then
        echo "[X] Error: Required tool '$tool' is not available in PATH."
        exit 1
    fi
done
echo "[+] Standard Darwin build utilities verified."

# 3. Create build directories & download prebuilt OpenSSL XCFramework
mkdir -p Frameworks
mkdir -p build/Payload

if [ ! -d "Frameworks/OpenSSL.xcframework" ]; then
    echo "[*] Downloading prebuilt OpenSSL.xcframework..."
    curl -L -s https://github.com/krzyzanowskim/OpenSSL/releases/download/1.1.2300/OpenSSL.xcframework.zip -o OpenSSL.xcframework.zip
    unzip -q OpenSSL.xcframework.zip -d Frameworks/
    rm -f OpenSSL.xcframework.zip
    echo "[+] OpenSSL.xcframework installed to Frameworks/"
fi

echo "[+] Dependency bootstrapping complete. Ready for project generation."
