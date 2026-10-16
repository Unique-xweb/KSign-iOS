#!/usr/bin/env bash
# [LISTN] build_ipa.sh
# Target: macOS Runner / xcodebuild iOS arm64
# Deliverable: Signed or Unsigned Production KSign.ipa package

set -euo pipefail

PROJECT_NAME="KSign"
SCHEME_NAME="KSign"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
OUTPUT_IPA="${BUILD_DIR}/${PROJECT_NAME}.ipa"

echo "[*] Step 1: Generating Xcode project via XcodeGen..."
xcodegen generate

echo "[*] Step 2: Compiling ${PROJECT_NAME} for iOS (generic/platform=iOS)..."
xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

echo "[*] Step 3: Extracting compiled bundle to Payload directory..."
rm -rf "${PAYLOAD_DIR}" "${OUTPUT_IPA}"
mkdir -p "${PAYLOAD_DIR}"

APP_BUNDLE="${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}-iphoneos/${PROJECT_NAME}.app"
if [ ! -d "${APP_BUNDLE}" ]; then
    echo "[X] Error: Built application not found at ${APP_BUNDLE}"
    exit 1
fi

cp -RL "${APP_BUNDLE}" "${PAYLOAD_DIR}/"

echo "[*] Step 4: Packaging Payload into ${OUTPUT_IPA}..."
cd "${BUILD_DIR}"
zip -qr -9 "${OUTPUT_IPA}" Payload
cd - > /dev/null

echo "[+] IPA Package successfully built at: ${OUTPUT_IPA}"
echo "[+] Size: $(du -sh "${OUTPUT_IPA}" | awk '{print $1}')"
echo "[+] SHA-256: $(shasum -a 256 "${OUTPUT_IPA}" | awk '{print $1}')"
