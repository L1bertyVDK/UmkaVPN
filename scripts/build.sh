#!/usr/bin/env bash
set -euo pipefail

API=24  # minSdk 24
ROOT="$(pwd)"
OUT="$ROOT/out"
rm -rf "$OUT" && mkdir -p "$OUT"/{arm64-v8a,armeabi-v7a,x86,x86_64}

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
AR="$TOOLCHAIN/llvm-ar"

build_sslocal() {
  local TARGET="$1" CC="$2" OUTDIR="$3"
  echo ">>> sslocal for $TARGET"
  RUSTFLAGS="-C link-arg=-fuse-ld=lld" \
  CC_${TARGET//-/_}="$CC" \
  AR_${TARGET//-/_}="$AR" \
  CARGO_TARGET_${TARGET//-/_}_LINKER="$CC" \
  cargo build --release --target "$TARGET" --bin sslocal
  cp "target/$TARGET/release/sslocal" "$OUT/$OUTDIR/ss-local"
}

echo "=== Setup Rust targets ==="
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android

echo "=== Clone shadowsocks-rust ==="
git clone --depth=1 https://github.com/shadowsocks/shadowsocks-rust.git ss-rust
pushd ss-rust >/dev/null

build_sslocal aarch64-linux-android      "$TOOLCHAIN/aarch64-linux-android${API}-clang"      arm64-v8a
build_sslocal armv7-linux-androideabi    "$TOOLCHAIN/armv7a-linux-androideabi${API}-clang"   armeabi-v7a
build_sslocal i686-linux-android         "$TOOLCHAIN/i686-linux-android${API}-clang"         x86
build_sslocal x86_64-linux-android       "$TOOLCHAIN/x86_64-linux-android${API}-clang"       x86_64

popd >/dev/null

echo "=== Build tun2socks (eycorsican/go-tun2socks) ==="
git clone --depth=1 https://github.com/eycorsican/go-tun2socks.git t2s
pushd t2s >/dev/null

CGO_ENABLED=1 CC="$TOOLCHAIN/aarch64-linux-android${API}-clang" GOOS=android GOARCH=arm64 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/arm64-v8a/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="$TOOLCHAIN/armv7a-linux-androideabi${API}-clang" GOOS=android GOARCH=arm GOARM=7 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/armeabi-v7a/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="$TOOLCHAIN/i686-linux-android${API}-clang" GOOS=android GOARCH=386 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/x86/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="$TOOLCHAIN/x86_64-linux-android${API}-clang" GOOS=android GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" -o "$OUT/x86_64/tun2socks" ./cmd/tun2socks

popd >/dev/null

echo "=== Results ==="
find "$OUT" -maxdepth 2 -type f -printf "%p\t%k KB\n"

echo "=== Pack ==="
(cd "$OUT"/.. && zip -r out.zip out >/dev/null)
mv "$OUT/../out.zip" "$ROOT/out.zip"
echo "OK: out.zip ready"
