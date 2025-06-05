#!/usr/bin/env bash
set -euo pipefail

#  Recompile the Rust/C API (chewing_capi) for two ABIs via `cargo ndk`.
#  Copy the resulting libchewing.so into
#      ChineseKeyboardIME/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/
#
# Run chewing-cli init-database on mini.src, tsi.src, word.src → .dat.
# Copy all final *.dat and other static data (e.g. .dat/.cin) into:
#      ChineseKeyboardIME/src/main/assets/chewing_data/
#
# USAGE:
#   cd ThirdPartyTools/libchewing
#   chmod +x build-android.sh
#   ./build-android.sh

echo ""
echo "-------------------------------------------------------------------"
echo "  Running libchewing/build-android.sh"
echo "  (rebuild .a, make .so, generate .dat from .src, copy assets)"
echo "-------------------------------------------------------------------"
echo ""


if [ -z "${ANDROID_NDK_HOME:-}" ] ; then
  echo "ERROR: Please set ANDROID_NDK_HOME before running this script."
  echo "  For example:"
  echo "    export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/25.1.8937393"
  exit 1
fi

if [ ! -d "$ANDROID_NDK_HOME" ] ; then
  echo "ERROR: ANDROID_NDK_HOME='$ANDROID_NDK_HOME' does not exist or is not a directory."
  exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
CLANGPP="$TOOLCHAIN/bin/clang++"
SYSROOT="$TOOLCHAIN/sysroot"

for path in "$TOOLCHAIN" "$CLANGPP" "$SYSROOT" ; do
  if [ ! -e "$path" ] ; then
    echo "ERROR: Cannot find required file or directory: $path"
    exit 1
  fi
done


ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPI_DIR="$ROOT/ThirdPartyTools/libchewing/capi"

TARGET_DIR="$ROOT/ThirdPartyTools/libchewing/target/android"

JNI_LIBS_DIR="$ROOT/Source/Gradle/ChineseKeyboardIME/src/main/jniLibs"

ASSETS_DATA_DIR="$ROOT/Source/Gradle/ChineseKeyboardIME/src/main/assets/chewing_data"

echo "→ Project root:             $ROOT"
echo "→ Chewing C API folder:     $CAPI_DIR"
echo "→ Rust target outputs:      $TARGET_DIR"
echo "→ Android jniLibs path:     $JNI_LIBS_DIR"
echo "→ Android assets 'chewing_data':"
echo "   $ASSETS_DATA_DIR"
echo

echo "=== Building static libchewing_capi.a via cargo-ndk ==="
pushd "$CAPI_DIR" > /dev/null

cargo ndk \
  -t aarch64-linux-android \
  -t armv7-linux-androideabi \
  -- build --release --target-dir ../target/android

popd > /dev/null

echo "→ Static archives now are located in:"
echo "     $TARGET_DIR/aarch64-linux-android/release/libchewing_capi.a"
echo "     $TARGET_DIR/armv7-linux-androideabi/release/libchewing_capi.a"
echo

mkdir -p "$JNI_LIBS_DIR/arm64-v8a"
mkdir -p "$JNI_LIBS_DIR/armeabi-v7a"


JNI_BRIDGE_CPP="$CAPI_DIR/src/chewingJNI.cpp"
SIMPLIFIED_CPP="$CAPI_DIR/src/chewing-simplified.cpp"

AARCH64_A="$TARGET_DIR/aarch64-linux-android/release/libchewing_capi.a"
ARMV7_A="$TARGET_DIR/armv7-linux-androideabi/release/libchewing_capi.a"

for f in "$JNI_BRIDGE_CPP" "$SIMPLIFIED_CPP" "$AARCH64_A" "$ARMV7_A"; do
  if [ ! -e "$f" ]; then
    echo "ERROR: Required file does not exist: $f"
    exit 1
  fi
done

echo "=== Linking libchewing.so for arm64-v8a ==="
CMD_AARCH64=(
  "$CLANGPP"
    --target=aarch64-none-linux-android30
    --sysroot="$SYSROOT"
    -fPIC -shared
    -std=c++14 -stdlib=libc++

    -I"$ROOT/ThirdPartyTools/libchewing"
    -I"$CAPI_DIR/include"

    "$JNI_BRIDGE_CPP"
    "$SIMPLIFIED_CPP"
    "$AARCH64_A"

    -llog

    -o "$JNI_LIBS_DIR/arm64-v8a/libchewing.so"
)

echo "  > ${CMD_AARCH64[*]}"
"${CMD_AARCH64[@]}"

echo "→ arm64-v8a .so written to: $JNI_LIBS_DIR/arm64-v8a/libchewing.so"
echo

echo "=== Linking libchewing.so for armeabi-v7a ==="
CMD_ARMV7=(
  "$CLANGPP"
    --target=armv7a-linux-androideabi30
    --sysroot="$SYSROOT"
    -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16
    -fPIC -shared
    -std=c++14 -stdlib=libc++

    -I"$ROOT/ThirdPartyTools/libchewing"
    -I"$CAPI_DIR/include"

    "$JNI_BRIDGE_CPP"
    "$SIMPLIFIED_CPP"
    "$ARMV7_A"

    -llog

    -o "$JNI_LIBS_DIR/armeabi-v7a/libchewing.so"
)

echo "  > ${CMD_ARMV7[*]}"
"${CMD_ARMV7[@]}"

echo "→ armeabi-v7a .so written to: $JNI_LIBS_DIR/armeabi-v7a/libchewing.so"
echo

echo "=== Building host-side chewing-cli (so we can turn .src → .dat) ==="
pushd "$ROOT/ThirdPartyTools/libchewing" > /dev/null

cargo build --release -p chewing-cli

HOST_CLI="$ROOT/ThirdPartyTools/libchewing/target/release/chewing-cli"

if [ ! -x "$HOST_CLI" ]; then
  echo "ERROR: Could not build host chewing-cli at: $HOST_CLI"
  exit 1
fi

popd > /dev/null
echo "→ Host chewing-cli is at: $HOST_CLI"
echo

echo "=== Generating .dat from .src via chewing-cli ==="
DATA_SRC_DIR="$ROOT/ThirdPartyTools/libchewing/data"
DATA_BIN_DIR="$ROOT/ThirdPartyTools/libchewing/data"

mkdir -p "$DATA_BIN_DIR"

DATA_COPYRIGHT="Copyright (c) 2022 libchewing Core Team"
DATA_LICENSE="LGPL-2.1-or-later"
DATA_VERSION="0.9.1"

echo "  • Generating tsi.dat (詞庫) …"
"$HOST_CLI" init-database \
    -c "$DATA_COPYRIGHT" \
    -l "$DATA_LICENSE" \
    -r "$DATA_VERSION" \
    -t trie \
    -n "內建詞庫" \
    "$DATA_SRC_DIR/tsi.src" \
    "$DATA_BIN_DIR/tsi.dat"

echo "  • Generating word.dat (字庫) …"
"$HOST_CLI" init-database \
    -c "$DATA_COPYRIGHT" \
    -l "$DATA_LICENSE" \
    -r "$DATA_VERSION" \
    -t trie \
    -n "內建字庫" \
    "$DATA_SRC_DIR/word.src" \
    "$DATA_BIN_DIR/word.dat"

echo "  • Generating mini.dat (迷你庫) …"
"$HOST_CLI" init-database \
    -c "$DATA_COPYRIGHT" \
    -l "$DATA_LICENSE" \
    -r "$DATA_VERSION" \
    -t trie \
    -n "內嵌字庫" \
    "$DATA_SRC_DIR/mini.src" \
    "$DATA_BIN_DIR/mini.dat"

echo "=== Copy dictionary files into Android asset folder ==="

mkdir -p "$ASSETS_DATA_DIR"

cp -pv "$DATA_BIN_DIR"/*.dat    "$ASSETS_DATA_DIR"/
cp -pv "$DATA_SRC_DIR"/*.cin    "$ASSETS_DATA_DIR"/

echo "---------------------------------------------------------"
echo "  build-android.sh finished successfully."
echo "    • libchewing.so → jniLibs/arm64-v8a & jniLibs/armeabi-v7a"
echo "    • chewing_data/*.dat, *.cin → src/main/assets/chewing_data/"
echo ""
