#!/usr/bin/env bash
set -euo pipefail

API=24 # minSdk 24
ROOT="$(pwd)"
OUT="$ROOT/out"

rm -rf "$OUT" && mkdir -p "$OUT"/{arm64-v8a,armeabi-v7a,x86,x86_64}

echo "=== Building sslocal (shadowsocks-rust) ==="
git clone --depth=1 https://github.com/shadowsocks/shadowsocks-rust.git ss-rust
pushd ss-rust >/dev/null

# Собираем "sslocal" и переименовываем в "ss-local"
cargo ndk -t arm64-v8a   -o "$OUT" build --release --bin sslocal
[ -f "$OUT/arm64-v8a/sslocal" ] && mv "$OUT/arm64-v8a/sslocal" "$OUT/arm64-v8a/ss-local"

cargo ndk -t armeabi-v7a -o "$OUT" build --release --bin sslocal
[ -f "$OUT/armeabi-v7a/sslocal" ] && mv "$OUT/armeabi-v7a/sslocal" "$OUT/armeabi-v7a/ss-local"

cargo ndk -t x86         -o "$OUT" build --release --bin sslocal
[ -f "$OUT/x86/sslocal" ] && mv "$OUT/x86/sslocal" "$OUT/x86/ss-local"

cargo ndk -t x86_64      -o "$OUT" build --release --bin sslocal
[ -f "$OUT/x86_64/sslocal" ] && mv "$OUT/x86_64/sslocal" "$OUT/x86_64/ss-local"

popd >/dev/null

echo "=== Building tun2socks (eycorsican/go-tun2socks) ==="
git clone --depth=1 https://github.com/eycorsican/go-tun2socks.git t2s
pushd t2s >/dev/null

# Проверим, что есть пакет ./cmd/tun2socks
test -d cmd/tun2socks || (echo "cmd/tun2socks not found"; ls -la; ls -la cmd; exit 1)

# Пути к компиляторам из NDK (linux runner)
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"

# arm64-v8a
CGO_ENABLED=1 \
CC="$TOOLCHAIN/aarch64-linux-android${API}-clang" \
GOOS=android GOARCH=arm64 \
go build -trimpath -ldflags="-s -w" -o "$OUT/arm64-v8a/tun2socks" ./cmd/tun2socks

# armeabi-v7a
CGO_ENABLED=1 \
CC="$TOOLCHAIN/armv7a-linux-androideabi${API}-clang" \
GOOS=android GOARCH=arm GOARM=7 \
go build -trimpath -ldflags="-s -w" -o "$OUT/armeabi-v7a/tun2socks" ./cmd/tun2socks

# x86
CGO_ENABLED=1 \
CC="$TOOLCHAIN/i686-linux-android${API}-clang" \
GOOS=android GOARCH=386 \
go build -trimpath -ldflags="-s -w" -o "$OUT/x86/tun2socks" ./cmd/tun2socks

# x86_64
CGO_ENABLED=1 \
CC="$TOOLCHAIN/x86_64-linux-android${API}-clang" \
GOOS=android GOARCH=amd64 \
go build -trimpath -ldflags="-s -w" -o "$OUT/x86_64/tun2socks" ./cmd/tun2socks

popd >/dev/null

echo "=== Checking results ==="
find "$OUT" -maxdepth 2 -type f -printf "%p\t%k KB\n"

echo "=== Pack to out.zip ==="
(cd "$OUT"/.. && zip -r out.zip out >/dev/null)
mv "$OUT/../out.zip" "$ROOT/out.zip"
echo "OK: out.zip ready"
