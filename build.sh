#!/bin/bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <CMake Version> <Ninja Version> <Target Triple> <Target Architecture> <Target Operating System>"
    exit 1
fi

ZIG_VER="0.14.1"
CMAKE_VER="$1"
NINJA_VER="$2"
TARGET_TRIPLE="$3"
TARGET_ARCH="$4"
TARGET_OS="$5"
ROOT_DIR="$(pwd)"
BUILD_DIR="$ROOT_DIR/build"
INSTALL_DIR="$ROOT_DIR/install"
TOOLCHAIN="$ROOT_DIR/zig-as-llvm"
ZIG_PATH="$ROOT_DIR/zig-x86_64-linux-$ZIG_VER"
ZIG_CC="$TOOLCHAIN/bin/cc"
ZIG_CXX="$TOOLCHAIN/bin/c++"
ZIG_LD="$TOOLCHAIN/bin/ld"
ZIG_OBJCOPY="$TOOLCHAIN/bin/objcopy"
ZIG_AR="$TOOLCHAIN/bin/ar"
ZIG_STRIP="$TOOLCHAIN/bin/strip"
ZIG_C_FLAGS="-fsanitize=undefined -static"
ZIG_CXX_FLAGS="$ZIG_C_FLAGS"
ZIG_LINKER_FLAGS="-static"

export PATH="$PATH:$ZIG_PATH"
export ZIG_TARGET="$TARGET_TRIPLE"

if [ -d "$INSTALL_DIR/$CMAKE_VER-$TARGET_TRIPLE" ]; then
    echo "CMake and Ninja already built for $TARGET_TRIPLE. Exiting."
    exit 0
fi

download_zig() {
    if [ ! -d "$ZIG_PATH" ]; then
        echo "Zig not found. Downloading..."
        curl -LkSs "https://ziglang.org/download/$ZIG_VER/zig-x86_64-linux-$ZIG_VER.tar.xz" | tar -xJ
    else
        echo "Zig already exists."
    fi
}

clone_repo() {
    local repo_url="$1"
    local branch="$2"
    local dir="$3"

    if [ ! -d "$dir" ]; then
        echo "Cloning $dir..."
        git clone --quiet --branch "$branch" --depth 1 "$repo_url" "$dir"
    else
        echo "$dir already exists."
    fi
}

build_project() {
    local name="$1"
    local src_dir="$2"
    local build_dir="$3"
    local install_dir="$4"

    echo "Configuring $name..."
    local extra_flags=""
    if [[ "$name" == "CMake" ]]; then
        extra_flags="-DCMAKE_USE_OPENSSL=OFF"
    fi

    cmake -B "$build_dir" -S "$src_dir" \
        -DCMAKE_CROSSCOMPILING=True \
        -DCMAKE_SYSTEM_PROCESSOR="$TARGET_ARCH" \
        -DCMAKE_SYSTEM_NAME="$TARGET_OS" \
        -DCMAKE_C_COMPILER="$ZIG_CC" \
        -DCMAKE_CXX_COMPILER="$ZIG_CXX" \
        -DCMAKE_ASM_COMPILER="$ZIG_CC" \
        -DCMAKE_LINKER="$ZIG_LD" \
        -DCMAKE_OBJCOPY="$ZIG_OBJCOPY" \
        -DCMAKE_AR="$ZIG_AR" \
        -DCMAKE_STRIP="$ZIG_STRIP" \
        -DCMAKE_C_FLAGS="$ZIG_C_FLAGS" \
        -DCMAKE_CXX_FLAGS="$ZIG_CXX_FLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$ZIG_LINKER_FLAGS" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        $extra_flags \
        -G Ninja

    echo "Building $name..."
    ninja -C "$build_dir" -j12

    echo "Installing $name..."
    ninja -C "$build_dir" install
}


strip_binaries() {
    local bin_dir="$1"
    echo "Stripping binaries in $bin_dir..."
    for binary in "$bin_dir"/*; do
        [ -f "$binary" ] && "$ZIG_STRIP" "$binary"
    done
}

download_zig
clone_repo "https://github.com/HomuHomu833/zig-as-llvm" "main" "$TOOLCHAIN"
clone_repo "https://github.com/Kitware/CMake.git" "v$CMAKE_VER" "$ROOT_DIR/cmake-$CMAKE_VER"
clone_repo "https://github.com/ninja-build/ninja.git" "v$NINJA_VER" "$ROOT_DIR/ninja-$NINJA_VER"

build_project "CMake" "$ROOT_DIR/cmake-$CMAKE_VER" \
    "$BUILD_DIR/cmake-$CMAKE_VER-$TARGET_TRIPLE" \
    "$BUILD_DIR/binary-cmake-$CMAKE_VER-$TARGET_TRIPLE"

build_project "Ninja" "$ROOT_DIR/ninja-$NINJA_VER" \
    "$BUILD_DIR/ninja-$CMAKE_VER-$TARGET_TRIPLE" \
    "$BUILD_DIR/binary-ninja-$CMAKE_VER-$TARGET_TRIPLE"

strip_binaries "$BUILD_DIR/binary-cmake-$CMAKE_VER-$TARGET_TRIPLE/bin"
strip_binaries "$BUILD_DIR/binary-ninja-$CMAKE_VER-$TARGET_TRIPLE/bin"

echo "Merging Ninja with CMake..."
mkdir -p "$INSTALL_DIR/$CMAKE_VER-$TARGET_TRIPLE"
for thing in "$BUILD_DIR/binary-cmake-$CMAKE_VER-$TARGET_TRIPLE" \
           "$BUILD_DIR/binary-ninja-$CMAKE_VER-$TARGET_TRIPLE"; do
    cp -R "$thing"/. "$INSTALL_DIR/$CMAKE_VER-$TARGET_TRIPLE"
done

echo "Done!"
