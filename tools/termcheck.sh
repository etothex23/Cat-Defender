#!/usr/bin/env bash
# Draws a 120x30 box with colour blocks so you can see whether the terminal is big enough.
W=120; H=30
if [ ! -t 1 ]; then
  echo "Not a real terminal (output is captured), so the size would be a default 80x24." >&2
  echo "Run this directly in your Terminal/iTerm window: ~/Github/Cat-Defender/tools/termcheck.sh" >&2
  exit 1
fi
cols=$(tput cols); rows=$(tput lines)
printf '\e[2J\e[H'
for ((y=1;y<=H;y++)); do
  printf '\e[%d;1H' "$y"
  if ((y==1)); then printf '+%s+' "$(printf '%*s' $((W-2)) '' | tr ' ' '-')"
  elif ((y==H)); then printf '+%s+' "$(printf '%*s' $((W-2)) '' | tr ' ' '-')"
  else printf '|\e[%d;%dH|' "$y" "$W"; fi
done
printf '\e[3;3HTerminal: %sx%s   (need %sx%s)' "$cols" "$rows" "$W" "$H"
for c in 196 208 226 46 51 21 129 201; do printf '\e[48;5;%sm  \e[0m' "$c"; done
printf '\e[4;3H'; for c in 196 208 226 46 51 21 129 201; do printf '\e[38;5;%sm▀▄█\e[0m ' "$c"; done
printf '\e[5;3H\e[1mIf you can see all four corners (+) and this line, size is OK.\e[0m'
printf '\e[%d;1H\n' $((H+1))
