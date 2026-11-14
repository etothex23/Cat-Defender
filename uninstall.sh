#!/bin/sh
PREFIX=${PREFIX:-$HOME/.local}
rm -rf "$PREFIX/share/cat-defender" "$PREFIX/bin/cat-defender" "$PREFIX/bin/meowtron"
echo "Meowtron removed. (Bash 5 from Homebrew was left alone; see docs/ENVIRONMENT.md to remove it.)"
