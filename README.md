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
| `tools/unself.py` | The branch's SELF unwrapper plus the second fake-signed magic (`54 14 f5 ee`) that `ps5-native-tool` writes for `libc.prx`; `rung1-doom.sh setup` installs it only if the branch's copy still rejects the file |
| `tools/doom-capture.py` | Standalone client for ps5-doom's frame socket (9119): receive, de-tile the 512×128 PS5 layout, write PNG. Verified as an exact round-trip against `tiling.h` |
| `tools/rung1-plan.cfg` | The `test.cfg` plan the title reads from `app0/`: skip the launcher, run the attract demo, capture frames 120 and 900, serve them on 9119 |
| `test/selftest.sh` | Exercises every subcommand on any OS by shimming the Mac-only tools; asserts the exact external calls each path makes |

## Requirements (on the Mac)

- Apple Silicon, Rosetta 2, Xcode Command Line Tools
- `brew install cmake ninja python imagemagick` (ImageMagick only for `diff`)
- [LunarG Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) at `~/VulkanSDK/<ver>/macOS`, or `VULKAN_SDK` set
- Docker Desktop (only for the `oracle` step; `test/oracle/` already holds reference frames rendered from the same plan, so `diff` works without it)
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

## Verified against the real artefacts (2026-10-15)

- `PPSA99666.zip` v1.0.1: 2.2 MB, sha256 matches the published file; contains `eboot.bin` (fake-signed SELF → x86-64 `ET_SCE_DYNEXEC`, FreeBSD OSABI), `sce_module/libc.prx` (second magic, unwraps to a valid `ET_SCE_DYNLIB` with all 14 phdrs), `sce_sys/param.json`, `wads/doom1.wad`.
- The branch's `run.sh` does `exec ./eboot` with no arguments, so the demo is driven by `app0/test.cfg` instead; the oracle runs the same attract demo with `DOOM_IWAD`/`DOOM_CAPTURE`/`DOOM_FRAMES`.
- ps5-doom's `console_test.py` depends on the author's private console tooling (`ps5.py`, Payload Manager); `tools/doom-capture.py` replaces it.

## Oracle without Docker

The host backend also builds natively with clang 18 and libcurl headers (`make host` in the ps5-doom checkout). Where only the runtime `libcurl.so.4` is present, fetch the matching `include/curl/*.h` from curl's tag and pass `HOST_FLAGS="... -I<dir>" HOST_CC="clang -L<dir with libcurl.so symlink>"`. Only the WAD-download helper links curl; the demo path never calls it.

## Known gaps

- Whether AnyPS5's offline socket stack lets the title `listen()` on 9119 is untested; `capture` falls back to timed `screencapture` if the socket never opens.
- The `tools/unself.py` magic fix should go upstream to the branch; until then `setup` patches the checkout in place and keeps `unself.py.orig`.

## License

MIT. AnyPS5 is GPL-2.0, ps5-doom is GPL-2.0; nothing from either is vendored here.
