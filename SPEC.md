# CC Video Wall - Project Spec & Progress Notes

Everything needed to pick this project back up later or on a new machine.

## What this is
A computer + monitor wall in CC:Tweaked that plays full videos on a monitor
wall with sound through a speaker. Videos are pre-converted offline into
CC-native data (per-frame text + DFPWM1a audio) and hosted on GitHub.

## Hosting
- Repo: https://github.com/Nick5amg5/cc-rick  (branch: main)
- Raw base (used by install.lua / wget):
  https://raw.githubusercontent.com/Nick5amg5/cc-rick/HEAD/
- Auth: `.ghtoken` in `C:\Users\denni\Downloads\rick-cc` (repo-scope token,
  user Nick5amg5). Never commit it.

## Local pipeline (all in `C:\Users\denni\Downloads\rick-cc`)
- `bundle_rick.py` - core converter + the player source (PLAY_LUA_TEMPLATE).
  - `python bundle_rick.py <video> --name <track> --fps 20 --monitor 8x5`
  - `--monitor NxM` sets the wall size in blocks; cells = monitor_cells(N,M),
    8x5 -> 164x67 (w=round((64*8-20)/(6*0.5)), h=round((64*5-20)/(9*0.5))).
  - `--player-only` regenerates out/rick.lua from the template.
  - Per-frame 16-colour adaptive palette ("pal"), textScale 0.5.
- `bundle_yt.py` - same but takes a YouTube URL (uses yt-dlp).
- `bundle_logo.py <img>` - builds out/logo.data (idle logo) from an image.
- `out/` holds every built file.

## The player (rick.lua - one generic file serves every track)
- `rick` -> picker if several .data files, else plays the only one.
- `rick <name>` plays `<name>.data` + `<name>.dfpwm`.
- `rick list` prints installed tracks (name, res, pal, size, duration, disk used).
- Plays a track once, then shows the logo and exits. `L` toggles continuous loop.
- Keys: P pause, Q quit, [ / ] volume, , / . A/V sync lead (saved to rick.sync),
  L loop. Also R = no; monitor shows logo when idle (picker / loading / stopped).
- A/V sync: audio feeds 2048-byte dfpwm chunks (~0.34 s); a `syncLead` delay on
  the video clock keeps audio ahead of video by a tunable amount (default 0.2 s).
- Monitor geometry is parsed from the .data header at runtime (W H FPS PAL).

## Data format (NFP)
```
W H FPS 1       <- header; PAL=1 means each frame carries a custom palette
RRR GGG 4 per line x4  <- 16 palette entries (hex)
<H rows of W hex tokens>  <- one row per monitor line
<blank line>    <- frame separator
```
Byte cost at 164x67: 112 + 67*(164+1) + 1 = 11168 B/frame -> 64 MB cap allows
up to ~6009 frames (~5 min at 20 fps, ~5:54 at 17 fps).

## Tracks in the repo (as of last work)
| name            | source                    | res (cells) | fps | approx size |
|-----------------|---------------------------|-------------|-----|-------------|
| rick            | Never Gonna Give You Up   | 164x67      | 20  | 47.6 MB     |
| osama           | -                         | 164x67      | 20  | 63.6 MB     |
| ganstaparadise  | -                         | 164x67      | 20  | 59.5 MB     |
| amishparadise   | -                         | 164x67      | 20  | 45.8 MB     |
| verity          | -                         | 164x67      | 20  | 27.4 MB     |
| jet2ad          | 30 s ad (YQZEoZ4W0ac)     | 164x67      | 20  | 6.5 MB      |
| clullaby        | 4:3 video (ySnO1e1y0RE)   | 136x67      | 20  | 31.7 MB     |
| beemoviespeed   | JMG1Nl7uWko               | 163x61      | 17  | 57.8 MB     |
Plus: install.lua, deletev.lua, tracks.txt, logo.data (from atmlogocinema.png),
rick.lua, and the music2ndmodule/ folder.

## Hard limits (CC:Tweaked), why the sizes above are what they are
- 67108864 B  (64 MiB) max single file a computer can http-download.
  -> beemoviespeed at 20 fps was 75.9 MB, had to drop to 17 fps.
- 268435456 B (256 MB) computer disk -> only ~4-5 of the 8 tracks fit at once.
  deletev <name> frees space; repo keeps everything so reinstall is trivial.

## Repo helper scripts (in game, installed to the computer root)
- install.lua : BASE is pre-set. `install` / `install <tracks...>` / `-f` force.
  Always fetches rick.lua + logo.data + requested tracks.
- deletev.lua : `deletev <name>` or `deletev -a` (keeps rick.lua/install/deletev
  and the idle logo.data).

## New computer setup (video wall)
```
wget https://raw.githubusercontent.com/Nick5amg5/cc-rick/HEAD/install.lua install
install -f rick osama ganstaparadise amishparadise verity jet2ad clullaby beemoviespeed
rick                (or:  rick <name>,  rick list)
```
Requires: http enabled on the server; monitor (Advanced, for colour) next to the
computer; speaker nearby.

## Uploading / how builds get to GitHub
- Small files (<~45 MB): `python upload_gh.py cc-rick <path>...`
  (GitHub Contents API - FAILS above ~46 MB with "file too large").
- Large files: MUST use git push (Contents API limit). Local clone is kept at
  `%LOCALAPPDATA%\Temp\opencode\cc-rick-clone`. Pattern:
```
$t=(Get-Content -LiteralPath '.ghtoken' -Raw).Trim();
$hdr='Authorization: Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('Nick5amg5:'+$t));
Copy-Item out\<file> <clone> -Force
git -C <clone> add -A
git -C <clone> -c user.name=Nick5amg5 -c user.email=Nick5amg5@users.noreply.github.com commit -m "..."
git -c http.extraheader=$hdr -C <clone> push -q origin main
```
- Verify each file: HEAD the raw URL and compare Content-Length to the local one.

## Music module (separate project, same repo)
- Folder: music2ndmodule/  (repo + local). ~/rick-cc/music2ndmodule/music.lua
- Offline music player for a plain computer + speaker (no monitor needed):
  local library music/*.dfpwm, playlists in music/playlists/*.txt, terminal GUI.
- Commands: `music` (GUI), `music add <url> <name>` (save a song), `music play <name>`.
- A monitor + touchscreen mode was discussed but NOT built yet (next step if wanted).

## Friction / gotchas learned
- `fs.find` returns a list, not an iterator: use `for _, f in ipairs(fs.find(...))`.
- Closing a file twice errors: always guard tail closes with `if h then h:close() end`.
- Monitor "touchscreen": only Advanced monitors, and only via the `monitor_touch`
  event when a player right-clicks them. Not yet used by the player.
- The CC speaker buffers only ONE playAudio call; feed small chunks for tight
  sync (2 KB dfpwm = ~0.34 s) or the audio lags video by the chunk length.
- Bundling lowers fps to fit the 64 MiB/file cap on long videos.

## Next steps (when resuming)
1. Touch-screen track selector over the logo (buttons drawn at idle; monitor_touch).
2. Any new track: convert, check size <= 67108864 B, git-push, update tracks.txt.
3. If the wall grows (more blocks), re-derive cells with monitor_cells and re-render.