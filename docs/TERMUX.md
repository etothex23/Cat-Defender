# Playing Meowtron on Android (Termux)

Tested by the author on a Galaxy Z Fold8 ("Vali"): looks good. Also run on a Galaxy Z Flip7 ("Modi"), whose landscape terminal is about 113x19, which is why the minimum height is 18 rows. Built and benchmarked on a Mac. The game fits the terminal it finds:
`screen = auto` in settings.conf uses up to 120x30 and shrinks down to **40x18**. Smaller screens get a
compact HUD, a shorter radar and a narrower view, and run 2-3x faster (Bash is the bottleneck).

## Install
1. Install Termux (F-Droid build recommended). Then, in Termux:
   `pkg update && pkg install bash git`   (Termux's bash is already 5.x)
2. Get the folder onto the phone: `git clone` it, or copy it over (Syncthing, `termux-setup-storage` + a file copy, scp).
3. `cd Cat-Defender && ./bin/meowtron`

## Size
- Portrait is roughly 45-55 columns, which works (compact mode). Landscape has more columns but few rows; pinch to zoom out.
- Run `tools/termcheck.sh` to see what you have. The game says so and exits if it is under 40x18.
- Rotating or showing the keyboard changes the size: restart the game after you do.
- Force a size with `screen = 60x24` in settings.conf.

## Controls
- Termux's extra-keys row has the arrows. WASD works too. Space = throw, X = spazz, M = sound, Q = quit.
- A Bluetooth keyboard is far nicer. The cat's acceleration likes key-repeat; if holding a key on the touch keyboard
  does not repeat, tap faster.
- Colour: Termux supports 256 colours, so nothing is lost.
- Sound: `afplay` is macOS only. On Termux only the big moments ring the terminal bell (which may vibrate). `sound = off` mutes it.

## If it is too slow
`AUTO=1 bash src/game.sh --bench 300` prints ms/frame (budget 50). Over budget? Use a smaller `screen = 40x18`,
`radar = off`, and the easy preset (fewer enemies).

## Sound on Android
The sounds are the WAV files in `sounds/`. The game plays them with the first of these it finds:
`afplay` (macOS), `paplay`/`aplay` (Linux), `play-audio` (Termux), `termux-media-player` (Termux:API), `mpv`, `ffplay`.
In Termux install one: `pkg install play-audio`. Then raise the phone's **media** volume. If none is found you only get the terminal bell on big moments.
`sound = off` in settings.conf (or the M key) mutes everything. `python3 tools/make_sounds.py` regenerates the files; alternates are in `sounds/alt/`.

## Dying, restarting and memory
- You die in a burst of sparks, the world freezes for about a second, then you reappear mid-screen, safe for 3 seconds, with nearby pigeons and rats cleared.
- At game over (no lives, or every kitten gone) press **R** to start over, or **Q** to quit. R starts a fresh process, which also frees all memory.
- Press **I** (or set `info = on`) to show frame time and memory in the HUD. On a Mac the game sits at about 10 MB and does not grow over thousands of frames.
