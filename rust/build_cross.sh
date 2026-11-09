#!/usr/bin/env bash
# Compila las extensiones Rust para WINDOWS y macOS desde Linux (para probar
# paquetes en local; la release oficial las compila en GitHub Actions):
#   · Windows x86_64: `cargo zigbuild` (target x86_64-pc-windows-gnullvm).
#   · macOS universal: osxcross (SDK de Apple) → Intel con mínimo 10.13 y
#     Apple Silicon con mínimo 11, unidos con llvm-lipo.
# Deja los .dll / .dylib en target/release/ (las rutas de los .gdextension).
#   rust/build_cross.sh                    (vectopen_text y vectopen_io)
#   rust/build_cross.sh vectopen_io        (solo esa)
#   OSXCROSS=/ruta/a/osxcross/target       (por defecto ~/Proyectos/osxcross/target)
set -euo pipefail
cd "$(dirname "$0")"
OSX="${OSXCROSS:-$HOME/Proyectos/osxcross/target}"
CRATES=("$@")
[ ${#CRATES[@]} -eq 0 ] && CRATES=(vectopen_text vectopen_io)

win() {
	( cd "$1"
	  cargo zigbuild --release --target x86_64-pc-windows-gnullvm
	  mkdir -p target/release
	  cp -f "target/x86_64-pc-windows-gnullvm/release/$1.dll" target/release/
	  echo "OK  $1 (Windows)" )
}

mac() {
	( cd "$1"
	  export PATH="$OSX/bin:$PATH"
	  local x86cc arm
	  x86cc="$(ls "$OSX/bin" | grep -E '^x86_64-apple-darwin[0-9.]+-clang$' | head -1)"
	  arm="$(ls "$OSX/bin" | grep -E '^aarch64-apple-darwin[0-9.]+-clang$' | head -1)"
	  CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$x86cc" CC_x86_64_apple_darwin="$x86cc" \
	  MACOSX_DEPLOYMENT_TARGET=10.13 cargo build --release --target x86_64-apple-darwin
	  CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER="$arm" CC_aarch64_apple_darwin="$arm" \
	  MACOSX_DEPLOYMENT_TARGET=11.0 cargo build --release --target aarch64-apple-darwin
	  mkdir -p target/release
	  llvm-lipo -create \
		"target/x86_64-apple-darwin/release/lib$1.dylib" \
		"target/aarch64-apple-darwin/release/lib$1.dylib" \
		-output "target/release/lib$1.dylib"
	  echo "OK  $1 (macOS universal)" )
}

for c in "${CRATES[@]}"; do
	win "$c"
	mac "$c"
done
