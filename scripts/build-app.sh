#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
whisper_lib="$project_dir/Vendor/whisper.cpp/build-livecaption/src/libwhisper.a"
if [[ ! -f "$whisper_lib" ]]; then
  if [[ -x "$project_dir/.tools/bin/cmake" ]]; then
    cmake_bin="$project_dir/.tools/bin/cmake"
  elif command -v cmake >/dev/null; then
    cmake_bin="$(command -v cmake)"
  else
    echo "缺少 CMake。请先运行：python3 -m venv .tools && .tools/bin/pip install cmake" >&2
    exit 1
  fi
  "$cmake_bin" -S Vendor/whisper.cpp -B Vendor/whisper.cpp/build-livecaption \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON -DGGML_BLAS=ON -DGGML_NATIVE=OFF
  "$cmake_bin" --build Vendor/whisper.cpp/build-livecaption --config Release -j "$(sysctl -n hw.logicalcpu)"
fi
swift build -c release "$@"
build_bin="$(swift build -c release --show-bin-path "$@")"
app_dir="$project_dir/dist/LiveCaption.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_bin/LiveCaption" "$app_dir/Contents/MacOS/LiveCaption"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
licenses_dir="$app_dir/Contents/Resources/Licenses"
mkdir -p "$licenses_dir/FluidAudio"
cp LICENSE THIRD_PARTY_NOTICES.md "$licenses_dir/"
cp Vendor/whisper.cpp/LICENSE "$licenses_dir/whisper.cpp-LICENSE"
cp Vendor/FluidAudio/LICENSE "$licenses_dir/FluidAudio/LICENSE"
cp Vendor/FluidAudio/ThirdPartyLicenses/* "$licenses_dir/FluidAudio/"
for resource_bundle in "$build_bin/"*.bundle(N); do
  ditto "$resource_bundle" "$app_dir/Contents/Resources/${resource_bundle:t}"
done
codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.wishyoujoy.livecaption"' \
  "$app_dir"
echo "$app_dir"
