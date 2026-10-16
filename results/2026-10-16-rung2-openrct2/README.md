# Rung 2 — ps5-openrct2 on Mac Studio M1 Ultra — import screen reached (no game files yet)

2026-10-16 03:35. Same host and branch as rung 1. ps5-openrct2 v1.0.0 (PPSA99728), 78 MB zip, sha256 OK.

| Step | Result |
|---|---|
| Relink | `libc.prx` carries the same second magic; patched `unself.py` handled it. **298 external prx references** (DOOM: 164), 23 MB Mach-O `eboot`. The relinker leaves `eboot` without the execute bit — `run.sh` fails with "Permission denied" until `chmod +x` (fixed in `anyps5-mac.sh setup`). |
| Run | Title starts, finds no `/app0/rct2`, enters the import screen. `openrct2.log`: `upload: serving http://10.0.0.7:9666/ into /app0/rct2` — AnyPS5's offline socket stack returned the Mac's real LAN address and bound the HTTP server. |
| Upload page | `curl http://127.0.0.1:9666/` → HTTP 200, 9.2 KB, `<title>Send RollerCoaster Tycoon 2 to OpenRCT2` (`upload-page.html`). |

So the SDL software renderer, libc++/ICU surface, Cocoa window and network stack all come up for a C++20 title. Next: `./rung2-openrct2.sh game <GOG installer>` (innoextract into `app0/rct2`, skipping the upload page), then `run` to reach the actual game.
