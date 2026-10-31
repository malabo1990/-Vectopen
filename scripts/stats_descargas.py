#!/usr/bin/env python3
"""Snapshot diario de descargas de los releases de un repo de GitHub.

GitHub solo expone el contador ACUMULADO por archivo (sin histórico ni
fechas), así que este script lo fotografía y lo añade a un CSV versionado.
Es idempotente: si ya hay fila para la fecha, la reemplaza.

Uso:
    GITHUB_TOKEN=... python3 scripts/stats_descargas.py --repo dueno/repo
    python3 scripts/stats_descargas.py --repo dueno/repo --out stats/descargas.csv

Requiere solo la biblioteca estándar (funciona en el runner de Actions).
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Archivos que no son instaladores: no cuentan para el total.
EXCLUIR = {"sha256sums.txt", "sha256sums"}

CAMPOS = [
    "fecha",
    "total",
    "delta",
    "linux",
    "macos",
    "windows",
    "otros",
    "releases",
    "detalle",
]


def api(url: str, token: str) -> object:
    cabeceras = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "vectopen-stats",
    }
    if token:
        cabeceras["Authorization"] = f"Bearer {token}"
    peticion = urllib.request.Request(url, headers=cabeceras)
    with urllib.request.urlopen(peticion, timeout=30) as r:
        return json.loads(r.read())


def releases(repo: str, token: str) -> list[dict]:
    """Todas las releases, paginando de 100 en 100."""
    salida: list[dict] = []
    pagina = 1
    while True:
        lote = api(
            f"https://api.github.com/repos/{repo}/releases?per_page=100&page={pagina}",
            token,
        )
        if not isinstance(lote, list) or not lote:
            return salida
        salida.extend(lote)
        if len(lote) < 100:
            return salida
        pagina += 1


def plataforma(nombre: str) -> str:
    n = nombre.lower()
    if n.endswith((".exe", ".msi")) or "windows" in n or "win64" in n or "win-x64" in n:
        return "windows"
    if n.endswith(".dmg") or "macos" in n or "darwin" in n or "universal" in n:
        return "macos"
    if n.endswith((".deb", ".rpm", ".appimage")) or "linux" in n:
        return "linux"
    return "otros"


def snapshot(repo: str, token: str) -> dict:
    todas = releases(repo, token)
    conteo = {"linux": 0, "macos": 0, "windows": 0, "otros": 0}
    detalle: dict[str, int] = {}
    total = 0
    for rel in todas:
        for asset in rel.get("assets", []):
            nombre = str(asset.get("name", ""))
            if nombre.lower() in EXCLUIR:
                continue
            n = int(asset.get("download_count", 0) or 0)
            total += n
            conteo[plataforma(nombre)] += n
            detalle[nombre] = n
    return {
        "fecha": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "total": total,
        "linux": conteo["linux"],
        "macos": conteo["macos"],
        "windows": conteo["windows"],
        "otros": conteo["otros"],
        "releases": len(todas),
        "detalle": json.dumps(
            dict(sorted(detalle.items())), ensure_ascii=False, separators=(",", ":")
        ),
        "delta": 0,
    }


def leer(ruta: Path) -> list[dict]:
    if not ruta.exists():
        return []
    with ruta.open(newline="", encoding="utf-8") as f:
        return [dict(fila) for fila in csv.DictReader(f)]


def escribir(ruta: Path, filas: list[dict]) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with ruta.open("w", newline="", encoding="utf-8") as f:
        escritor = csv.DictWriter(f, fieldnames=CAMPOS)
        escritor.writeheader()
        for fila in filas:
            escritor.writerow({k: fila.get(k, "") for k in CAMPOS})


def main() -> int:
    parser = argparse.ArgumentParser(description="Snapshot de descargas de releases")
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY", ""),
        help="dueno/repo (por defecto GITHUB_REPOSITORY)",
    )
    parser.add_argument("--out", default="stats/descargas.csv")
    parser.add_argument("--print", action="store_true", help="imprimir el snapshot")
    args = parser.parse_args()

    if not args.repo or "/" not in args.repo:
        print("Falta --repo dueno/repo", file=sys.stderr)
        return 2

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    try:
        nuevo = snapshot(args.repo, token)
    except urllib.error.HTTPError as e:
        print(f"GitHub respondió {e.code}: {e.reason}", file=sys.stderr)
        if e.code in (403, 429):
            print("¿Rate limit? Se omite esta ejecución.", file=sys.stderr)
        return 1

    ruta = Path(args.out)
    filas = leer(ruta)
    filas = [f for f in filas if f.get("fecha") != nuevo["fecha"]]

    anterior = 0
    for f in filas:
        try:
            anterior = int(f.get("total", 0))
        except (TypeError, ValueError):
            anterior = 0
    nuevo["delta"] = nuevo["total"] - anterior if filas else int(nuevo["total"])

    filas.append(nuevo)
    filas.sort(key=lambda f: str(f.get("fecha", "")))
    escribir(ruta, filas)

    if args.print:
        print(json.dumps(nuevo, ensure_ascii=False, indent=2))
    print(f"{nuevo['fecha']}: {nuevo['total']} descargas (+{nuevo['delta']}) · {ruta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
