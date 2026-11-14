# Playing Meowtron on Android (Termux)

Untested on a real phone as of 2026-11-14 (built and tested on a Mac). The game now fits the terminal it finds:
`screen = auto` in settings.conf uses up to 120x30 and shrinks down to **40x20**. Smaller screens get a
compact HUD, a shorter radar and a narrower view, and run 2-3x faster (Bash is the bottleneck).

## Install
1. Install Termux (F-Droid build recommended). Then, in Termux:
   `pkg update && pkg install bash git`   (Termux's bash is already 5.x)
2. Get the folder onto the phone: `git clone` it, or copy it over (Syncthing, `termux-setup-storage` + a file copy, scp).
3. `cd Cat-Defender && ./bin/meowtron`

## Size
- Portrait is roughly 45-55 columns, which works (compact mode). Landscape has more columns but few rows; pinch to zoom out.
- Run `tools/termcheck.sh` to see what you have. The game says so and exits if it is under 40x20.
- Rotating or showing the keyboard changes the size: restart the game after you do.
- Force a size with `screen = 60x24` in settings.conf.

## Controls
- Termux's extra-keys row has the arrows. WASD works too. Space = throw, X = spazz, M = sound, Q = quit.
- A Bluetooth keyboard is far nicer. The cat's acceleration likes key-repeat; if holding a key on the touch keyboard
  does not repeat, tap faster.
- Colour: Termux supports 256 colours, so nothing is lost.
- Sound: `afplay` is macOS only. On Termux only the big moments ring the terminal bell (which may vibrate). `sound = off` mutes it.

## If it is too slow
`AUTO=1 bash src/game.sh --bench 300` prints ms/frame (budget 50). Over budget? Use a smaller `screen = 40x20`,
`radar = off`, and the easy preset (fewer enemies).
