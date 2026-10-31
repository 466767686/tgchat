#!/usr/bin/env bash
# Build helper.
#
#   ./build.sh assembleDebug
#   ./build.sh assembleRelease
#   ./build.sh testDebugUnitTest
#
# On a normal x86_64 machine this is just a thin wrapper around Gradle.
# On this aarch64 box it adds the qemu-based aapt2 override, because the
# Android SDK only ships an x86_64 aapt2 binary.
set -euo pipefail
cd "$(dirname "$0")"

export JAVA_HOME="${JAVA_HOME:-/root/toolchain/jdk-17.0.2}"
export ANDROID_HOME="${ANDROID_HOME:-/root/toolchain/android-sdk}"

GRADLE_BIN="${GRADLE_BIN:-/root/toolchain/gradle-8.9/bin/gradle}"

EXTRA=()
if [ -x /root/toolchain/aapt2-override/aapt2 ]; then
  EXTRA+=("-Pandroid.aapt2FromMavenOverride=/root/toolchain/aapt2-override/aapt2")
fi

if [ $# -eq 0 ]; then
  set -- assembleDebug
fi

exec "$GRADLE_BIN" "$@" "${EXTRA[@]}" --console=plain
