#!/usr/bin/env bash
# Compila las extensiones Rust para Linux de forma COMPATIBLE con el Godot de
# Flatpak (runtime org.freedesktop.Platform, glibc 2.42): un binario hecho
# con el compilador del sistema (p. ej. Fedora, glibc 2.43) no carga ahí.
#   · glibc 2.28 vía `cargo zigbuild` (pip install --user ziglang;
#     cargo install cargo-zigbuild).
#   · vectopen_vectorizer enlaza ONNX Runtime (C++ / libstdc++): se enlaza
#     contra la libstdc++ de la PROPIA runtime de Flatpak, así no puede pedir
#     símbolos que la runtime no tenga.
# Deja los .so en target/{debug,release}/ (las rutas de los .gdextension).
set -euo pipefail
cd "$(dirname "$0")"
TRIPLE=x86_64-unknown-linux-gnu
RT="${FLATPAK_RUNTIME:-$HOME/.local/share/flatpak/runtime/org.freedesktop.Platform/x86_64/25.08/active/files}"
STDCXX="$(ls "$RT"/lib/x86_64-linux-gnu/libstdc++.so.6.* | head -1)"

build() {
	local crate="$1" flags="${2:-}"
	( cd "$crate"
	  CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="$flags" \
		cargo zigbuild --release --target "$TRIPLE.2.28"
	  mkdir -p target/debug target/release
	  local so="target/$TRIPLE/release/lib$crate.so"
	  cp -f "$so" "target/debug/lib$crate.so.new" && mv -f "target/debug/lib$crate.so.new" "target/debug/lib$crate.so"
	  cp -f "$so" "target/release/lib$crate.so.new" && mv -f "target/release/lib$crate.so.new" "target/release/lib$crate.so"
	  echo "OK  $crate"
	)
}

build vectopen_text
build vectopen_vectorizer "-C link-arg=$STDCXX"
