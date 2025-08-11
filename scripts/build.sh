#!/usr/bin/env bash
set -euo pipefail

API=24  # соответствует minSdk
ROOT="$(pwd)"
OUT="$ROOT/out"

# Очистка/создание выходных папок
rm -rf "$OUT" && mkdir -p "$OUT"/{arm64-v8a,armeabi-v7a,x86,x86_64}

# Пути к инструментам NDK
: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is not set}"
TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
AR="${TOOLCHAIN}/llvm-ar"

echo "NDK: ${ANDROID_NDK_HOME}"
echo "TOOLCHAIN: ${TOOLCHAIN}"

# Проверим, что нужные компиляторы существуют
for cc in \
  "aarch64-linux-android${API}-clang" \
  "armv7a-linux-androideabi${API}-clang" \
  "i686-linux-android${API}-clang" \
  "x86_64-linux-android${API}-clang"
do
  if [[ ! -x "${TOOLCHAIN}/${cc}" ]]; then
    echo "ERROR: ${TOOLCHAIN}/${cc} not found or not executable"
    exit 1
  fi
done

# Экспорт переменных среды для cc crate и rustc под конкретный target
export_cc_vars () {
  local TARGET="$1"; local CC="$2"
  local TUP
  TUP="$(echo "${TARGET}" | tr '-' '_')"   # aarch64-linux-android -> aarch64_linux_android
  eval "export CC_${TUP}='${CC}'"
  eval "export AR_${TUP}='${AR}'"
  eval "export CARGO_TARGET_${TUP}_LINKER='${CC}'"
}

# Сборка sslocal (Shadowsocks) под target + копирование в OUT
build_sslocal () {
  local TARGET="$1" CC="$2" SUBDIR="$3"
  echo ">>> build sslocal for ${TARGET}"
  export_cc_vars "${TARGET}" "${CC}"
  # Явно задаём линкер clang из NDK для rustc
  RUSTFLAGS="-C linker=${CC} -C link-arg=-fuse-ld=lld" \
    cargo build --release --target "${TARGET}" --bin sslocal
  cp "target/${TARGET}/release/sslocal" "${OUT}/${SUBDIR}/ss-local"
  chmod +x "${OUT}/${SUBDIR}/ss-local"
}

echo "=== Clone shadowsocks-rust ==="
git clone --depth=1 https://github.com/shadowsocks/shadowsocks-rust.git ss-rust
pushd ss-rust >/dev/null

# Добавим таргеты (на случай локального запуска)
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android

# Сборка под все ABI
build_sslocal aarch64-linux-android   "${TOOLCHAIN}/aarch64-linux-android${API}-clang"      arm64-v8a
build_sslocal armv7-linux-androideabi "${TOOLCHAIN}/armv7a-linux-androideabi${API}-clang"   armeabi-v7a
build_sslocal i686-linux-android      "${TOOLCHAIN}/i686-linux-android${API}-clang"         x86
build_sslocal x86_64-linux-android    "${TOOLCHAIN}/x86_64-linux-android${API}-clang"       x86_64

popd >/dev/null

echo "=== Build tun2socks (eycorsican/go-tun2socks) ==="
git clone --depth=1 https://github.com/eycorsican/go-tun2socks.git t2s
pushd t2s >/dev/null

# Сборка go-tun2socks под все ABI с использованием компиляторов NDK
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
rm -f "${ROOT}/out.zip"
( cd "${OUT}/.." && zip -r "${ROOT}/out.zip" out >/dev/null )
echo "OK: ${ROOT}/out.zip ready"
