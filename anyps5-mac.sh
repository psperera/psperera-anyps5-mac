#!/usr/bin/env bash
# anyps5-mac.sh — build yripper/AnyPS5 feat/macos-runtime on Apple Silicon (x86-64 under Rosetta 2 + MoltenVK)
# and set up / run a title with the branch's own tools/macos scripts.
#
# Usage:
#   ./anyps5-mac.sh build                       # clone + submodules + configure + build (+ test)
#   ./anyps5-mac.sh setup <dump_dir> <game_dir> [module_dir ...]
#   ./anyps5-mac.sh run <game_dir> [--profile]  # run.sh or run-profile.sh
#   ./anyps5-mac.sh summary <profile.log>       # profile_summary.py
#   ./anyps5-mac.sh update                      # pull branch, rebuild
#
# Env overrides:
#   ANYPS5_ROOT   where the checkout lives      (default: /Volumes/Lexar4TB/anyps5 if mounted, else ~/anyps5)
#   ANYPS5_REMOTE fork to track                 (default: https://github.com/yripper/AnyPS5.git)
#   ANYPS5_BRANCH branch                        (default: feat/macos-runtime)
#   VULKAN_SDK    Vulkan SDK macOS dir          (default: newest ~/VulkanSDK/*/macOS)
#   ANYPS5_TESTS  1 to run ctest after build    (default: 1)
#   ANYPS5_JOBS   parallel build jobs           (default: nproc)

set -euo pipefail

# Homebrew tools first: a venv python (e.g. an MCP extension) can shadow the one with numpy/pillow
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ANYPS5_REMOTE="${ANYPS5_REMOTE:-https://github.com/yripper/AnyPS5.git}"
ANYPS5_BRANCH="${ANYPS5_BRANCH:-feat/macos-runtime}"
ANYPS5_TESTS="${ANYPS5_TESTS:-1}"
ANYPS5_JOBS="${ANYPS5_JOBS:-$(sysctl -n hw.ncpu)}"

if [[ -z "${ANYPS5_ROOT:-}" ]]; then
  if [[ -d /Volumes/Lexar4TB ]]; then ANYPS5_ROOT=/Volumes/Lexar4TB/anyps5; else ANYPS5_ROOT="$HOME/anyps5"; fi
fi
SRC="$ANYPS5_ROOT/AnyPS5"
BUILD="$ANYPS5_ROOT/build-macos"   # the branch's scripts expect ../build-macos next to the source tree
export ANYPS5_BUILD="$BUILD"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

check_prereqs() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only"
  [[ "$(uname -m)" == "arm64" ]] || log "not Apple silicon — Rosetta steps are no-ops"

  # Rosetta 2
  if [[ "$(uname -m)" == "arm64" ]] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    log "Installing Rosetta 2"
    softwareupdate --install-rosetta --agree-to-license
  fi

  xcode-select -p >/dev/null 2>&1 || die "Install Xcode Command Line Tools: xcode-select --install"

  for t in git cmake ninja python3; do
    command -v "$t" >/dev/null || die "missing $t (brew install $t)"
  done
  local cmv; cmv=$(cmake --version | awk 'NR==1{print $3}')
  [[ "$(printf '%s\n3.22.1\n' "$cmv" | sort -V | head -1)" == "3.22.1" ]] || die "CMake >= 3.22.1 required (have $cmv)"

  # Vulkan SDK / MoltenVK (LunarG SDK ships universal dylibs, fine for the x86_64 build)
  if [[ -z "${VULKAN_SDK:-}" ]]; then
    VULKAN_SDK=$(ls -d "$HOME"/VulkanSDK/*/macOS 2>/dev/null | sort -V | tail -1 || true)
  fi
  [[ -n "${VULKAN_SDK:-}" && -f "$VULKAN_SDK/lib/libvulkan.1.dylib" ]] \
    || die "Vulkan SDK not found. Install from https://vulkan.lunarg.com/sdk/home#mac (default path ~/VulkanSDK/<ver>/macOS) or set VULKAN_SDK"
  export VULKAN_SDK
  export DYLD_LIBRARY_PATH="$VULKAN_SDK/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  export VK_ICD_FILENAMES="$VULKAN_SDK/share/vulkan/icd.d/MoltenVK_icd.json"
  log "Vulkan SDK: $VULKAN_SDK"

  # disk headroom — a Release x86_64 build + FFmpeg + submodules is a multi-GB tree
  local free_gb; free_gb=$(df -g "$ANYPS5_ROOT" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
  [[ "${free_gb:-0}" -ge 20 ]] || log "warning: <20 GiB free at $ANYPS5_ROOT"
}

clone_or_update() {
  mkdir -p "$ANYPS5_ROOT"
  if [[ ! -d "$SRC/.git" ]]; then
    log "Cloning $ANYPS5_REMOTE ($ANYPS5_BRANCH) → $SRC"
    git clone --branch "$ANYPS5_BRANCH" "$ANYPS5_REMOTE" "$SRC"
  else
    log "Updating $SRC"
    git -C "$SRC" fetch origin "$ANYPS5_BRANCH"
    git -C "$SRC" checkout "$ANYPS5_BRANCH"
    git -C "$SRC" pull --ff-only origin "$ANYPS5_BRANCH"
  fi
  git -C "$SRC" remote get-url upstream >/dev/null 2>&1 || git -C "$SRC" remote add upstream https://github.com/boykopovar/AnyPS5.git
  log "Submodules"
  git -C "$SRC" submodule update --init --recursive --jobs 8
  log "HEAD: $(git -C "$SRC" log -1 --format='%h %s')"
}

configure_and_build() {
  log "Configure (x86_64, Release, tests on)"
  cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DBUILD_TESTING=ON \
    ${CCACHE:+-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache}
  log "Build (-k 0 keeps going past failures, as the branch doc recommends)"
  local build_rc=0
  cmake --build "$BUILD" --parallel "$ANYPS5_JOBS" -- -k 0 || build_rc=$?
  if (( build_rc != 0 )); then
    log "main build reported failures (on this branch the known ones are test-only targets: GuestRaiseException, GuestDup, dma-buf tests); continuing to libs"
  fi
  [[ -x "$BUILD/core/relinker/relinker" ]] || die "relinker did not build — real failure, see the output above"
  log "Build libs target"
  cmake --build "$BUILD" --target libs --parallel "$ANYPS5_JOBS" -- -k 0 || log "libs target reported failures — check above"

  local relinker; relinker=$(find "$BUILD" -maxdepth 3 -name relinker -type f -perm -u+x 2>/dev/null | head -1 || true)
  if [[ -n "$relinker" ]]; then
    log "relinker present: $relinker"
    if file "$relinker" | grep -q x86_64; then log "relinker is x86_64 (Rosetta)"; else log "warning: relinker is not x86_64"; fi
  else
    log "warning: relinker binary not found under $BUILD"
  fi
}

run_tests() {
  [[ "$ANYPS5_TESTS" == "1" ]] || return 0
  log "ctest (AGC + guest suites; flip/display/lds_atomics64 excluded as the macOS contributors do)"
  ( cd "$BUILD" && ctest -j1 --timeout 60 --output-on-failure \
      -R '^(agc|guest)' -E '(flip|display|lds_atomics64)' ) \
    | tee "$ANYPS5_ROOT/ctest-$(date +%Y%m%d-%H%M).log" || log "some tests failed — expected on this branch (~12 AGC failures reported by others)"
}

cmd_build()  { check_prereqs; clone_or_update; configure_and_build; run_tests; log "Done. Next: $0 setup <dump_dir> <game_dir>"; }
cmd_update() { check_prereqs; clone_or_update; configure_and_build; run_tests; }

cmd_setup() {
  [[ $# -ge 2 ]] || die "usage: $0 setup <dump_dir> <game_dir> [module_dir ...]"
  check_prereqs
  local dump="$1" game="$2"; shift 2
  [[ -f "$dump/eboot.bin" ]] || die "no eboot.bin in $dump (needs a decrypted dump)"
  log "setup-game.sh → $game  (modules: ${*:-sce_module only})"
  ( cd "$SRC" && tools/macos/setup-game.sh "$dump" "$game" "$@" )
  [[ -f "$game/eboot" ]] && chmod +x "$game/eboot"   # the relinker writes it without the execute bit
  log "Title ready. Run: $0 run $game [--profile]"
}

cmd_run() {
  [[ $# -ge 1 ]] || die "usage: $0 run <game_dir> [--profile]"
  check_prereqs
  local game="$1"; shift || true
  local script=run.sh; [[ "${1:-}" == "--profile" ]] && script=run-profile.sh
  [[ -x "$game/$script" ]] || die "$game/$script missing — run setup first"
  log "Launching $script in $game (APS5_ASYNC_PIPELINES=${APS5_ASYNC_PIPELINES:-1})"
  ( cd "$game" && "./$script" )
}

cmd_summary() {
  [[ $# -ge 1 ]] || die "usage: $0 summary <profile.log> [--windows]"
  python3 -I "$SRC/tools/macos/profile_summary.py" "$@"
}

case "${1:-}" in
  build)   shift; cmd_build "$@" ;;
  update)  shift; cmd_update "$@" ;;
  setup)   shift; cmd_setup "$@" ;;
  run)     shift; cmd_run "$@" ;;
  summary) shift; cmd_summary "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
