#!/usr/bin/env bash
# test/selftest.sh — exercise anyps5-mac.sh and rung1-doom.sh without a Mac, a GPU or the network.
# Shims uname/sysctl/xcode-select/cmake/ninja/ctest/git/curl/shasum/unzip/docker/file and the
# branch's tools/macos scripts, then walks every subcommand and asserts the calls each one makes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export ANYPS5_ROOT="$T/anyps5" ANYPS5_TESTS=0 ANYPS5_JOBS=2
export PATH="$T/bin:$PATH"; mkdir -p "$T/bin"
LOG="$T/calls.log"; : >"$LOG"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
called() { grep -q -- "$1" "$LOG" && ok "called: $1" || bad "expected call: $1"; }

# --- shims: every external command logs its argv and fakes the minimum result -----------------
shim() { local n="$1"; shift; printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\n%s\n' "$n" "$LOG" "$*" >"$T/bin/$n"; chmod +x "$T/bin/$n"; }
shim uname      'case "${1:-}" in -s) echo Darwin;; -m) echo arm64;; *) echo Darwin;; esac'
shim sysctl     'echo 8'
shim arch       'exit 0'
shim xcode-select 'echo /Library/Developer/CommandLineTools'
shim cmake      'case "$1" in --version) echo "cmake version 3.30.0";; -S) mkdir -p "$5" 2>/dev/null; shift; for a; do case $a in -B) b=1;; *) [[ ${b:-} == 1 ]] && { mkdir -p "$a/core/relinker"; printf "#!/bin/sh\n" > "$a/core/relinker/relinker"; chmod +x "$a/core/relinker/relinker"; b=0; };; esac; done;; esac; exit 0'
shim ninja      'exit 0'
shim ctest      'exit 0'
shim file       'echo "Mach-O 64-bit executable x86_64"'
shim df         'printf "Filesystem 1G-blocks Used Available Capacity Mounted on\nfake 1000 100 900 10%% /\n"'
shim docker     'exit 0'
shim curl       'out=""; while (($#)); do [[ $1 == -o ]] && out=$2; shift; done; [[ -n $out ]] && { [[ $out == *.sha256 ]] && echo "0000  PPSA99666.zip" > "$out" || : > "$out"; }; exit 0'
shim shasum     'exit 0'
shim unzip      'mkdir -p PPSA99666/sce_sys PPSA99666/wads; : > PPSA99666/eboot.bin; echo "{}" > PPSA99666/sce_sys/param.json; : > PPSA99666/wads/doom1.wad'
shim du         'echo "1M	x"'
# git shim: clone creates a fake checkout with the branch's tools/macos scripts; everything else succeeds
cat >"$T/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$CALLS"
if [[ "$1" == clone ]]; then dest="${@: -1}"; mkdir -p "$dest/.git" "$dest/tools/macos" "$dest/docker"
  printf '#!/usr/bin/env bash\necho "setup-game.sh $*" >>"%s"\nmkdir -p "$2"; printf "#!/bin/sh\\n" | tee "$2/run.sh" "$2/run-profile.sh" >/dev/null; chmod +x "$2"/run*.sh\n' "$CALLS" >"$dest/tools/macos/setup-game.sh"
  chmod +x "$dest/tools/macos/setup-game.sh"; echo "print('summary ok')" >"$dest/tools/macos/profile_summary.py"; fi
[[ "$1" == log ]] && echo "abc1234 fake head"
[[ "$1" == -C && "$3" == log ]] && echo "abc1234 fake head"
exit 0
EOF
chmod +x "$T/bin/git"; export CALLS="$LOG"
# fake Vulkan SDK
mkdir -p "$HOME/VulkanSDK/1.4.0/macOS/lib" "$HOME/VulkanSDK/1.4.0/macOS/share/vulkan/icd.d"
: >"$HOME/VulkanSDK/1.4.0/macOS/lib/libvulkan.1.dylib"

MAC="$ROOT/anyps5-mac.sh"; RUNG="$ROOT/rung1-doom.sh"
echo "== anyps5-mac.sh"
"$MAC" >/dev/null 2>&1 && bad "no-arg should exit 1" || ok "no-arg prints usage and exits 1"
"$MAC" build >"$T/build.out" 2>&1 && ok "build completes" || { bad "build failed"; cat "$T/build.out"; }
called "git clone --branch feat/macos-runtime https://github.com/yripper/AnyPS5.git"
called "git -C $ANYPS5_ROOT/AnyPS5 submodule update --init --recursive"
called "cmake -S $ANYPS5_ROOT/AnyPS5 -B $ANYPS5_ROOT/build-macos -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DBUILD_TESTING=ON"
called "cmake --build $ANYPS5_ROOT/build-macos --target libs"
grep -q "relinker is x86_64" "$T/build.out" && ok "relinker arch check reported" || bad "relinker arch check missing"
grep -q "ctest" "$LOG" && bad "ctest ran with ANYPS5_TESTS=0" || ok "ctest skipped with ANYPS5_TESTS=0"
"$MAC" setup "$T/nodump" "$T/g" >/dev/null 2>&1 && bad "setup without eboot.bin should fail" || ok "setup refuses a dir without eboot.bin"
mkdir -p "$T/dump"; : >"$T/dump/eboot.bin"
"$MAC" setup "$T/dump" "$T/game" Media/Modules >/dev/null 2>&1 && ok "setup runs" || bad "setup failed"
called "setup-game.sh $T/dump $T/game Media/Modules"
[[ -x "$T/game/run.sh" ]] && ok "run.sh produced" || bad "run.sh missing"
"$MAC" run "$T/game" >/dev/null 2>&1 && ok "run launches run.sh" || bad "run failed"
"$MAC" run "$T/game" --profile >/dev/null 2>&1 && ok "run --profile launches run-profile.sh" || bad "run --profile failed"
"$MAC" summary /dev/null 2>&1 | grep -q "summary ok" && ok "summary calls profile_summary.py with -I" || bad "summary failed"
# prereq failure paths
PATH="$T/bin2:$PATH" ; mkdir -p "$T/bin2"; cp "$T/bin/uname" "$T/bin2/uname"; sed -i 's/Darwin/Linux/g' "$T/bin2/uname"
"$MAC" build >/dev/null 2>&1 && bad "non-Darwin should die" || ok "dies on non-Darwin host"
rm -rf "$T/bin2"; PATH="${PATH#"$T/bin2:"}"
VULKAN_SDK="$T/nosdk" "$MAC" build >/dev/null 2>&1 && bad "missing Vulkan SDK should die" || ok "dies without Vulkan SDK"

echo "== rung1-doom.sh"
: >"$LOG"
"$RUNG" >/dev/null 2>&1 && bad "no-arg should exit 1" || ok "no-arg prints usage and exits 1"
"$RUNG" fetch >"$T/fetch.out" 2>&1 && ok "fetch completes" || { bad "fetch failed"; cat "$T/fetch.out"; }
called "curl -fL --retry 3 -o $ANYPS5_ROOT/rung1-doom/PPSA99666.zip https://github.com/lowbit/ps5-doom/releases/download/v1.0.1/PPSA99666.zip"
called "shasum -a 256 -c PPSA99666.zip.sha256"
[[ -f "$ANYPS5_ROOT/rung1-doom/dump/PPSA99666/eboot.bin" ]] && ok "dump unpacked at expected path" || bad "dump path wrong"
"$RUNG" setup >/dev/null 2>&1 && ok "setup relinks via anyps5-mac.sh" || bad "setup failed"
called "setup-game.sh $ANYPS5_ROOT/rung1-doom/dump/PPSA99666 $ANYPS5_ROOT/rung1-doom/game"
"$RUNG" oracle >"$T/oracle.out" 2>&1 && ok "oracle completes" || { bad "oracle failed"; cat "$T/oracle.out"; }
called "git clone --branch v1.0.1 --depth 1 https://github.com/lowbit/ps5-doom.git"
called "docker build -t ps5-doom-build"
called "docker run --rm --platform linux/amd64"
grep -q "DOOM_IWAD=doom1.wad" "$LOG" && ok "oracle renders doom1.wad timedemo" || bad "oracle env missing"
"$RUNG" run >/dev/null 2>&1 && ok "run launches title" || bad "run failed"
"$RUNG" run --profile >/dev/null 2>&1 && ok "run --profile launches profile script" || bad "run --profile failed"
shim docker 'exit 0'; rm "$T/bin/docker"
"$RUNG" oracle >/dev/null 2>&1 && bad "oracle without docker should die" || ok "oracle dies without docker"

echo; echo "passed $pass, failed $fail"; [[ $fail -eq 0 ]]
