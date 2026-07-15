#!/usr/bin/env bash
#
# Builds the iOS Bluetooth plugin as a fat static library for device + simulator.
#
#   export GODOT_SRC=/path/to/godot      # engine source at the version you export with
#   ./build.sh [debug|release]
#
# Must run on macOS with Xcode installed. There is no way around that: the plugin
# links CoreBluetooth and compiles Objective-C++, and only Apple's toolchain can
# do either.

set -euo pipefail

TARGET="${1:-release}"
: "${GODOT_SRC:?Set GODOT_SRC to a checkout of the Godot source tree}"

if [[ "$(uname)" != "Darwin" ]]; then
	echo "error: iOS plugins can only be built on macOS." >&2
	exit 1
fi

if ! command -v xcrun >/dev/null; then
	echo "error: Xcode command line tools not found." >&2
	exit 1
fi

SDK_DEVICE="$(xcrun --sdk iphoneos --show-sdk-path)"
SDK_SIM="$(xcrun --sdk iphonesimulator --show-sdk-path)"
MIN_IOS="14.0"

BUILD_DIR="build/${TARGET}"
mkdir -p "${BUILD_DIR}"

SOURCES=(
	pixel_painter_bluetooth.mm
	register_types.mm
)

# Godot's headers are not installed anywhere; they are consumed straight out of
# the engine source tree, which is why GODOT_SRC is mandatory.
INCLUDES=(
	-I"${GODOT_SRC}"
	-I"${GODOT_SRC}/platform/ios"
	-I.
	-I../shared
)

FLAGS=(-std=c++17 -fobjc-arc -Wall -Wno-unused-parameter)
if [[ "${TARGET}" == "debug" ]]; then
	FLAGS+=(-g -O0 -DDEBUG_ENABLED)
else
	FLAGS+=(-O2)
fi

build_slice() {
	local arch="$1"
	local sdk="$2"
	local min_flag="$3"
	local out="$4"

	local objects=()
	for src in "${SOURCES[@]}"; do
		local obj="${BUILD_DIR}/$(basename "${src%.*}")-${arch}.o"
		echo "  CC  ${src} (${arch})"
		xcrun clang -c "${src}" -o "${obj}" \
			-arch "${arch}" -isysroot "${sdk}" "${min_flag}" \
			"${FLAGS[@]}" "${INCLUDES[@]}"
		objects+=("${obj}")
	done

	xcrun libtool -static -o "${out}" "${objects[@]}"
}

echo "Building device slice (arm64)…"
build_slice arm64 "${SDK_DEVICE}" "-mios-version-min=${MIN_IOS}" \
	"${BUILD_DIR}/libpixel_painter_bluetooth.device.a"

echo "Building simulator slice (arm64)…"
build_slice arm64 "${SDK_SIM}" "-mios-simulator-version-min=${MIN_IOS}" \
	"${BUILD_DIR}/libpixel_painter_bluetooth.sim.a"

# Godot's iOS export expects the plain .a name from the .gdip; ship the device
# slice under that name and keep the simulator slice alongside for local testing.
cp "${BUILD_DIR}/libpixel_painter_bluetooth.device.a" \
	"${BUILD_DIR}/libpixel_painter_bluetooth.a"

echo ""
echo "Built ${BUILD_DIR}/libpixel_painter_bluetooth.a"
echo ""
echo "Next:"
echo "  mkdir -p ../../ios/plugins"
echo "  cp ${BUILD_DIR}/libpixel_painter_bluetooth.a ../../ios/plugins/"
echo "  cp PixelPainterBluetooth.gdip ../../ios/plugins/"
echo "  …then tick the plugin in the iOS export preset and re-export."
