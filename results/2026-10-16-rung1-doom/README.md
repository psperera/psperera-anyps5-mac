# Rung 1 — ps5-doom on Mac Studio M1 Ultra — PASS

2026-10-16. macOS 27.2, Mac Studio (Apple M1 Ultra, 64 GB), x86-64 build under Rosetta 2,
Vulkan SDK 1.4.363.0 / MoltenVK, yripper/AnyPS5 `feat/macos-runtime` at the commit in
`anyps5-branch-head.txt`, ps5-doom v1.0.1 (PPSA99666), shareware `doom1.wad`, attract demo via `app0/test.cfg`.

| Step | Result |
|---|---|
| Build | relinker + 127 `.prx` built; 10 test-only targets fail (`build-failures.txt`: SIGUSR1 macro clash, missing `<initializer_list>`, Linux-only dma-buf) — same set PlutoDeveloper's "build and run the test suite on Apple silicon" commit fixes |
| Relink | `tools/unself.py` magic patch fired for `libc.prx`; relinker: 164 external prx refs, 1 converted module, 4.7 MB Mach-O `eboot` |
| Run | MoltenVK device on Apple M1 Ultra, `subgroup=32`, `depthRangeUnrestricted=0`; title listened on 9119, loaded WAD, audio at 48 kHz |
| Presenter | **`video: AGC compute presentation`** — the gfx1010 wave64 `present.cl` kernel recompiled and ran on the GPU; no CPU-scaler fallback |
| Frames | frame 900 captured over the socket and de-tiled; visually identical to the host oracle (same HUD text, corridor, corpse); RMSE 21.8/255 vs the 320×200 oracle after sharp-bilinear up/box down resampling |
| Exit | `ps5: exit 0` at frame 1000, then **`libc++abi: terminating … mutex lock failed: Invalid argument`** during teardown — a shutdown-ordering bug in the macOS runtime, not in the title |

Not yet done: frame 120 (consumed by a first capture attempt that failed on a broken numpy), `run-profile.sh`, a second clean run for determinism.

Env notes: Homebrew `numpy` was a broken namespace package until reinstalled; `python3` on PATH was the Claude MCP venv — scripts should prefer `/opt/homebrew/bin/python3`.
