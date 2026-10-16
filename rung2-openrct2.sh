#!/usr/bin/env bash
# rung2-openrct2.sh — Rung 2: ps5-openrct2 (PPSA99728) through AnyPS5 on the Mac.
#
# Steps:
#   fetch                 download PPSA99728.zip from lowbit/ps5-openrct2 releases, verify sha256, unpack
#   setup                 relink with anyps5-mac.sh (uses the same unself.py patch as rung 1)
#   game <gog-exe|dir|zip> put your own RollerCoaster Tycoon 2 files at app0/rct2 so the import screen is skipped
#   run [--profile]       launch
#   all <gog-source>      fetch → setup → game → run
#
# The title reads /app0/rct2 (Data, ObjData, Scenarios, Tracks, Landscapes) and only shows its
# browser-upload import screen when that folder is missing. Under AnyPS5 app0/ is a local directory,
# so the GOG installer is unpacked straight into it with innoextract (brew install innoextract).
#
# Env: ANYPS5_ROOT (as rung 1), RCT_VERSION (default v1.0.0)

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC="$HERE/anyps5-mac.sh"; [[ -x "$MAC" ]] || { echo "anyps5-mac.sh not found beside this script" >&2; exit 1; }

if [[ -z "${ANYPS5_ROOT:-}" ]]; then
  if [[ -d /Volumes/Lexar4TB ]]; then ANYPS5_ROOT=/Volumes/Lexar4TB/anyps5; else ANYPS5_ROOT="$HOME/anyps5"; fi
fi
RCT_VERSION="${RCT_VERSION:-v1.0.0}"
WORK="$ANYPS5_ROOT/rung2-openrct2"
DUMP="$WORK/dump/PPSA99728"
GAME="$WORK/game"
ANYPS5_SRC="$ANYPS5_ROOT/AnyPS5"
REL="https://github.com/lowbit/ps5-openrct2/releases/download/$RCT_VERSION"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cmd_fetch() {
  mkdir -p "$WORK/dump"
  log "Downloading PPSA99728.zip ($RCT_VERSION, ~78 MB)"
  curl -fL --retry 3 -o "$WORK/PPSA99728.zip" "$REL/PPSA99728.zip"
  curl -fL --retry 3 -o "$WORK/PPSA99728.zip.sha256" "$REL/PPSA99728.zip.sha256"
  ( cd "$WORK" && shasum -a 256 -c PPSA99728.zip.sha256 ) || die "sha256 mismatch — do not use this zip"
  rm -rf "$DUMP"
  ( cd "$WORK/dump" && unzip -q "$WORK/PPSA99728.zip" )
  [[ -f "$DUMP/eboot.bin" && -d "$DUMP/data" && -f "$DUMP/sce_module/libc.prx" ]] || die "unexpected zip layout under $WORK/dump"
  log "Dump ready: $DUMP ($(du -sh "$DUMP" | cut -f1))"
}

patch_unself() {
  local up="$ANYPS5_SRC/tools/macos/unself.py"
  [[ -f "$up" ]] || die "no $up — run anyps5-mac.sh build first"
  local probe; probe=$(python3 -I "$up" "$DUMP/sce_module/libc.prx" "$WORK/.unself-probe.elf" 2>&1 || true)
  if [[ "$probe" == FAIL* ]]; then
    log "branch unself.py rejects libc.prx; installing patched copy"
    cp "$up" "$up.orig" 2>/dev/null || true
    cp "$HERE/tools/unself.py" "$up"
  fi
  rm -f "$WORK/.unself-probe.elf"
}

cmd_setup() {
  [[ -f "$DUMP/eboot.bin" ]] || cmd_fetch
  patch_unself
  "$MAC" setup "$DUMP" "$GAME"
  log "Title directory: $GAME"
  [[ -d "$GAME/app0/rct2" ]] && log "game files present at app0/rct2" || log "no game files yet: $0 game <gog-installer.exe | rct2-folder | rct2.zip>"
}

cmd_game() {
  [[ $# -ge 1 ]] || die "usage: $0 game <setup_rollercoaster_tycoon_2_*.exe | RCT2 folder | zip>"
  [[ -d "$GAME/app0" ]] || cmd_setup
  local src="$1" dst="$GAME/app0/rct2"
  rm -rf "$dst.partial"; mkdir -p "$dst.partial"
  if [[ -d "$src" ]]; then
    log "Copying game folder"
    for d in Data ObjData Scenarios Tracks Landscapes; do [[ -d "$src/$d" ]] && cp -R "$src/$d" "$dst.partial/"; done
  elif [[ "$src" == *.zip ]]; then
    log "Unzipping game folder"
    ( cd "$dst.partial" && unzip -q "$src" )
    # tolerate a single top-level folder inside the zip
    if [[ ! -d "$dst.partial/Data" ]]; then local inner; inner=$(find "$dst.partial" -maxdepth 2 -type d -name Data | head -1); [[ -n "$inner" ]] && { mv "$(dirname "$inner")"/* "$dst.partial/"; rmdir "$(dirname "$inner")" 2>/dev/null || true; }; fi
  elif [[ "$src" == *.exe ]]; then
    command -v innoextract >/dev/null || die "innoextract needed for the GOG installer: brew install innoextract"
    [[ -f "${src%.exe}-1.bin" || -n "$(ls "$(dirname "$src")"/*.bin 2>/dev/null)" ]] || log "warning: no .bin beside the installer; GOG's offline installer needs both"
    log "Extracting GOG installer with innoextract (a minute or two)"
    innoextract -q -d "$dst.partial" "$src"
    # innoextract puts game files under app/ (and sometimes app/<lang>/); pull Data etc. up
    local root; root=$(find "$dst.partial" -maxdepth 3 -type d -iname Data | head -1)
    [[ -n "$root" ]] || die "no Data folder found in the extracted installer"
    root=$(dirname "$root")
    for d in Data ObjData Scenarios Tracks Landscapes; do
      local hit; hit=$(find "$root" -maxdepth 1 -type d -iname "$d" | head -1)
      [[ -n "$hit" ]] && mv "$hit" "$dst.partial/$d.keep"
    done
    find "$dst.partial" -mindepth 1 -maxdepth 1 ! -name '*.keep' -exec rm -rf {} +
    for k in "$dst.partial"/*.keep; do mv "$k" "${k%.keep}"; done
  else
    die "unrecognised source: $src"
  fi
  for d in Data ObjData Scenarios; do [[ -d "$dst.partial/$d" ]] || die "missing $d in the game files (got: $(ls "$dst.partial" | tr '\n' ' '))"; done
  rm -rf "$dst"; mv "$dst.partial" "$dst"
  log "Game files installed: $(du -sh "$dst" | cut -f1) at app0/rct2 ($(ls "$dst" | tr '\n' ' '))"
}

cmd_run() {
  [[ -x "$GAME/run.sh" ]] || cmd_setup
  [[ -d "$GAME/app0/rct2/Data" ]] || log "no game files at app0/rct2 — the title will show its import screen (address + QR) instead of the game"
  if [[ "${1:-}" == "--profile" ]]; then "$MAC" run "$GAME" --profile; else "$MAC" run "$GAME"; fi
  log "log: $GAME/app0/openrct2.log"
}

cmd_all() { [[ $# -ge 1 ]] || die "usage: $0 all <gog-source>"; cmd_fetch; cmd_setup; cmd_game "$1"; cmd_run; }

case "${1:-}" in
  fetch) cmd_fetch ;;
  setup) cmd_setup ;;
  game)  shift; cmd_game "$@" ;;
  run)   shift; cmd_run "$@" ;;
  all)   shift; cmd_all "$@" ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
