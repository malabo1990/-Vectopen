# Vídeo promocional de Vectopen

Cómo se hace (30 s, 16:9 y 9:16):

1. Ilustraciones en `~/.cache/vectopen_tests/promo_assets/undraw/` (por ahora
   `designer-girl.svg`, del espejo
   [balazser/undraw-svg-collection](https://github.com/balazser/undraw-svg-collection)).
2. Grabar con el Movie Maker de Godot (interfaz y cartel en inglés):

   ```bash
   E2E_TIMEOUT=900 E2E_ENV="PROMO_LANG=en" \
   E2E_ARGS="--write-movie $HOME/.cache/vectopen_tests/promo_en/f.png --fixed-fps 30" \
       test/run_e2e.sh promo_video_e2e
   grep '^MARK' ~/.cache/vectopen_tests/promo_video_e2e.log > ~/.cache/vectopen_tests/promo_en/marks.txt
   ```

3. Montar (tarjetas, rótulos, logo final, versión vertical):

   ```bash
   python3 tools/promo/make_promo.py ~/.cache/vectopen_tests/promo_en en
   ```

## Créditos y licencias

| Recurso | Autor | Licencia |
|---|---|---|
| Ilustración «designer girl» | Katerina Limpitsouni · [unDraw](https://undraw.co) | [Licencia unDraw](https://undraw.co/license): uso comercial, con cambios, sin atribución obligatoria. No se permite redistribuirlas en packs, entrenar IA ni enlazarlas directamente desde su web. |
| Tipografía Inter | Rasmus Andersson | SIL Open Font License 1.1 |
| Logo, interfaz y cartel | Vectopen | MIT |

No se usan logotipos de marcas ajenas. Otras ilustraciones válidas para más
piezas: [Open Peeps](https://www.openpeeps.com/) y
[Open Doodles](https://www.opendoodles.com/) (CC0, dominio público).
