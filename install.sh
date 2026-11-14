#!/bin/sh
# Meowtron installer: checks for Bash 4+, copies the game, links a launcher.
set -e
SRC=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$HOME/.local}
APP="$PREFIX/share/cat-defender"

have_bash4() {
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash)"; do
    [ -x "$b" ] && "$b" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null && return 0
  done
  return 1
}

if ! have_bash4; then
  echo "Bash 4+ not found."
  if command -v brew >/dev/null 2>&1; then
    printf "Run 'brew install bash' now? [y/N] "; read -r a
    [ "$a" = y ] && brew install bash || { echo "Cannot continue without Bash 4+."; exit 1; }
  else
    echo "Install Bash 4+ and re-run."; exit 1
  fi
fi

mkdir -p "$APP" "$PREFIX/bin"
cp -R "$SRC/bin" "$SRC/src" "$SRC/sprites" "$APP/"
[ -e "$APP/settings.conf" ] || cp "$SRC/settings.conf" "$APP/settings.conf"   # keep your edits on re-install
ln -sf "$APP/bin/cat-defender" "$PREFIX/bin/cat-defender"
ln -sf "$APP/bin/cat-defender" "$PREFIX/bin/meowtron"
echo "Installed to $APP"
echo "Launcher: $PREFIX/bin/meowtron (also cat-defender)  (make sure $PREFIX/bin is on your PATH)"
