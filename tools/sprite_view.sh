#!/usr/bin/env bash
# Render a .spr file with colour half-blocks. Usage: sprite_view.sh sprites/cat_fly_right.spr [scale-gap]
declare -A PAL
while read -r c n _; do [[ $c == \#* || -z $c ]] || PAL[$c]=$n; done < "$(dirname "$0")/../sprites/palette.txt"
mapfile -t rows < <(grep -v '^#' "$1")
w=${#rows[0]}
for ((y=0; y<${#rows[@]}; y+=2)); do
  line=''
  for ((x=0; x<w; x++)); do
    t=${rows[y]:x:1}; b=${rows[y+1]:x:1}; b=${b:-.}
    if [[ $t == . && $b == . ]]; then line+=' '
    elif [[ $b == . ]]; then line+="\e[38;5;${PAL[$t]}m▀\e[0m"
    elif [[ $t == . ]]; then line+="\e[38;5;${PAL[$b]}m▄\e[0m"
    else line+="\e[38;5;${PAL[$t]};48;5;${PAL[$b]}m▀\e[0m"; fi
  done
  printf '  %b\n' "$line"
done
