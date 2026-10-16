# psperera-anyps5-mac

Scripts for running [AnyPS5](https://github.com/boykopovar/AnyPS5) on Apple Silicon, against
[yripper's `feat/macos-runtime`](https://github.com/yripper/AnyPS5/tree/feat/macos-runtime) branch
(x86-64 under Rosetta 2, Vulkan through MoltenVK), with a first-rung test title and a diff oracle.

AnyPS5 is not an emulator: it relinks a PS5 executable into a native binary and binds its imports to
reimplemented system libraries. The macOS runtime port exists upstream as a series of small PRs
tracked in [issue #1](https://github.com/boykopovar/AnyPS5/issues/1); these scripts only wrap the
branch's own `docs/user/MACOS.md` flow so they stay aligned as it changes.

## Scripts

| Script | What it does |
|---|---|
| `anyps5-mac.sh` | `build` (prereqs → clone → submodules → CMake x86_64 Release → ctest), `setup <dump> <game_dir>`, `run <game_dir> [--profile]`, `summary <log>`, `update` |
| `rung1-doom.sh` | Rung 1: [ps5-doom](https://github.com/lowbit/ps5-doom) (PPSA99666). `fetch` the release zip with sha256 check, `setup`, `oracle` (headless host build in Docker renders reference frames), `run`, `capture`, `diff` |
| `test/selftest.sh` | Exercises every subcommand on any OS by shimming the Mac-only tools; asserts the exact external calls each path makes |

## Requirements (on the Mac)

- Apple Silicon, Rosetta 2, Xcode Command Line Tools
- `brew install cmake ninja python imagemagick` (ImageMagick only for `diff`)
- [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) at `~/VulkanSDK/<ver>/macOS`, or `VULKAN_SDK` set
- Docker Desktop (only for the `oracle` step)
- ~20 GiB free where the checkout lives (`ANYPS5_ROOT`; defaults to `/Volumes/Lexar4TB/anyps5` if mounted, else `~/anyps5`)

## Use

```sh
./anyps5-mac.sh build            # expect ~12 AGC test failures; that is the branch's current baseline
./rung1-doom.sh all              # fetch → setup → oracle → run
./rung1-doom.sh capture          # while DOOM is running
./rung1-doom.sh diff             # RMSE of captured frames vs the oracle
```

A uniform colour shift in the diff points at the palette or scaler; structured garbage points at the
wave64 `present.cl` compute kernel miscompiling for a 32-lane GPU. Hold L1+R1 at launch to force
ps5-doom's CPU scaler and bisect between the two.

Rung 2, once DOOM presents: [ps5-openrct2](https://github.com/lowbit/ps5-openrct2) (PPSA99728) with
your own RollerCoaster Tycoon 2 files.

## Test

```sh
shellcheck -S warning anyps5-mac.sh rung1-doom.sh
bash test/selftest.sh
```

## Known gaps

- `rung1-doom.sh capture` assumes `tools/console_test.py --host/--out`; those flags are unverified, so it falls back to timed `screencapture`.
- `run.sh` on the branch may not forward `-timedemo demo1`; start the demo from the launcher if the diff frames do not line up.

## License

MIT. AnyPS5 is GPL-2.0, ps5-doom is GPL-2.0; nothing from either is vendored here.
