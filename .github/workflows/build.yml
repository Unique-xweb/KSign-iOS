name: Build KSign IPA

on:
  push:
    branches: [ "main", "master" ]
    tags: [ "v*" ]
  pull_request:
    branches: [ "main", "master" ]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: Build & Package IPA
    runs-on: macos-15

    steps:
      - name: Checkout Source Code
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Verify Xcode Version
        run: |
          xcodebuild -version

      - name: Install Build Tooling (XcodeGen)
        run: |
          brew install xcodegen

      - name: Run Setup Dependencies
        run: |
          chmod +x scripts/setup_dependencies.sh scripts/build_ipa.sh
          ./scripts/setup_dependencies.sh

      - name: Compile and Package KSign.ipa
        run: |
          ./scripts/build_ipa.sh

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: KSign-ipa
          path: build/KSign.ipa
          if-no-files-found: error
