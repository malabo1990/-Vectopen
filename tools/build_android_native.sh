#!/usr/bin/env bash
# =============================================================================
# Compila las librerías nativas (Rust) de Vectopen para Android con el NDK:
# texto (vectopen_text) e importadores (vectopen_io), arm64 y x86_64.
# Los .gdextension ya apuntan a target/<triple>/release/. Se ejecuta antes de
# exportar la APK. El vectorizador IA no se compila para Android (su motor
# ONNX Runtime no se incluye): la app lo indica en el panel Vectorizar.
# Uso: tools/build_android_native.sh   (NDK: $ANDROID_NDK_HOME o el último de
#      ~/Android/Sdk/ndk/)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/../rust"
NDK="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Android/Sdk/ndk/* 2>/dev/null | sort -V | tail -1)}"
[ -d "$NDK" ] || { echo "No encuentro el NDK de Android (ANDROID_NDK_HOME)"; exit 1; }
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
API=24
for TRIPLE in aarch64-linux-android x86_64-linux-android; do
	rustup target add "$TRIPLE" >/dev/null 2>&1 || true
	U="$(echo "$TRIPLE" | tr 'a-z-' 'A-Z_')"
	export "CARGO_TARGET_${U}_LINKER=$TC/${TRIPLE}${API}-clang"
	export "CC_${TRIPLE//-/_}=$TC/${TRIPLE}${API}-clang"
	export "AR_${TRIPLE//-/_}=$TC/llvm-ar"
	for C in vectopen_text vectopen_io; do
		(cd "$C" && cargo build --release --target "$TRIPLE")
		echo "  ✓ $C ($TRIPLE)"
	done
done
