#!/usr/bin/env bash
set -euo pipefail

API=24  # minSdk
ROOT="$(pwd)"
OUT="$ROOT/out"
rm -rf "$OUT" && mkdir -p "$OUT"/{arm64-v8a,armeabi-v7a,x86,x86_64}

TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
AR="${TOOLCHAIN}/llvm-ar"

echo "NDK: ${ANDROID_NDK_HOME}"
echo "TOOLCHAIN: ${TOOLCHAIN}"

# Проверим, что компиляторы на месте
for cc in \
  "aarch64-linux-android${API}-clang" \
  "armv7a-linux-androideabi${API}-clang" \
  "i686-linux-android${API}-clang" \
  "x86_64-linux-android${API}-clang"
do
  test -x "${TOOLCHAIN}/${cc}" || { echo "ERROR: ${TOOLCHAIN}/${cc} not found"; exit 1; }
done

# Для cc crate: CC_<triple> и AR_<triple> (lowercase с _)
export_cc_vars () {
  local TARGET="$1"; local CC="$2"
  local TUP="$(echo "${TARGET}" | tr '-' '_')"       # aarch64-linux-android -> aarch64_linux_android
  eval "export CC_${TUP}='${CC}'"
  eval "export AR_${TUP}='${AR}'"
}

build_sslocal () {
  local TARGET="$1" CC="$2" SUB="$3"
  echo ">>> sslocal for ${TARGET}"
  export_cc_vars "${TARGET}" "${CC}"
  # Ключ: укажем rustc явный линкер clang из NDK
  RUSTFLAGS="-C linker=${CC} -C link-arg=-fuse-ld=lld" \
    cargo build --release --target "${TARGET}" --bin sslocal
  cp "target/${TARGET}/release/sslocal" "${OUT}/${SUB}/ss-local"
  chmod +x "${OUT}/${SUB}/ss-local"
}

echo "=== Clone shadowsocks-rust ==="
git clone --depth=1 https://github.com/shadowsocks/shadowsocks-rust.git ss-rust
pushd ss-rust >/dev/null
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android

build_sslocal aarch64-linux-android   "${TOOLCHAIN}/aarch64-linux-android${API}-clang"      arm64-v8a
build_sslocal armv7-linux-androideabi "${TOOLCHAIN}/armv7a-linux-androideabi${API}-clang"   armeabi-v7a
build_sslocal i686-linux-android      "${TOOLCHAIN}/i686-linux-android${API}-clang"         x86
build_sslocal x86_64-linux-android    "${TOOLCHAIN}/x86_64-linux-android${API}-clang"       x86_64
popd >/dev/null

echo "=== Build tun2socks (eycorsican/go-tun2socks) ==="
git clone --depth=1 https://github.com/eycorsican/go-tun2socks.git t2s
pushd t2s >/dev/null

CGO_ENABLED=1 CC="${TOOLCHAIN}/aarch64-linux-android${API}-clang" GOOS=android GOARCH=arm64 \
  go build -trimpath -ldflags="-s -w" -o "${OUT}/arm64-v8a/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="${TOOLCHAIN}/armv7a-linux-androideabi${API}-clang" GOOS=android GOARCH=arm GOARM=7 \
  go build -trimpath -ldflags="-s -w" -o "${OUT}/armeabi-v7a/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="${TOOLCHAIN}/i686-linux-android${API}-clang" GOOS=android GOARCH=386 \
  go build -trimpath -ldflags="-s -w" -o "${OUT}/x86/tun2socks" ./cmd/tun2socks

CGO_ENABLED=1 CC="${TOOLCHAIN}/x86_64-linux-android${API}-clang" GOOS=android GOARCH=amd64 \
  go build -trimpath -ldflags="-s -w" -o "${OUT}/x86_64/tun2socks" ./cmd/tun2socks
popd >/dev/null

echo "=== Results ==="
find "${OUT}" -maxdepth 2 -type f -printf "%p\t%k KB\n"

echo "=== Pack ==="
( cd "${OUT}/.." && zip -r out.zip out >/dev/null )
mv "${OUT}/../out.zip" "${ROOT}/out.zip"
echo "OK: out.zip ready"
