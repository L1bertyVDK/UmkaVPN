#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"; OUT="$ROOT/out"
rm -rf "$OUT" && mkdir -p "$OUT"/{arm64-v8a,armeabi-v7a,x86,x86_64}

echo "=== sslocal (shadowsocks-rust) ==="
git clone --depth=1 https://github.com/shadowsocks/shadowsocks-rust.git ss-rust
pushd ss-rust >/dev/null
cargo ndk -t arm64-v8a   -o "$OUT" build --release --bin sslocal && mv "$OUT/arm64-v8a/sslocal" "$OUT/arm64-v8a/ss-local"
cargo ndk -t armeabi-v7a -o "$OUT" build --release --bin sslocal && mv "$OUT/armeabi-v7a/sslocal" "$OUT/armeabi-v7a/ss-local"
cargo ndk -t x86         -o "$OUT" build --release --bin sslocal && mv "$OUT/x86/sslocal" "$OUT/x86/ss-local"
cargo ndk -t x86_64      -o "$OUT" build --release --bin sslocal && mv "$OUT/x86_64/sslocal" "$OUT/x86_64/ss-local"
popd >/dev/null

echo "=== tun2socks (xjasonlyu/tun2socks) ==="
git clone --depth=1 https://github.com/xjasonlyu/tun2socks.git t2s
pushd t2s >/dev/null
CGO_ENABLED=1 CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" GOOS=android GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o "$OUT/arm64-v8a/tun2socks" ./cmd/tun2socks
CGO_ENABLED=1 CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi24-clang" GOOS=android GOARCH=arm GOARM=7 go build -trimpath -ldflags="-s -w" -o "$OUT/armeabi-v7a/tun2socks" ./cmd/tun2socks
CGO_ENABLED=1 CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android24-clang" GOOS=android GOARCH=386 go build -trimpath -ldflags="-s -w" -o "$OUT/x86/tun2socks" ./cmd/tun2socks
CGO_ENABLED=1 CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android24-clang" GOOS=android GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$OUT/x86_64/tun2socks" ./cmd/tun2socks
popd >/dev/null

(cd "$OUT"/.. && zip -r out.zip out)
echo "Done: out.zip"
