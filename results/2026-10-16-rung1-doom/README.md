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

## Second run (profile) — 2026-10-16 03:32

- `run-profile.sh`, same test plan. **35.3 presents/s** (DOOM's 35 Hz tic rate), 0 dropped, GPU busy ~8 ms/frame, `inflight_wait` p50 8.3 ms / p90 10.5 ms; 1000 dispatches, 2 pipeline-cache misses then all hits; dispatch overhead ~50 µs. Log: `profile-*.log`.
- Frames 120 and 900 captured over 9119 and de-tiled (`mac-frame*-320.png`): **RMSE 3.7 and 2.0 /255** vs the oracle after resampling; 90 % / 98 % of pixels within 8. The 21.8 in run 1 was from a corrupted first pull, not the render.
- Clean exit, no teardown crash this time — the `mutex lock failed` abort is intermittent (1 of 2 runs).
