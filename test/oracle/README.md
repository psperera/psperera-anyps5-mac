# Reference frames

Rendered 2026-10-15 by ps5-doom v1.0.1's headless host backend (`make host`, clang 18, Linux x86-64),
shareware `doom1.wad` from `PPSA99666.zip`, attract demo, no input:

    DOOM_IWAD=doom1.wad DOOM_CAPTURE=120,900 DOOM_FRAMES=1000 build/host/bin/doom

Frame 120 is the title screen; frame 900 is the demo mid-E1M1 ("picked up 4 shotgun shells").
Two independent runs produced byte-identical `.raw` output, so these are a deterministic baseline
for `rung1-doom.sh diff` before you have rendered your own with `rung1-doom.sh oracle`.
`SHA256SUMS` covers the raw palette-index frames and the PNGs.
