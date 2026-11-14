# Cat-Defender environment notes

## Requirements
- Bash 4+ (developed on 5.3). macOS ships 3.2, which is too old.
- UTF-8 terminal with 256-colour (or truecolor) ANSI. Ideal 120x30; it shrinks to fit down to 40x18 (`screen` in settings.conf). Phones: see TERMUX.md.
- Rendering uses half-block characters (▀ ▄ █) as colour "pixels".

## Changes made to this machine (2026-11-13)
| Change | Command | How to undo |
|---|---|---|
| Installed GNU Bash 5.3.20 (Homebrew) at /opt/homebrew/bin/bash | `brew install bash` | `brew uninstall bash` |
| Upgraded dependency libunistring 1.4.2 -> 1.5 (done automatically by brew) | (part of the above) | `brew uninstall bash` leaves libunistring in place; it is harmless and other formulae may use it |

Notes:
- The system /bin/bash (3.2.57) is untouched. Nothing was set as the login shell.
- Scripts must use `#!/usr/bin/env bash` and rely on /opt/homebrew/bin being on PATH,
  or be started through `bin/cat-defender`, which finds a suitable bash itself.
- If Homebrew upgrades bash later and something breaks, run `brew reinstall bash`.
