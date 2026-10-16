#!/usr/bin/env bash
# rung1-doom.sh — Rung 1: ps5-doom (PPSA99666) through AnyPS5 on the Mac, with the host backend as diff oracle.
#
# Steps:
#   fetch     download PPSA99666.zip from lowbit/ps5-doom releases, verify sha256, unpack as a "dump"
#   setup     relink it with anyps5-mac.sh (tools/macos/setup-game.sh)
#   oracle    build ps5-doom's headless host backend in Docker and render reference frames of demo1
#   run       launch DOOM through AnyPS5 (optionally with the profile log)
#   capture   pull frames from the running title over its test port (9119) and de-tile to PNG
#   diff      compare captured frames to the oracle frames
#   all       fetch → setup → oracle → run
#
# Env:
#   ANYPS5_ROOT      same as anyps5-mac.sh (default /Volumes/Lexar4TB/anyps5 or ~/anyps5)
#   DOOM_VERSION     release tag (default v1.0.1)
#   DOOM_CAPTURE     oracle frame numbers (default 120,900 — the repo's own choice)
#   DOOM_HOST        host:port of the running title's capture socket (default 127.0.0.1:9119)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC="$HERE/anyps5-mac.sh"; [[ -x "$MAC" ]] || { echo "anyps5-mac.sh not found beside this script" >&2; exit 1; }

if [[ -z "${ANYPS5_ROOT:-}" ]]; then
  if [[ -d /Volumes/Lexar4TB ]]; then ANYPS5_ROOT=/Volumes/Lexar4TB/anyps5; else ANYPS5_ROOT="$HOME/anyps5"; fi
fi
DOOM_VERSION="${DOOM_VERSION:-v1.0.1}"
DOOM_CAPTURE="${DOOM_CAPTURE:-120,900}"
DOOM_HOST="${DOOM_HOST:-127.0.0.1:9119}"

WORK="$ANYPS5_ROOT/rung1-doom"
DUMP="$WORK/dump/PPSA99666"      # the unpacked release folder = a homebrew "dump" (eboot.bin + sce_sys + wads)
GAME="$WORK/game"                # AnyPS5 title directory produced by setup-game.sh
SRC="$WORK/ps5-doom"             # source checkout, for the host oracle and console_test.py
ORACLE="$WORK/oracle"
CAPT="$WORK/captured"
REL="https://github.com/lowbit/ps5-doom/releases/download/$DOOM_VERSION"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cmd_fetch() {
  mkdir -p "$WORK/dump"
  log "Downloading PPSA99666.zip ($DOOM_VERSION)"
  curl -fL --retry 3 -o "$WORK/PPSA99666.zip" "$REL/PPSA99666.zip"
  curl -fL --retry 3 -o "$WORK/PPSA99666.zip.sha256" "$REL/PPSA99666.zip.sha256"
  log "Verifying sha256"
  ( cd "$WORK" && shasum -a 256 -c PPSA99666.zip.sha256 ) || die "sha256 mismatch — do not use this zip"
  rm -rf "$DUMP"
  ( cd "$WORK/dump" && unzip -q "$WORK/PPSA99666.zip" )
  [[ -f "$DUMP/eboot.bin" && -f "$DUMP/sce_sys/param.json" ]] || die "unexpected zip layout under $WORK/dump"
  log "Dump ready: $DUMP ($(du -sh "$DUMP" | cut -f1)); shareware WAD: $(ls "$DUMP/wads" 2>/dev/null | tr '\n' ' ')"
}

cmd_setup() {
  [[ -f "$DUMP/eboot.bin" ]] || cmd_fetch
  log "Relinking through anyps5-mac.sh setup"
  "$MAC" setup "$DUMP" "$GAME"
  log "Title directory: $GAME"
  ls -la "$GAME" | sed 's/^/    /'
}

cmd_oracle() {
  command -v docker >/dev/null || die "Docker is required for the host oracle (Docker Desktop on the Mac)"
  if [[ ! -d "$SRC/.git" ]]; then
    log "Cloning lowbit/ps5-doom at $DOOM_VERSION"
    git clone --branch "$DOOM_VERSION" --depth 1 https://github.com/lowbit/ps5-doom.git "$SRC"
  fi
  log "Building ps5-doom-build image"
  docker build -t ps5-doom-build "$SRC/docker/"
  log "Building the headless host backend (linux/amd64 container; same game code, PNG frames out)"
  docker run --rm --platform linux/amd64 -v "$SRC:/src" -w /src ps5-doom-build make -j"$(sysctl -n hw.ncpu)" host
  mkdir -p "$ORACLE"
  log "Rendering reference frames $DOOM_CAPTURE of demo1 (timedemo)"
  docker run --rm --platform linux/amd64 -v "$SRC:/src" -v "$DUMP/wads:/wads:ro" -v "$ORACLE:/out" -w /src \
    -e DOOM_WADDIR=/wads -e DOOM_IWAD=doom1.wad -e DOOM_OUT=/out -e DOOM_CAPTURE="$DOOM_CAPTURE" -e DOOM_SAVEDIR=/tmp \
    ps5-doom-build build/host/bin/doom -timedemo demo1
  log "Oracle frames:"; ls -1 "$ORACLE" | sed 's/^/    /'
}

cmd_run() {
  [[ -x "$GAME/run.sh" ]] || cmd_setup
  local mode="${1:-}"
  if [[ "$mode" == "--profile" ]]; then "$MAC" run "$GAME" --profile; else "$MAC" run "$GAME"; fi
  log "If the screen stays black >500 ms the title switches to its CPU scaler on its own; check the log for 'present'"
  log "Hold L1+R1 (or the mapped keys in anyps5-input.ini) at start to force the CPU scaler and isolate the wave64 kernel"
}

cmd_capture() {
  # The title opens a TCP listener on 9119 and streams tiled frames to tools/console_test.py.
  # Under AnyPS5 this depends on the offline socket stack accepting a listen(); if it does not, fall back to
  # macOS screencapture at the oracle frame times (35 fps timedemo => frame/35 seconds after start).
  [[ -d "$SRC" ]] || die "run 'oracle' first (needs the ps5-doom checkout for console_test.py)"
  mkdir -p "$CAPT"
  log "Attempting frame pull from $DOOM_HOST (title must be running)"
  if ( cd "$SRC" && uv run --no-project python tools/console_test.py --host "$DOOM_HOST" --out "$CAPT" test/console-play.cfg ) 2>"$CAPT/console_test.err"; then
    log "Frames de-tiled into $CAPT"
  else
    log "console_test.py could not connect (see $CAPT/console_test.err) — falling back to screencapture"
    IFS=',' read -ra frames <<< "$DOOM_CAPTURE"
    local t0; t0=$(date +%s)
    for f in "${frames[@]}"; do
      local at=$(( f / 35 ))
      while (( $(date +%s) - t0 < at )); do sleep 0.2; done
      screencapture -x "$CAPT/frame_${f}_screen.png"
      log "captured screen at ~frame $f"
    done
  fi
}

cmd_diff() {
  command -v magick >/dev/null || command -v compare >/dev/null || die "ImageMagick needed: brew install imagemagick"
  local cmp; cmp=$(command -v magick >/dev/null && echo "magick compare" || echo compare)
  mkdir -p "$WORK/diff"
  for ref in "$ORACLE"/*.png; do
    local n; n=$(basename "$ref" .png)
    local cand; cand=$(ls "$CAPT"/*"${n#frame_}"*.png 2>/dev/null | head -1 || true)
    [[ -n "$cand" ]] || { log "no capture matching $n"; continue; }
    # RMSE over the frame; the oracle is 320x200 palette output, the Mac frame is the 1080p sharp-bilinear upscale,
    # so resize the capture down before comparing.
    magick "$cand" -resize 320x200! "$WORK/diff/${n}_cand.png" 2>/dev/null || convert "$cand" -resize 320x200! "$WORK/diff/${n}_cand.png"
    local rmse; rmse=$($cmp -metric RMSE "$ref" "$WORK/diff/${n}_cand.png" "$WORK/diff/${n}_delta.png" 2>&1 || true)
    printf '    %-12s RMSE %s\n' "$n" "$rmse"
  done
  log "Deltas in $WORK/diff — a palette/scaler bug shows as uniform colour shift; a recompiler bug as structured garbage"
}

cmd_all() { cmd_fetch; cmd_setup; cmd_oracle; cmd_run "${1:-}"; }

case "${1:-}" in
  fetch)   cmd_fetch ;;
  setup)   cmd_setup ;;
  oracle)  cmd_oracle ;;
  run)     shift; cmd_run "$@" ;;
  capture) cmd_capture ;;
  diff)    cmd_diff ;;
  all)     shift; cmd_all "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
