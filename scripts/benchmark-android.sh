#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESULT_DIR="${1:-.benchmark-results/android-$(date -u +%Y%m%dT%H%M%SZ)}"
if [[ $# -gt 0 && "$1" != "--"* ]]; then
    shift
fi

BUILD_ONLY=false
if [[ "${1:-}" == "--build-only" ]]; then
    BUILD_ONLY=true
    shift
fi

export BENCHMARK_DISABLE_JEMALLOC="${BENCHMARK_DISABLE_JEMALLOC:-true}"
export KOMA_ENABLE_BENCHMARKS=1

mkdir -p "$RESULT_DIR"

ANDROID_SWIFT_SDK="${ANDROID_SWIFT_SDK:-$(swift sdk list 2>/dev/null | awk '/android/ { print $1; exit }')}"
if [[ -z "$ANDROID_SWIFT_SDK" ]]; then
    echo "No Android Swift SDK found. Install one, or set ANDROID_SWIFT_SDK." >&2
    exit 1
fi

ADB=(adb)
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    ADB=(adb -s "$ANDROID_SERIAL")
fi

device_abi=""
if command -v adb >/dev/null 2>&1 && "${ADB[@]}" get-state >/dev/null 2>&1; then
    device_abi="$("${ADB[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"
fi

triple_for_abi() {
    case "$1" in
        arm64-v8a) echo "aarch64-unknown-linux-android35" ;;
        x86_64) echo "x86_64-unknown-linux-android35" ;;
        armeabi-v7a) echo "armv7-unknown-linux-android35" ;;
        *) echo "aarch64-unknown-linux-android35" ;;
    esac
}

ANDROID_SWIFT_TRIPLE="${ANDROID_SWIFT_TRIPLE:-$(triple_for_abi "$device_abi")}"
ANDROID_BUILD_SCRATCH="${ANDROID_BUILD_SCRATCH:-.build/android-${ANDROID_SWIFT_TRIPLE}}"
ANDROID_LINK_LIB_DIR="$ANDROID_BUILD_SCRATCH/link-libs"
ANDROID_SWIFT_SDK_ROOT="${ANDROID_SWIFT_SDK_ROOT:-$HOME/Library/org.swift.swiftpm/swift-sdks/$ANDROID_SWIFT_SDK.artifactbundle/swift-android}"
ANDROID_FILTERED_SWIFT_SDKS="$ANDROID_BUILD_SCRATCH/swift-sdks"
ANDROID_FILTERED_SWIFT_SDK_ID="koma-${ANDROID_SWIFT_SDK}-${ANDROID_SWIFT_TRIPLE}"

SWIFT_VERSION="$(swift --version | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
GIT_REVISION="$(git rev-parse --verify HEAD 2>/dev/null || echo unknown)"
GIT_TAG="$(git describe --tags --exact-match 2>/dev/null || echo untagged)"
HOST_PLATFORM="$(uname -smr)"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PRODUCTS=(
    KomaAndroidBenchmarks
    KomaAndroidSQLiteSwiftBenchmarks
)
BUILD_COMMAND="swift build -c release --scratch-path $ANDROID_BUILD_SCRATCH --swift-sdks-path $ANDROID_FILTERED_SWIFT_SDKS --swift-sdk $ANDROID_FILTERED_SWIFT_SDK_ID --triple $ANDROID_SWIFT_TRIPLE --product <product> -Xcc -I$ROOT_DIR/Sources/CKomaSQLite/include -Xlinker -L$ANDROID_LINK_LIB_DIR"

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

android_clang_name() {
    case "$ANDROID_SWIFT_TRIPLE" in
        aarch64-unknown-linux-android*) echo "${ANDROID_SWIFT_TRIPLE/aarch64-unknown-linux-android/aarch64-linux-android}-clang" ;;
        x86_64-unknown-linux-android*) echo "${ANDROID_SWIFT_TRIPLE/x86_64-unknown-linux-android/x86_64-linux-android}-clang" ;;
        armv7-unknown-linux-android*) echo "${ANDROID_SWIFT_TRIPLE/armv7-unknown-linux-android/armv7a-linux-androideabi}-clang" ;;
        *) echo "" ;;
    esac
}

swift_resource_arch() {
    case "$ANDROID_SWIFT_TRIPLE" in
        aarch64-unknown-linux-android*) echo "aarch64" ;;
        x86_64-unknown-linux-android*) echo "x86_64" ;;
        armv7-unknown-linux-android*) echo "armv7" ;;
        *) echo "" ;;
    esac
}

android_ndk_arch_dir() {
    case "$ANDROID_SWIFT_TRIPLE" in
        aarch64-unknown-linux-android*) echo "aarch64-linux-android" ;;
        x86_64-unknown-linux-android*) echo "x86_64-linux-android" ;;
        armv7-unknown-linux-android*) echo "arm-linux-androideabi" ;;
        *) echo "" ;;
    esac
}

prepare_filtered_swift_sdk() {
    local resource_arch
    resource_arch="$(swift_resource_arch)"

    if [[ -z "$resource_arch" || ! -d "$ANDROID_SWIFT_SDK_ROOT" ]]; then
        echo "Unable to locate Swift Android SDK root for $ANDROID_SWIFT_TRIPLE. Set ANDROID_SWIFT_SDK_ROOT." >&2
        exit 1
    fi

    local bundle="$ANDROID_FILTERED_SWIFT_SDKS/$ANDROID_FILTERED_SWIFT_SDK_ID.artifactbundle"
    local variant="$bundle/swift-android"
    mkdir -p "$variant"

    ln -sfn "$ANDROID_SWIFT_SDK_ROOT/swift-resources" "$variant/swift-resources"
    ln -sfn "$ANDROID_SWIFT_SDK_ROOT/android-ndk-r27d" "$variant/android-ndk-r27d"
    ln -sfn "$ANDROID_SWIFT_SDK_ROOT/ndk-sysroot" "$variant/ndk-sysroot"
    ln -sfn "$ANDROID_SWIFT_SDK_ROOT/scripts" "$variant/scripts"
    ln -sfn "$ANDROID_SWIFT_SDK_ROOT/swift-toolset.json" "$variant/swift-toolset.json"

    cat > "$bundle/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$ANDROID_FILTERED_SWIFT_SDK_ID": {
      "variants": [
        {
          "path": "swift-android"
        }
      ],
      "version": "0.1",
      "type": "swiftSDK"
    }
  }
}
JSON

    cat > "$variant/swift-sdk.json" <<JSON
{
  "schemaVersion": "4.0",
  "targetTriples": {
    "$ANDROID_SWIFT_TRIPLE": {
      "sdkRootPath": "ndk-sysroot",
      "swiftResourcesPath": "swift-resources/usr/lib/swift-$resource_arch",
      "swiftStaticResourcesPath": "swift-resources/usr/lib/swift_static-$resource_arch",
      "toolsetPaths": [ "swift-toolset.json" ]
    }
  }
}
JSON
}

prepare_android_link_libraries() {
    local ndk_bin="$ANDROID_SWIFT_SDK_ROOT/android-ndk-r27d/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    local clang_name
    clang_name="$(android_clang_name)"

    if [[ -z "$clang_name" || ! -x "$ndk_bin/$clang_name" ]]; then
        echo "Unable to locate Android clang for $ANDROID_SWIFT_TRIPLE. Set ANDROID_SWIFT_SDK_ROOT." >&2
        exit 1
    fi

    mkdir -p "$ANDROID_LINK_LIB_DIR"

    local source="$ANDROID_LINK_LIB_DIR/sqlite3-link-placeholder.c"
    local object="$ANDROID_LINK_LIB_DIR/sqlite3-link-placeholder.o"
    printf '%s\n' 'int koma_sqlite3_link_placeholder = 0;' > "$source"
    "$ndk_bin/$clang_name" -c "$source" -o "$object"
    "$ndk_bin/llvm-ar" rcs "$ANDROID_LINK_LIB_DIR/libsqlite3.a" "$object"
}

prepare_filtered_swift_sdk
prepare_android_link_libraries

if [[ "${ANDROID_INCREMENTAL_BUILD:-0}" != "1" ]]; then
    rm -rf "$ANDROID_BUILD_SCRATCH/$ANDROID_SWIFT_TRIPLE"
fi

declare -a BINARIES=()
for product in "${PRODUCTS[@]}"; do
    echo "Building $product with $ANDROID_SWIFT_SDK for $ANDROID_SWIFT_TRIPLE..."
    swift build \
        -c release \
        --scratch-path "$ANDROID_BUILD_SCRATCH" \
        --swift-sdks-path "$ANDROID_FILTERED_SWIFT_SDKS" \
        --swift-sdk "$ANDROID_FILTERED_SWIFT_SDK_ID" \
        --triple "$ANDROID_SWIFT_TRIPLE" \
        --product "$product" \
        -Xcc "-I$ROOT_DIR/Sources/CKomaSQLite/include" \
        -Xlinker "-L$ANDROID_LINK_LIB_DIR"

    binary="$(find "$ANDROID_BUILD_SCRATCH" -type f -path "*/release/$product" | sort | tail -n 1)"
    if [[ -z "$binary" ]]; then
        echo "Unable to locate $product after build." >&2
        exit 1
    fi
    BINARIES+=("$binary")
done

if [[ "$BUILD_ONLY" == true ]]; then
    cat > "$RESULT_DIR/metadata.json" <<JSON
{
  "schemaVersion": 1,
  "suite": "KomaAndroidBenchmarks",
  "startedAt": "$(json_escape "$STARTED_AT")",
  "gitRevision": "$(json_escape "$GIT_REVISION")",
  "gitTag": "$(json_escape "$GIT_TAG")",
  "swiftVersion": "$(json_escape "$SWIFT_VERSION")",
  "androidSwiftSDK": "$(json_escape "$ANDROID_SWIFT_SDK")",
  "androidSwiftTriple": "$(json_escape "$ANDROID_SWIFT_TRIPLE")",
  "hostPlatform": "$(json_escape "$HOST_PLATFORM")",
  "device": "build-only",
  "command": "$(json_escape "$BUILD_COMMAND")"
}
JSON
    printf 'Android benchmark binaries built:\n'
    printf -- '- %s\n' "${BINARIES[@]}"
    echo "Build metadata written to $RESULT_DIR"
    exit 0
fi

if ! command -v adb >/dev/null 2>&1; then
    echo "adb was not found. Install Android platform-tools or add adb to PATH." >&2
    exit 1
fi

if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
    echo "No Android device or emulator is available through adb." >&2
    echo "Start an emulator, connect a device, or use --build-only to verify compilation." >&2
    exit 1
fi

DEVICE_MODEL="$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')"
DEVICE_MANUFACTURER="$("${ADB[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
ANDROID_VERSION="$("${ADB[@]}" shell getprop ro.build.version.release | tr -d '\r')"
ANDROID_SDK="$("${ADB[@]}" shell getprop ro.build.version.sdk | tr -d '\r')"
ANDROID_ABI="$("${ADB[@]}" shell getprop ro.product.cpu.abi | tr -d '\r')"
REMOTE_DIR="${KOMA_ANDROID_REMOTE_DIR:-/data/local/tmp/koma-benchmarks}"
SWIFT_RUNTIME_DIR="$ANDROID_SWIFT_SDK_ROOT/swift-resources/usr/lib/swift-$(swift_resource_arch)/android"
NDK_CXX_SHARED="$ANDROID_SWIFT_SDK_ROOT/android-ndk-r27d/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/$(android_ndk_arch_dir)/libc++_shared.so"

cat > "$RESULT_DIR/metadata.json" <<JSON
{
  "schemaVersion": 1,
  "suite": "KomaAndroidBenchmarks",
  "startedAt": "$(json_escape "$STARTED_AT")",
  "gitRevision": "$(json_escape "$GIT_REVISION")",
  "gitTag": "$(json_escape "$GIT_TAG")",
  "swiftVersion": "$(json_escape "$SWIFT_VERSION")",
  "androidSwiftSDK": "$(json_escape "$ANDROID_SWIFT_SDK")",
  "androidSwiftTriple": "$(json_escape "$ANDROID_SWIFT_TRIPLE")",
  "hostPlatform": "$(json_escape "$HOST_PLATFORM")",
  "device": "$(json_escape "$DEVICE_MANUFACTURER $DEVICE_MODEL")",
  "androidVersion": "$(json_escape "$ANDROID_VERSION")",
  "androidSDK": "$(json_escape "$ANDROID_SDK")",
  "androidABI": "$(json_escape "$ANDROID_ABI")",
  "command": "$(json_escape "$BUILD_COMMAND && adb shell <product> $*")"
}
JSON

"${ADB[@]}" shell "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR'"
for binary in "${BINARIES[@]}"; do
    product="$(basename "$binary")"
    "${ADB[@]}" push "$binary" "$REMOTE_DIR/$product" >/dev/null 2>&1

    binary_dir="$(dirname "$binary")"
    while IFS= read -r library; do
        "${ADB[@]}" push "$library" "$REMOTE_DIR/" >/dev/null 2>&1
    done < <(find "$binary_dir" -maxdepth 1 -type f -name '*.so' | sort)
done

if [[ ! -d "$SWIFT_RUNTIME_DIR" ]]; then
    echo "Unable to locate Swift runtime libraries at $SWIFT_RUNTIME_DIR." >&2
    exit 1
fi

while IFS= read -r library; do
    "${ADB[@]}" push "$library" "$REMOTE_DIR/" >/dev/null 2>&1
done < <(find "$SWIFT_RUNTIME_DIR" -maxdepth 1 -type f -name '*.so' | sort)

if [[ -f "$NDK_CXX_SHARED" ]]; then
    "${ADB[@]}" push "$NDK_CXX_SHARED" "$REMOTE_DIR/" >/dev/null 2>&1
fi

REMOTE_ARGS=""
for arg in "$@"; do
    REMOTE_ARGS+=" $(printf '%q' "$arg")"
done

: > "$RESULT_DIR/results.txt"
for binary in "${BINARIES[@]}"; do
    product="$(basename "$binary")"
    "${ADB[@]}" shell "cd '$REMOTE_DIR' && chmod 755 './$product' && TMPDIR='$REMOTE_DIR' LD_LIBRARY_PATH='$REMOTE_DIR' './$product'$REMOTE_ARGS" \
        | tee -a "$RESULT_DIR/results.txt"
done

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RESULT_DIR/summary.md" <<MARKDOWN
# Koma Android Benchmark Run

- Suite: KomaAndroidBenchmarks
- Started: $STARTED_AT
- Finished: $FINISHED_AT
- Git revision: $GIT_REVISION
- Git tag: $GIT_TAG
- Swift: $SWIFT_VERSION
- Android Swift SDK: $ANDROID_SWIFT_SDK
- Android Swift triple: $ANDROID_SWIFT_TRIPLE
- Host platform: $HOST_PLATFORM
- Device: $DEVICE_MANUFACTURER $DEVICE_MODEL
- Android: $ANDROID_VERSION, SDK $ANDROID_SDK, ABI $ANDROID_ABI

See \`results.txt\` for raw benchmark output and \`metadata.json\` for machine-readable run metadata.
MARKDOWN

echo "Android benchmark artifacts written to $RESULT_DIR"
