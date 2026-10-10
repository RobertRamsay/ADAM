# ADAM tools

Developer tooling. None of this ships with ADAM.

| Path | What it is |
|---|---|
| `assemble_engine.ps1` | Rebuilds `datafiles/engine/engine.bin` and `boot.bin` with vasm (`-Fbin -pic -m68000 -no-opt`). |
| `run_adf.ps1` | Boots an ADF in FS-UAE as a stock A600 or A1200, exactly like ADAM's Build and play. |
| `reference/adf_reference.py` | Python copy of `scripts/scr_adf` (data block + ADF writer). Used to test the engine without GameMaker. **Must stay in step with `scr_adf.gml` and `engine.s`.** |
| `reference/gen_examples.py` | Generates the four example games in `datafiles/examples/` (deterministic) plus test ADFs and preview PNGs in `reference/out/`. Needs Pillow. |
| `reference/art.py` | 16 x 24 sprite string art used by the examples. |
| `linux_test/*.sh` | The headless FS-UAE harness used during development (Xvfb + xdotool + xwd screenshots). Reference only on Windows. |
| `intro/render_intro.py` | Renders the 1080p60 YouTube intro frames + audio (`intro.wav`). Encode with: `ffmpeg -framerate 60 -i frames/f%03d.png -i intro.wav -c:v libx264 -pix_fmt yuv420p -crf 14 -c:a aac -b:a 256k -shortest ADAM_intro_1080p60.mp4` |

Typical engine loop: edit `engine.s` → `assemble_engine.ps1` → `python reference/gen_examples.py` → `run_adf.ps1 -Adf reference/out/gem_hunter.adf`.
