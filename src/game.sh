#!/usr/bin/env bash
# MEOWTRON - a Defender-style cat game in Bash. (Project folder: Cat-Defender.)
# Needs Bash 4+ (use bin/cat-defender, which finds one for you).
#
# Options:  --bench N        run N frames headless and print ms/frame
#           --snapshot FILE  run 90 frames headless, dump the last frame's pixels to FILE
# Settings live in settings.conf (difficulty, rat patterns). Test env: DIFFICULTY=easy|medium|hard, AUTO=1 (autopilot plays; AUTO=lazy only reacts once a kitten is taken), TRACE=1 (print game events), SPAWN_EVERY=N, RENDER_OUT=file

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Meowtron needs Bash 4+. Run bin/cat-defender or: brew install bash" >&2
  exit 1
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_SPAWN=${SPAWN_EVERY:-}; ENV_BIRD=${BIRD_EVERY:-}   # test overrides (win over settings.conf)

# ---- geometry (everything in "catxels"; 1 terminal cell = 1 wide x 2 tall catxels) ----
W=120            # screen width in catxels / columns
CH=30            # screen height in terminal rows
H=$((CH * 2))    # screen height in catxels (60)
WW=1200          # world width in catxels (wraps around)
GROUND=54        # first catxel row of the sidewalk (set from the screen size)
RB=11            # bottom border row of the radar panel (11 = tall radar, 7 = compact)
TOP=14           # top of the play area (rows above it belong to the radar)
SKY=17
FRAME_US=50000   # 20 frames per second

MODE=play; BENCH_FRAMES=0; SNAP_FILE=
case ${1:-} in
  --bench)    MODE=bench; BENCH_FRAMES=${2:-200} ;;
  --snapshot) MODE=snap;  BENCH_FRAMES=${2:-90}; SNAP_FILE=${3:-${2:?need a file}}
              [[ ${2:-} =~ ^[0-9]+$ ]] || BENCH_FRAMES=90 ;;
esac

# ---- palette + sprites ----
declare -A PAL SW SH
while read -r c n _; do [[ $c == \#* || -z $c ]] || PAL[$c]=$n; done < "$ROOT/sprites/palette.txt"

load_sprite() {  # name file [mirror]
  local name=$1 file=$2 mir=${3:-0} row ch x w=0 h=0
  local -n px="SPX_$name"
  px=()
  while IFS= read -r row; do
    [[ $row == \#* || -z $row ]] && continue
    w=${#row}
    for ((x = 0; x < w; x++)); do
      if ((mir)); then ch=${row:w-1-x:1}; else ch=${row:x:1}; fi
      if [[ $ch == . ]]; then px+=(-1); else px+=("${PAL[$ch]}"); fi
    done
    ((h++))
  done < "$file"
  SW[$name]=$w; SH[$name]=$h
}
declare -a SPX_cat_r SPX_cat_l SPX_box SPX_can SPX_swipe_r SPX_swipe_l
declare -a SPX_mouse_l SPX_mouse_r SPX_kitten SPX_balloon SPX_rat_l SPX_rat_r SPX_bird_la SPX_bird_lb SPX_bird_ra SPX_bird_rb
load_sprite cat_r "$ROOT/sprites/cat_fly_right_v3.spr"
load_sprite cat_l "$ROOT/sprites/cat_fly_right_v3.spr" 1
load_sprite swipe_r "$ROOT/sprites/swipe.spr"
load_sprite swipe_l "$ROOT/sprites/swipe.spr" 1
load_sprite mouse_l "$ROOT/sprites/mouse_left.spr"
load_sprite mouse_r "$ROOT/sprites/mouse_left.spr" 1
load_sprite bird_la "$ROOT/sprites/bird.spr"
load_sprite bird_ra "$ROOT/sprites/bird.spr" 1
load_sprite bird_lb "$ROOT/sprites/bird2.spr"
load_sprite bird_rb "$ROOT/sprites/bird2.spr" 1
load_sprite rat_l "$ROOT/sprites/rat.spr"
load_sprite rat_r "$ROOT/sprites/rat.spr" 1
load_sprite kitten  "$ROOT/sprites/kitten.spr"
load_sprite balloon "$ROOT/sprites/balloon.spr"
load_sprite box   "$ROOT/sprites/box.spr"
load_sprite can   "$ROOT/sprites/trashcan.spr"

# ---- frame buffer (one colour number per catxel) ----
declare -a fb sky pfb ZERO rd prd
init_sky() {
  local i x y
  for ((i = 0; i < W * H; i++)); do sky[i]=$SKY; done
  RANDOM=7
  for ((i = 0; i < W * H / 210; i++)); do  # stars
    x=$((RANDOM % W)); y=$((3 + RANDOM % (GROUND - 12)))
    sky[y * W + x]=$((RANDOM % 2 ? 250 : 244))
  done
  for ((y = GROUND; y < H; y++)); do       # street: sidewalk, curb, asphalt
    local c=236
    ((y == GROUND)) && c=250
    ((y == GROUND + 1)) && c=245
    ((y == GROUND + 2)) && c=240
    for ((x = 0; x < W; x++)); do sky[y * W + x]=$c; done
  done
  for ((i = 0; i < CH; i++)); do ZERO[i]=0; done
}

# Draw a sprite into fb (clipped) and mark the terminal rows it touches as "dirty".
blit() {  # sprite x y
  local -n px="SPX_$1"
  local w=${SW[$1]} h=${SH[$1]} x0=$2 y0=$3 i n=${#px[@]} c x y r
  for ((r = y0 >> 1; r <= (y0 + h - 1) >> 1; r++)); do ((r >= 0 && r < CH)) && rd[r]=1; done
  for ((i = 0; i < n; i++)); do
    c=${px[i]}; ((c < 0)) && continue
    x=$((x0 + i % w)); y=$((y0 + i / w))
    ((x < 0 || x >= W || y < 0 || y >= H)) && continue
    fb[y * W + x]=$c
  done
}

# Signed shortest distance a-b around the wrapping world, into WDV.
wd() { WDV=$(( ($1 - $2) % WW + WW + WW / 2 )); WDV=$(( WDV % WW - WW / 2 )); }

SOUND=0; SFX_LAST=0
# Sound effects: macOS system sounds through afplay (anything else gets the terminal bell for the big moments).
# Only in real play (never in headless tests). Toggle with M, or `sound = on|off` in settings.conf.
sfx() {  # name [volume]
  local f=/System/Library/Sounds/$1.aiff now=${EPOCHREALTIME/./}
  ((now - SFX_LAST < 60000)) && return 0          # no more than ~16 sounds a second
  SFX_LAST=$now
  if [[ -r $f ]] && command -v afplay >/dev/null 2>&1; then { afplay -v "${2:-0.5}" "$f" >/dev/null 2>&1 & } 2>/dev/null
  else case $1 in Basso|Sosumi|Submarine|Hero) printf '\a' ;; esac; fi
}
sfx_for() {
  case $1 in
    "mouse popped"|"mouse spazzed"|"bird popped"|"rat popped") sfx Pop ;;
    "life lost (0 left)") sfx Sosumi 0.7 ;;
    "life lost"*) sfx Basso 0.7 ;;
    "kitten "*" caught") sfx Glass ;;
    "kitten "*" landed safely") sfx Tink 0.4 ;;
    "SPAZZ-OUT") sfx Submarine 0.7 ;;
    "bonus life") sfx Hero 0.6 ;;
  esac
}
ev() { ((SOUND)) && [[ $MODE == play ]] && sfx_for "$*"; [[ -n ${TRACE:-} ]] && echo "[f$frame] $*" >&2; return 0; }

# ---- settings.conf: "key = value" lines, [easy]/[medium]/[hard] sections, # comments ----
declare -A CFG
declare -a PATS=()
NPAT=0; DIFF=medium
load_settings() {
  local f=${SETTINGS_FILE:-$ROOT/settings.conf} sec= line k v
  [[ -r $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}; line=${line//$'\r'/}
    line=${line#"${line%%[![:space:]]*}"}; line=${line%"${line##*[![:space:]]}"}
    [[ -z $line ]] && continue
    if [[ $line == \[*\] ]]; then sec=${line:1:${#line}-2}; sec=${sec,,}; continue; fi
    [[ $line == *=* ]] || continue
    k=${line%%=*}; v=${line#*=}
    k=${k%"${k##*[![:space:]]}"}; v=${v#"${v%%[![:space:]]*}"}
    CFG[$sec.${k,,}]=$v
  done < "$f"
}
cfgn() {  # key default -> CV (a number; the difficulty section wins over the global one)
  local key=$1 def=$2
  if [[ -n ${CFG[$DIFF.$key]:-} ]]; then CV=${CFG[$DIFF.$key]}; elif [[ -n ${CFG[.$key]:-} ]]; then CV=${CFG[.$key]}; else CV=$def; fi
  [[ $CV =~ ^[0-9]+$ ]] || CV=$def
}
apply_settings() {
  local n=1 pat d=${DIFFICULTY:-${CFG[.difficulty]:-medium}}
  d=${d,,}; [[ $d == easy || $d == medium || $d == hard ]] || d=medium
  DIFF=$d
  cfgn lives 3;             LIVES=$CV
  cfgn spazz 3;             BOMBS=$CV
  cfgn extra_life_every 5000; EXTRA_STEP=$CV; EXTRA_AT=$CV
  cfgn mouse_every 60;      SPAWN_EVERY=$CV; [[ -n $ENV_SPAWN ]] && SPAWN_EVERY=$ENV_SPAWN
  cfgn max_mice 3;          MAXMICE=$CV
  cfgn bird_every 200;      BIRD_EVERY=$CV; [[ -n $ENV_BIRD ]] && BIRD_EVERY=$ENV_BIRD
  cfgn max_birds 2;         MAXBIRDS=$CV
  cfgn bird_boost 3;        BIRD_BOOST=$CV
  cfgn rat_every 160;       RAT_EVERY=$CV
  cfgn max_rats 2;          MAXRATS=$CV
  cfgn rat_speed 1;         ((CV < 1)) && CV=1; RAT_SPEED=$CV
  cfgn rat_step 10;         ((CV < 2)) && CV=2; RAT_STEP=$CV
  cfgn jump_height 14;      JUMP_H=$CV
  d=${CFG[.radar]:-on}; d=${d,,}; RADAR=1; [[ $d == off || $d == 0 || $d == no ]] && RADAR=0
  d=${CFG[.sound]:-on}; d=${d,,}; SOUND=1; [[ $d == off || $d == 0 || $d == no ]] && SOUND=0
  ((SPAWN_EVERY < 1)) && SPAWN_EVERY=1; ((BIRD_EVERY < 1)) && BIRD_EVERY=1; ((RAT_EVERY < 1)) && RAT_EVERY=1
  PATS=()
  while [[ -n ${CFG[.pattern$n]:-} ]]; do
    pat=${CFG[.pattern$n]^^}; pat=${pat//[^RJTH]/}
    [[ -n $pat ]] && PATS+=("$pat")
    n=$((n + 1))
  done
  ((${#PATS[@]})) || PATS=(RRRJJ RJJRR RRTRRJJT RRHJRRHJ)
  NPAT=${#PATS[@]}
}
write_setting() {  # key value: remember a choice in settings.conf (keeps your comments and layout)
  local f=${SETTINGS_FILE:-$ROOT/settings.conf} line out='' done=0
  [[ -w $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    if ((!done)) && [[ $line =~ ^[[:space:]]*$1[[:space:]]*= ]]; then
      line="$1 = $2"; [[ $1 == difficulty ]] && line+="        # easy | medium | hard"; [[ $1 == sound ]] && line+="                 # on | off"; done=1
    fi
    out+=$line$'\n'
  done < "$f"
  ((done)) && printf '%s' "$out" > "$f"
  return 0
}

# ---- world: cardboard boxes, stacks and trash cans along the street ----
declare -a OT OX
gen_world() {
  local x=45 k
  RANDOM=42
  while ((x < WW - 40)); do
    k=$((RANDOM % 4))
    case $k in 0) OT+=(box);; 1) OT+=(can);; 2) OT+=(stack);; 3) OT+=(can);; esac
    OX+=("$x")
    x=$((x + 32 + RANDOM % 55))
  done
}

# ---- kittens (the people to rescue). state: 0 on ground, 1 carried, 2 falling, 3 gone ----
NK=6
declare -a KX KY KS KV KF
gen_kittens() {
  local i x ok j d
  for ((i = 0; i < NK; i++)); do
    while :; do
      x=$((60 + RANDOM % (WW - 120))); ok=1
      for ((j = 0; j < ${#OX[@]}; j++)); do d=$((x - OX[j])); if ((d > -12 && d < 14)); then ok=0; break; fi; done
      for ((j = 0; j < i; j++)); do d=$((x - KX[j])); if ((d > -40 && d < 40)); then ok=0; break; fi; done
      ((ok)) && break
    done
    KX+=("$x"); KY+=($((GROUND - 6))); KS+=(0); KV+=(0); KF+=(0)
  done
}

# ---- game state (cat position in 1/8 catxel) ----
px8=$((200 * 8)); cam8=$((170 * 8)); vx=0; face=1
catY8=$((24 * 8)); catY=24; pcatY=24
quit=0; frame=0
SCORE=0; LOST=0; RESCUED=0
LIVES=3; BOMBS=3; EXTRA_AT=5000; EXTRA_STEP=5000      # lives: a lost kitten costs one; a bonus life every EXTRA_AT points
SPAZ=0; SPAZ_FRAMES=12; bomb=0; spaz_now=0; over=0   # spazz-out smart bomb
declare -a RING_X=(8 7 4 0 -4 -7 -8 -7 -4 0 4 7) RING_Y=(0 4 7 8 7 4 0 -4 -7 -8 -7 -4)
lose_life() { ((LIVES > 0)) && LIVES=$((LIVES - 1)); ((LIVES == 0)) && over=1; ev "life lost ($LIVES left)"; }

# ---- movement tuning. Unit: 1 catxel = 1 sprite pixel = 1 terminal column wide.
# Speeds are stored in 1/8 catxel per frame (the game runs 20 frames/s).
BURST=16        # instant kick on a fresh tap (= 2 catxels/frame)
PUSH=10         # extra push per frame ...
PUSH_FRAMES=3   # ... for this many frames after a fresh tap
ACC=14          # speed gained per key-repeat event while the key is held down
MAXV=44         # top speed (= 5.5 catxels/frame = 110 catxels/s)
REPEAT_GAP=3    # frames: a key event after a longer gap counts as a fresh tap
CRUISE=16       # above this speed, coasting slows down fast; below it, the cat drifts
FRIC_FAST=13    # coasting above cruise: speed x 13/16 per frame
FRIC_DRIFT=61   # drifting below cruise: speed x 61/64 per frame (a long slide)
SINK=1          # gentle fall, 1/8 catxel per frame (about 2.5 catxels/s)
DRIFT_MIN=2     # resting drift speed in the direction you last flew (1/8 catxel/frame)
declare -a WIND=(0 1 2 3 2 1 0 -1 -2 -3 -2 -1)   # breeze that sways the drift, one step per 1.5 s
push_dir=0; push_left=0; moved=0; frozen=0; lastR=-99; lastL=-99

# ---- cat swipe (the beam)
SWIPE_SPEED=6   # catxels per frame (fast: 120 catxels/s)
SWIPE_LIFE=14   # frames before it fades (range = speed x life = 84 catxels)
COOLDOWN=4      # frames between swipes
MAX_SWIPES=4    # on screen at once
declare -a SX SY SD SL
cool=0; fire=0

# ---- mice (they take kittens up on balloons)
MAXMICE=3                          # on the street at once
SPAWN_EVERY=${SPAWN_EVERY:-60}     # frames between new mice (if a free kitten exists)
RISE_EVERY=3                       # a carrying mouse rises 1 catxel every N frames
SAFE_FALL=22                       # a kitten dropped from higher than this is lost unless caught
declare -a MX MY MS MK MD          # x, y, state (0 running, 1 carrying), kitten index, facing

# ---- rats: street runners that follow a pattern from settings.conf (R run, J jump, T turn, H face the cat) ----
RAT_G=$((GROUND - 5))              # a rat's resting y
RAT_COUNT=0
declare -a RX RO RD RP RI RT RA    # x, lift (jump height now), direction, pattern, step index, frames left in step, action

spawn_rat() {
  ((${#RX[@]} >= MAXRATS || NPAT == 0)) && return
  local cx=$((px8 >> 3)) x
  x=$(( cx + (RANDOM % 2 ? W / 2 + 12 : -W / 2 - 22) )); x=$(( (x % WW + WW) % WW ))
  wd "$cx" "$x"
  RX+=("$x"); RO+=(0); RD+=($((WDV > 0 ? 1 : -1))); RP+=($((RAT_COUNT % NPAT))); RI+=(0); RT+=(0); RA+=(R)
  ev "rat spawned, pattern $((RAT_COUNT % NPAT + 1)): ${PATS[RAT_COUNT % NPAT]}"
  RAT_COUNT=$((RAT_COUNT + 1))
}

rat_next() {  # pick this rat's next R/J step; T and H are instant
  local i=$1 pat=${PATS[${RP[$1]}]} tries=0 tok n
  n=${#pat}
  while ((tries < n)); do
    tok=${pat:${RI[i]}:1}; RI[i]=$(( (RI[i] + 1) % n )); tries=$((tries + 1))
    case $tok in
      T) RD[i]=$((-RD[i])) ;;
      H) wd $((px8 >> 3)) "${RX[i]}"; RD[i]=$((WDV > 0 ? 1 : -1)) ;;
      R|J) RA[i]=$tok; RT[i]=$RAT_STEP; return ;;
    esac
  done
  RA[i]=R; RT[i]=$RAT_STEP
}

update_rats() {
  local i j x o d alive sx dx ry t cx=$((px8 >> 3))
  local -a nx=() no=() nd=() np=() ni=() nt=() na=()
  for ((i = 0; i < ${#RX[@]}; i++)); do
    ((RT[i] <= 0)) && rat_next "$i"
    d=${RD[i]}; x=$(( ((RX[i] + d * RAT_SPEED) % WW + WW) % WW ))
    o=0
    if [[ ${RA[i]} == J ]]; then t=$((RAT_STEP - RT[i])); o=$(( 4 * JUMP_H * t * (RAT_STEP - t) / (RAT_STEP * RAT_STEP) )); fi
    RT[i]=$((RT[i] - 1)); ry=$((RAT_G - o)); alive=1
    for ((j = 0; j < ${#SX[@]}; j++)); do      # biscuit hits (they pierce)
      wd $((SX[j] + 4)) $((x + 5)); dx=${WDV#-}
      if ((dx < 9 && SY[j] + 5 > ry && SY[j] < ry + 5)); then alive=0; break; fi
    done
    if ((alive && spaz_now)); then
      sx=$(( ((x - (cam8 >> 3)) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
      ((sx >= -12 && sx < W)) && alive=0
    fi
    if ((!alive)); then SCORE=$((SCORE + 200)); ev "rat popped"; continue; fi
    wd $((cx + 4)) $((x + 5)); dx=${WDV#-}
    if ((inv == 0 && dx < 8 && ry + 5 > catY && ry < catY + 6)); then
      lose_life; inv=$INVULN; ev "rat bit the cat"; continue
    fi
    nx+=("$x"); no+=("$o"); nd+=("${RD[i]}"); np+=("${RP[i]}"); ni+=("${RI[i]}"); nt+=("${RT[i]}"); na+=("${RA[i]}")
  done
  RX=("${nx[@]}"); RO=("${no[@]}"); RD=("${nd[@]}"); RP=("${np[@]}"); RI=("${ni[@]}"); RT=("${nt[@]}"); RA=("${na[@]}")
}

# ---- birds: pigeons home in on the cat. A hit costs a life. A swipe or a spazz pops them. ----
MAXBIRDS=2
BIRD_EVERY=${BIRD_EVERY:-200}      # frames between new birds
INVULN=40                          # frames the cat is safe (and blinking) after a hit
inv=0
declare -a BX BY BD                # x, y, facing

spawn_bird() {
  ((${#BX[@]} >= MAXBIRDS)) && return
  local x=$(( (px8 >> 3) + (RANDOM % 2 ? W / 2 + 14 : -W / 2 - 20) ))
  BX+=($(( (x % WW + WW) % WW ))); BY+=($((TOP + 2 + RANDOM % 12))); BD+=(-1)
  ev "bird spawned"
}

update_birds() {
  local i j x y d dx dy alive sx cx=$((px8 >> 3)) step
  local -a nx=() ny=() nd=()
  for ((i = 0; i < ${#BX[@]}; i++)); do
    x=${BX[i]}; y=${BY[i]}; d=${BD[i]}; alive=1
    for ((j = 0; j < ${#SX[@]}; j++)); do      # biscuit hits (they pierce)
      wd $((SX[j] + 4)) $((x + 4)); dx=${WDV#-}
      if ((dx < 8 && SY[j] + 5 > y && SY[j] < y + 5)); then alive=0; break; fi
    done
    if ((alive && spaz_now)); then             # spazz-out pops every bird on screen
      sx=$(( ((x - (cam8 >> 3)) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
      ((sx >= -12 && sx < W)) && alive=0
    fi
    if ((!alive)); then SCORE=$((SCORE + 250)); ev "bird popped"; continue; fi
    wd "$cx" "$x"; dx=$WDV                     # cat minus bird
    step=$((1 + (BIRD_BOOST > 0 && frame % BIRD_BOOST == 0)))
    if ((dx > 2)); then x=$(( (x + step) % WW )); d=1; elif ((dx < -2)); then x=$(( (x - step + WW) % WW )); d=-1; fi
    dy=$((catY - y))
    if ((frame % 2 == 0)); then ((dy > 1)) && y=$((y + 1)); ((dy < -1)) && y=$((y - 1)); fi
    ((y < TOP)) && y=$TOP; ((y > GROUND - 8)) && y=$((GROUND - 8))
    wd "$cx" "$x"; dx=${WDV#-}
    if ((inv == 0 && dx < 8 && y - catY < 5 && catY - y < 5)); then   # it got the cat
      lose_life; inv=$INVULN; ev "bird hit the cat"; continue
    fi
    nx+=("$x"); ny+=("$y"); nd+=("$d")
  done
  BX=("${nx[@]}"); BY=("${ny[@]}"); BD=("${nd[@]}")
}

handle_key() {
  case $1 in
    $'\e[C'|$'\eOC'|d)
      if ((frame - lastR > REPEAT_GAP)); then vx=$((vx + BURST)); push_dir=1; push_left=$PUSH_FRAMES
      else vx=$((vx + ACC)); fi
      lastR=$frame; moved=1; face=1 ;;
    $'\e[D'|$'\eOD'|a)
      if ((frame - lastL > REPEAT_GAP)); then vx=$((vx - BURST)); push_dir=-1; push_left=$PUSH_FRAMES
      else vx=$((vx - ACC)); fi
      lastL=$frame; moved=1; face=-1 ;;
    $'\e[A'|$'\eOA'|w) catY8=$((catY8 - 16)); frozen=1 ;;
    $'\e[B'|$'\eOB'|s) catY8=$((catY8 + 16)); frozen=1 ;;
    ' ') fire=1 ;;
    x|X|b|B) bomb=1 ;;
    m|M) SOUND=$((1 - SOUND)); write_setting sound "$( ((SOUND)) && echo on || echo off )"; ((SOUND)) && sfx Pop ;;
    q|Q) quit=1 ;;
  esac
}

read_input() {
  local k r
  while read -t 0 -rs; do
    IFS= read -rsn1 k || break
    if [[ $k == $'\e' ]]; then IFS= read -rsn2 -t 0.01 r; k+=$r; fi
    handle_key "$k"
  done
}

# Headless stand-in for the keyboard. AUTO=1 plays the game: chase the best target and swipe it.
autopilot() {
  local i bd=99999 tx= ty= d dd cx=$((px8 >> 3))
  for ((i = 0; i < ${#MX[@]}; i++)); do
    [[ ${AUTO:-} == lazy ]] && ((MS[i] == 0)) && continue   # lazy: only react once a kitten is taken
    wd "${MX[i]}" "$cx"; d=${WDV#-}; ((MS[i] == 1)) && d=$((d - 500))
    if ((d < bd)); then bd=$d; tx=${MX[i]}; ty=${MY[i]}; fi
  done
  for ((i = 0; i < ${#RX[@]}; i++)); do
    wd "${RX[i]}" "$cx"; d=$(( ${WDV#-} - 800 ))
    if ((d < bd)); then bd=$d; tx=${RX[i]}; ty=$((RAT_G - RO[i])); fi
  done
  for ((i = 0; i < ${#BX[@]}; i++)); do
    wd "${BX[i]}" "$cx"; d=$(( ${WDV#-} - 1500 ))
    if ((d < bd)); then bd=$d; tx=${BX[i]}; ty=${BY[i]}; fi
  done
  for ((i = 0; i < NK; i++)); do
    ((KS[i] == 2)) || continue
    wd "${KX[i]}" "$cx"; d=$(( ${WDV#-} - 1000 ))
    if ((d < bd)); then bd=$d; tx=${KX[i]}; ty=${KY[i]}; fi
  done
  ((frame % 300 == 299)) && handle_key x
  [[ -z $tx ]] && return
  wd "$tx" "$cx"; dd=$WDV
  if ((dd > 12)); then handle_key $'\e[C'; elif ((dd < -12)); then handle_key $'\e[D'; fi
  if ((catY < ty - 1)); then handle_key $'\e[B'; elif ((catY > ty + 1)); then handle_key $'\e[A'; fi
  if (( (dd > 0 && face > 0 || dd < 0 && face < 0) && ${dd#-} < 80 && catY - ty < 4 && ty - catY < 4 )); then handle_key ' '; fi
}

sim_input() {
  if [[ ${AUTO:-} == idle ]]; then return; fi   # idle: a player who does nothing
  if [[ -n ${AUTO:-} ]]; then autopilot; return; fi
  if [[ -n ${TAPTEST:-} ]]; then   # one tap at frame 0, then 12 frames of held key at frame 60, then release
    ((frame == 0)) && handle_key $'\e[C'
    ((frame >= 60 && frame < 72)) && handle_key $'\e[C'
    [[ -n ${VTEST:-} ]] && ((frame >= 8 && frame < 30)) && handle_key $'\e[A'
    return
  fi
  if ((frame < BENCH_FRAMES * 2 / 3)); then handle_key $'\e[C'; else handle_key $'\e[D'; fi
  ((frame % 8 == 0)) && handle_key ' '
  case $((frame / 10 % 4)) in 0) handle_key $'\e[A';; 2) handle_key $'\e[B';; esac
}

# ---- swipes ----
spawn_swipe() {
  ((${#SX[@]} >= MAX_SWIPES)) && return
  SX+=($(( (px8 >> 3) + (face > 0 ? 9 : -8) ))); SY+=($((catY + 1))); SD+=("$face"); SL+=("$SWIPE_LIFE")
}
move_swipes() {
  local i nx=() ny=() nd=() nl=()
  for ((i = 0; i < ${#SX[@]}; i++)); do
    ((SL[i]--)); ((SL[i] <= 0)) && continue
    nx+=($(( ((SX[i] + SD[i] * SWIPE_SPEED) % WW + WW) % WW ))); ny+=("${SY[i]}"); nd+=("${SD[i]}"); nl+=("${SL[i]}")
  done
  SX=("${nx[@]}"); SY=("${ny[@]}"); SD=("${nd[@]}"); SL=("${nl[@]}")
}

# ---- mice: run to a kitten, grab it, rise on a balloon. A swipe pops them. ----
spawn_mouse() {
  local i j k taken cx x cand=()
  ((${#MX[@]} >= MAXMICE)) && return
  for ((i = 0; i < NK; i++)); do
    ((KS[i] == 0)) || continue
    taken=0
    for ((j = 0; j < ${#MK[@]}; j++)); do ((MK[j] == i)) && taken=1; done
    ((taken)) || cand+=("$i")
  done
  ((${#cand[@]} == 0)) && return
  k=${cand[RANDOM % ${#cand[@]}]}
  cx=$((cam8 >> 3))
  if ((RANDOM % 2)); then x=$((cx + W + 20)); else x=$((cx - 30)); fi
  x=$(( (x % WW + WW) % WW ))
  MX+=("$x"); MY+=($((GROUND - 6))); MS+=(0); MK+=("$k"); MD+=(-1)
  ev "mouse spawned for kitten $k"
}

update_mice() {
  local i j k s x y d top alive sx
  local -a nx=() ny=() ns=() nk=() nd=()
  for ((i = 0; i < ${#MX[@]}; i++)); do
    x=${MX[i]}; y=${MY[i]}; s=${MS[i]}; k=${MK[i]}; alive=1
    top=$y; ((s == 1)) && top=$((y - 5))      # the balloon counts as part of the mouse
    if ((spaz_now)); then                      # spazz-out: pops every mouse on screen
      sx=$(( ((x - (cam8 >> 3)) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
      if ((sx >= -12 && sx < W)); then
        SCORE=$((SCORE + 150)); ev "mouse spazzed"
        if ((s == 1)); then KS[k]=2; KV[k]=0; KF[k]=${KY[k]}; ev "kitten $k falling"; fi
        continue
      fi
    fi
    for ((j = 0; j < ${#SX[@]}; j++)); do     # swipe hits (swipes pierce)
      wd $((SX[j] + 4)) $((x + 5)); d=${WDV#-}
      if ((d < 9 && SY[j] + 5 > top && SY[j] < y + 6)); then
        alive=0; SCORE=$((SCORE + 150)); ev "mouse popped"
        if ((s == 1)); then KS[k]=2; KV[k]=0; KF[k]=${KY[k]}; ev "kitten $k falling"; fi
        break
      fi
    done
    ((alive)) || continue
    if ((s == 0)); then
      wd "${KX[k]}" "$x"
      if ((WDV > -3 && WDV < 3)); then s=1; KS[k]=1; ev "mouse grabbed kitten $k"
      elif ((WDV > 0)); then x=$(( (x + 1) % WW )); MD[i]=1
      else x=$(( (x - 1 + WW) % WW )); MD[i]=-1; fi
    else
      ((frame % RISE_EVERY == 0)) && y=$((y - 1))
      KX[k]=$((x + 1)); KY[k]=$(( y + 5 > GROUND - 6 ? GROUND - 6 : y + 5 ))
      if ((y <= TOP + 5)); then KS[k]=3; LOST=$((LOST + 1)); lose_life; ev "kitten $k lost to the sky"; continue; fi
    fi
    nx+=("$x"); ny+=("$y"); ns+=("$s"); nk+=("$k"); nd+=("${MD[i]}")
  done
  MX=("${nx[@]}"); MY=("${ny[@]}"); MS=("${ns[@]}"); MK=("${nk[@]}"); MD=("${nd[@]}")
}

# ---- falling kittens: catch them with the cat, or they land (or splat) ----
update_kittens() {
  local i step adx cxw=$((px8 >> 3))
  for ((i = 0; i < NK; i++)); do
    ((KS[i] == 2)) || continue
    step=$((1 + KV[i] / 6)); ((step > 3)) && step=3
    KY[i]=$((KY[i] + step)); KV[i]=$((KV[i] + 1))
    wd $((KX[i] + 4)) $((cxw + 4)); adx=${WDV#-}
    if ((adx < 8 && KY[i] - catY < 7 && catY - KY[i] < 7)); then
      KS[i]=0; KY[i]=$((GROUND - 6)); SCORE=$((SCORE + 500)); RESCUED=$((RESCUED + 1)); ev "kitten $i caught"
      continue
    fi
    if ((KY[i] >= GROUND - 6)); then
      KY[i]=$((GROUND - 6))
      if ((GROUND - 6 - KF[i] > SAFE_FALL)); then KS[i]=3; LOST=$((LOST + 1)); lose_life; ev "kitten $i splat"
      else KS[i]=0; SCORE=$((SCORE + 100)); ev "kitten $i landed safely"; fi
    fi
  done
}

update() {
  if ((over)); then fire=0; bomb=0; moved=0; frozen=0; return; fi
  local av=$((vx < 0 ? -vx : vx))
  if ((push_left > 0)); then vx=$((vx + push_dir * PUSH)); ((push_left--)); fi
  if ((!moved && !frozen)); then           # no horizontal OR vertical key this frame: coast
    if ((av > CRUISE)); then vx=$((vx * FRIC_FAST / 16))
    else                                   # settle onto a slow drift: last heading + breeze
      local tgt=$((face * DRIFT_MIN + WIND[(frame / 30) % 12]))
      vx=$((tgt + (vx - tgt) * FRIC_DRIFT / 64))
    fi
  fi
  moved=0; frozen=0
  ((vx > MAXV)) && vx=$MAXV
  ((vx < -MAXV)) && vx=$((-MAXV))
  [[ -n ${TRACEVX:-} ]] && echo "f=$frame vx=$vx" >&2
  px8=$((px8 + vx))
  catY8=$((catY8 + SINK))                  # slow sink
  ((catY8 < TOP * 8)) && catY8=$((TOP * 8))
  ((catY8 > (GROUND - 8) * 8)) && catY8=$(((GROUND - 8) * 8))
  catY=$((catY8 >> 3))
  ((cool > 0)) && ((cool--))
  if ((fire && cool == 0)); then spawn_swipe; cool=$COOLDOWN; fi
  fire=0
  move_swipes
  if ((bomb && BOMBS > 0 && SPAZ == 0)); then BOMBS=$((BOMBS - 1)); SPAZ=$SPAZ_FRAMES; spaz_now=1; ev "SPAZZ-OUT"; fi
  bomb=0
  if ((frame > 0 && frame % SPAWN_EVERY == 0)); then spawn_mouse; fi
  if ((frame > 0 && frame % BIRD_EVERY == 0)); then spawn_bird; fi
  if ((frame > 0 && frame % RAT_EVERY == 0)); then spawn_rat; fi
  ((inv > 0)) && inv=$((inv - 1))
  update_mice
  update_birds
  update_rats
  spaz_now=0; ((SPAZ > 0)) && SPAZ=$((SPAZ - 1))
  update_kittens
  if ((SCORE >= EXTRA_AT)); then LIVES=$((LIVES + 1)); EXTRA_AT=$((EXTRA_AT + EXTRA_STEP)); ev "bonus life"; fi
  local tgt=$((px8 - (face > 0 ? W * 5 / 24 : W * 7 / 12) * 8))
  cam8=$((cam8 + (tgt - cam8) / 6))
  if ((px8 >= WW * 8)); then px8=$((px8 - WW * 8)); cam8=$((cam8 - WW * 8)); fi
  if ((px8 < 0));       then px8=$((px8 + WW * 8)); cam8=$((cam8 + WW * 8)); fi
}

# ---- radar: the whole wrapping world as a strip across the top (rows 2-7) ----
RDW=80; RDX0=$(((W - RDW) / 2)); RADAR=1   # (set again by fit_screen)
bake_radar() {   # the static part: panel, frame and the street furniture
  ((RADAR)) || return 0
  local x y i
  for ((y = 2; y <= RB; y++)); do
    for ((x = RDX0 - 1; x <= RDX0 + RDW; x++)); do
      if ((y == 2 || y == RB || x == RDX0 - 1 || x == RDX0 + RDW)); then sky[y * W + x]=238; else sky[y * W + x]=233; fi
    done
  done
  for ((i = 0; i < ${#OX[@]}; i++)); do x=$((RDX0 + OX[i] * RDW / WW)); sky[(RB - 1) * W + x]=240; done
}
rplot() {  # world-x, world-y, colour: a 1x2 dot at the matching height in the strip
  local x=$((RDX0 + ((($1 % WW) + WW) % WW) * RDW / WW)) y=$((3 + ($2 - TOP) * (RB - 4) / (GROUND - TOP)))
  ((y < 3)) && y=3; ((y > RB - 2)) && y=$((RB - 2))
  fb[y * W + x]=$3; fb[(y + 1) * W + x]=$3
}
radar() {
  ((RADAR)) || return 0
  local i k x y v c cx=$((px8 >> 3)) blink=$((frame / 3 % 2))
  for ((k = 1; k <= RB / 2; k++)); do rd[k]=1; done
  v=$(( ((cam8 >> 3) % WW + WW) % WW * RDW / WW ))      # your view, as a bright bracket
  for ((k = 0; k <= W * RDW / WW; k++)); do x=$((RDX0 + (v + k) % RDW)); fb[2 * W + x]=252; fb[RB * W + x]=252; done
  x=$((RDX0 + cx * RDW / WW)); for ((k = 3; k < RB; k++)); do fb[k * W + x]=94; done   # a dim line down from you
  for ((i = 0; i < ${#MX[@]}; i++)); do c=250; ((MS[i] == 1 && blink)) && c=231; rplot "${MX[i]}" "${MY[i]}" "$c"; done
  for ((i = 0; i < ${#RX[@]}; i++)); do rplot "${RX[i]}" $((RAT_G - RO[i])) 137; done
  for ((i = 0; i < ${#BX[@]}; i++)); do rplot "${BX[i]}" "${BY[i]}" 117; done
  for ((i = 0; i < NK; i++)); do
    case ${KS[i]} in 0) c=211;; 1) c=196; ((blink)) && c=203;; 2) c=226;; *) continue;; esac
    rplot "${KX[i]}" "${KY[i]}" "$c"
  done
  y=$((3 + (catY - TOP) * (RB - 4) / (GROUND - TOP))); ((y < 3)) && y=3; ((y > RB - 2)) && y=$((RB - 2))   # the cat, at its height
  fb[y * W + x]=208; fb[y * W + x + 1]=208; fb[(y + 1) * W + x]=208; fb[(y + 1) * W + x + 1]=208
}

compose() {
  local camx=$((cam8 >> 3)) i sx x y wf
  fb=("${sky[@]}"); rd=("${ZERO[@]}")
  # street markings scroll with the world
  for ((x = 0; x < W; x++)); do
    ((((x + camx) % 20) < 9)) && fb[(H - 2) * W + x]=220
    ((((x + camx) % 40) == 0)) && fb[(GROUND + 1) * W + x]=240
  done
  # terrain
  for ((i = 0; i < ${#OX[@]}; i++)); do
    sx=$(( ((OX[i] - camx) % WW + WW) % WW ))
    ((sx > WW - 20)) && sx=$((sx - WW))
    ((sx >= W || sx < -12)) && continue
    case ${OT[i]} in
      box)   blit box "$sx" $((GROUND - 6)) ;;
      can)   blit can "$sx" $((GROUND - 6)) ;;
      stack) blit box "$sx" $((GROUND - 6)); blit box $((sx + 1)) $((GROUND - 12)) ;;
    esac
  done
  # kittens
  for ((i = 0; i < NK; i++)); do
    ((KS[i] == 3)) && continue
    sx=$(( ((KX[i] - camx) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
    ((sx >= W || sx < -12)) && continue
    blit kitten "$sx" "${KY[i]}"
  done
  # mice (a balloon above any mouse that is carrying a kitten)
  for ((i = 0; i < ${#MX[@]}; i++)); do
    sx=$(( ((MX[i] - camx) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
    ((sx >= W || sx < -12)) && continue
    ((MS[i] == 1)) && blit balloon $((sx + 2)) $((MY[i] - 5))
    if ((MD[i] > 0)); then blit mouse_r "$sx" "${MY[i]}"; else blit mouse_l "$sx" "${MY[i]}"; fi
  done
  # rats
  for ((i = 0; i < ${#RX[@]}; i++)); do
    sx=$(( ((RX[i] - camx) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
    ((sx >= W || sx < -12)) && continue
    if ((RD[i] > 0)); then blit rat_r "$sx" $((RAT_G - RO[i])); else blit rat_l "$sx" $((RAT_G - RO[i])); fi
  done
  # birds
  for ((i = 0; i < ${#BX[@]}; i++)); do
    sx=$(( ((BX[i] - camx) % WW + WW) % WW )); ((sx > WW - 20)) && sx=$((sx - WW))
    ((sx >= W || sx < -12)) && continue
    wf=a; ((frame / 3 % 2)) && wf=b
    if ((BD[i] > 0)); then blit "bird_r$wf" "$sx" "${BY[i]}"; else blit "bird_l$wf" "$sx" "${BY[i]}"; fi
  done
  # swipes
  for ((i = 0; i < ${#SX[@]}; i++)); do
    sx=$(( ((SX[i] - camx) % WW + WW) % WW ))
    ((sx > WW - 20)) && sx=$((sx - WW))
    if ((SD[i] > 0)); then blit swipe_r "$sx" "${SY[i]}"; else blit swipe_l "$sx" "${SY[i]}"; fi
  done
  # cat
  local sprite=cat_r; ((face < 0)) && sprite=cat_l
  local cxs=$(( (px8 - cam8) >> 3 )) cys=$catY
  if ((SPAZ > 0)); then                       # spazz-out: the cat shakes and a shockwave ring expands
    cxs=$((cxs + (SPAZ % 2 ? 2 : -2))); cys=$((cys + (SPAZ % 3 - 1)))
    local r=$(( (SPAZ_FRAMES - SPAZ + 1) * 5 )) rx ry
    for ((i = 0; i < 12; i++)); do
      rx=$((cxs + 8 + RING_X[i] * r / 8 * 2)); ry=$((cys + 3 + RING_Y[i] * r / 8))
      for ((x = 0; x < 3; x++)); do
        ((rx + x >= 0 && rx + x < W && ry >= 0 && ry < H)) && fb[ry * W + rx + x]=$((SPAZ % 2 ? 226 : 231))
      done
      ((ry >= 0 && ry < H)) && rd[ry >> 1]=1
    done
    for ((y = cys - 20; y <= cys + 26; y += 2)); do ((y >= 0 && y < H)) && rd[y >> 1]=1; done
  fi
  ((inv > 0 && frame % 4 < 2)) || blit "$sprite" "$cxs" "$cys"   # blinks while safe after a hit
  radar
}

# ---- terminal output: only changed cells, only rows that can change ----
ORIGX=1; ORIGY=1
render() {
  local out='' cy cx i top bot ci last=-9 cur_t=-1 cur_b=-1 alive=0 hud
  for ((cy = 1; cy < CH; cy++)); do
    # sky rows are static unless a sprite is (or just was) on them; rows 20+ hold the street
    if ((frame > 0 && cy < GROUND / 2 && !rd[cy] && !prd[cy])); then continue; fi
    for ((cx = 0; cx < W; cx++)); do
      i=$((2 * cy * W + cx)); top=${fb[i]}; bot=${fb[i + W]}
      ci=$((cy * W + cx))
      [[ ${pfb[i]} == "$top" && ${pfb[i + W]} == "$bot" ]] && continue
      if ((ci != last + 1 || cx == 0)); then out+=$'\e['$((cy + ORIGY))';'$((cx + ORIGX))'H'; fi
      if ((top != cur_t || bot != cur_b)); then out+=$'\e[38;5;'${top}';48;5;'${bot}'m'; cur_t=$top; cur_b=$bot; fi
      out+='▀'
      last=$ci
    done
  done
  pfb=("${fb[@]}"); prd=("${rd[@]}")
  if ((frame % 4 == 0)); then
    for ((i = 0; i < NK; i++)); do ((KS[i] != 3)) && ((alive++)); done
    out+=$'\e['$ORIGY';'$ORIGX'H\e[0;97;48;5;236m'
    local snd=off dtag=${DIFF^^}; ((SOUND)) && snd=on
    if ((W < 60)); then            # phone-sized
      if ((over)); then printf -v hud ' GAME OVER %d  q quit' "$SCORE"
      elif ((alive == 0)); then printf -v hud ' ALL GONE %d  q quit' "$SCORE"
      else printf -v hud ' %s %d  L%d Z%d K%d S%d M:%s' "${dtag:0:3}" "$SCORE" "$LIVES" "$BOMBS" "$alive" "$RESCUED" "$snd"; fi
    elif ((W < 120)); then
      if ((over)); then printf -v hud ' MEOWTRON  SCORE %d  GAME OVER - SAVED %d  press q ' "$SCORE" "$RESCUED"
      elif ((alive == 0)); then printf -v hud ' MEOWTRON  SCORE %d  ALL THE KITTENS ARE GONE  press q ' "$SCORE"
      else printf -v hud ' MEOWTRON [%s]  SCORE %d  LIVES %d  SPAZZ %d  KITTENS %d/%d  SAVED %d  M %s' "${DIFF^^}" "$SCORE" "$LIVES" "$BOMBS" "$alive" "$NK" "$RESCUED" "$snd"; fi
    elif ((over)); then
      printf -v hud ' MEOWTRON   SCORE %6d   GAME OVER - SAVED %d kitten(s)   press q ' "$SCORE" "$RESCUED"
    elif ((alive == 0)); then
      printf -v hud ' MEOWTRON   SCORE %6d   ALL THE KITTENS ARE GONE...   press q ' "$SCORE"
    else
      printf -v hud ' MEOWTRON [%s]  SCORE %6d  LIVES %d  SPAZZ %d  KITTENS %d/%d  SAVED %d  SPACE throw  X spazz  M sound %s  q quit' "${DIFF^^}" "$SCORE" "$LIVES" "$BOMBS" "$alive" "$NK" "$RESCUED" "$snd"
    fi
    hud=${hud:0:W}
    printf -v hud "%-${W}s" "$hud"
    out+=$hud
  fi
  printf '%s' "$out"
}

# ---- setup / teardown ----
# Screen size: `screen = auto` fits the terminal (up to 120x30, down to 40x20); `screen = 80x24` forces one.
fit_screen() {  # terminal-cols terminal-rows (empty when headless)
  local want=${SCREEN:-${CFG[.screen]:-auto}} cols=$1 rows=$2 w=120 ch=30
  want=${want,,}
  if [[ $want =~ ^([0-9]+)x([0-9]+)$ ]]; then w=${BASH_REMATCH[1]}; ch=${BASH_REMATCH[2]}
  elif [[ -n $cols ]]; then w=$((cols < 120 ? cols : 120)); ch=$((rows < 30 ? rows : 30)); fi
  ((w < 40)) && w=40; ((ch < 20)) && ch=20
  if [[ -n $cols ]] && ((cols < w || rows < ch)); then
    echo "Terminal is ${cols}x${rows}; Meowtron needs at least ${w}x${ch} (40x20 is the smallest). Enlarge the window or shrink the font." >&2
    exit 1
  fi
  W=$w; CH=$ch; H=$((CH * 2)); GROUND=$((H - 6)); RAT_G=$((GROUND - 5))
  RDW=$((W - 4 < 80 ? W - 4 : 80)); RDX0=$(((W - RDW) / 2))
  if ((CH < 26)); then RB=7; else RB=11; fi          # compact radar on small screens
  TOP=$((RB + 3))
  ((catY8 > (GROUND - 8) * 8)) && catY8=$(((GROUND - 8) * 8)); catY=$((catY8 >> 3))
}

setup_tty() {
  ORIGX=$(( (TCOLS - W) / 2 + 1 )); ORIGY=$(( (TROWS - CH) / 2 ))
  STTY_ORIG=$(stty -g)
  stty -echo -icanon
  printf '\e[?1049h\e[?25l\e[?7l\e[2J'
}
cleanup() {
  [[ $MODE == play ]] && printf '\e[0m\e[?7h\e[?25h\e[?1049l' && stty "$STTY_ORIG" 2>/dev/null
  [[ -n ${TMPD:-} ]] && rm -rf "$TMPD"
}
trap cleanup EXIT

# ---- title / settings page: pick a difficulty ----
title_screen() {
  local b=$(( (CH - 18) / 2 )) names=(easy medium hard) blurb=("5 lives, slow rats, few pests" "3 lives, the way it was meant" "2 lives, fast rats, lots of pests") idx=1 i k r row col out opt
  for i in 0 1 2; do [[ ${names[i]} == "$DIFF" ]] && idx=$i; done
  while :; do
    out=$'\e[0m\e[2J'
    at() { local t=${3:0:W}; out+=$'\e['$((ORIGY + b + $1))';'$((ORIGX + (W - ${#t}) / 2))'H'$2$t$'\e[0m'; }
    at 0  $'\e[1;38;5;208m' "M E O W T R O N"
    at 2  $'\e[38;5;250m' "a small cat. six kittens. too many mice."
    at 6  $'\e[38;5;252m' "D I F F I C U L T Y"
    opt=''
    for i in 0 1 2; do
      if ((i == idx)); then opt+=$'\e[1;30;48;5;208m  '${names[i]^^}$'  \e[0m   '; else opt+=$'\e[38;5;245m  '${names[i]}$'  \e[0m   '; fi
    done
    out+=$'\e['$((ORIGY + b + 8))';'$((ORIGX + (W - 28) / 2))'H'$opt
    at 10 $'\e[38;5;245m' "${blurb[idx]}"
    at 12 $'\e[38;5;252m' "M  sound: $( ((SOUND)) && echo ON || echo off )"
    at 14 $'\e[38;5;252m' "$( ((W < 50)) && echo "< > pick   ENTER play   Q quit" || echo "LEFT / RIGHT choose     ENTER play     Q quit" )"
    at 16 $'\e[38;5;240m' "$( ((W < 56)) || echo "rat patterns and every number live in settings.conf" )"
    printf '%s' "$out"
    IFS= read -rsn1 k || { quit=1; return; }
    if [[ $k == $'\e' ]]; then IFS= read -rsn2 -t 0.05 r; k+=$r; fi
    case $k in
      $'\e[C'|d|l) idx=$(( (idx + 1) % 3 )) ;;
      $'\e[D'|a|h) idx=$(( (idx + 2) % 3 )) ;;
      1|2|3) idx=$((k - 1)) ;;
      ''|$'\n'|' ') break ;;
      m|M) handle_key m ;;
      q|Q) quit=1; return ;;
    esac
  done
  DIFFICULTY=${names[idx]}; apply_settings; write_setting difficulty "$DIFF"
  printf '\e[0m\e[2J'
}

# ---- main ----
load_settings; apply_settings
TCOLS=; TROWS=
if [[ $MODE == play ]]; then
  [[ -t 0 && -t 1 ]] || { echo "Run this in a real terminal." >&2; exit 1; }
  TCOLS=$(tput cols); TROWS=$(tput lines)
fi
fit_screen "$TCOLS" "$TROWS"
init_sky; gen_world; gen_kittens
pfb=(); for ((i = 0; i < W * H; i++)); do pfb[i]=-1; done
rd=("${ZERO[@]}"); prd=("${ZERO[@]}")

if [[ $MODE == play ]]; then
  setup_tty
  title_screen
  ((quit)) && exit 0
  TMPD=$(mktemp -d); mkfifo "$TMPD/f"; exec {sfd}<>"$TMPD/f"
fi

bake_radar
t_start=${EPOCHREALTIME/./}
while ((!quit)); do
  t0=${EPOCHREALTIME/./}
  pcatY=$catY
  if [[ $MODE == play ]]; then read_input; else sim_input; fi
  update
  compose
  if [[ $MODE == play ]]; then
    render
    rem=$((FRAME_US - (${EPOCHREALTIME/./} - t0)))
    if ((rem > 0)); then printf -v s '0.%06d' "$rem"; read -rt "$s" -u "$sfd" || true; fi
  else
    render >> "${RENDER_OUT:-/dev/null}"
  fi
  ((frame++))
  if [[ $MODE != play ]] && ((frame >= BENCH_FRAMES)); then break; fi
done

if [[ $MODE == bench ]]; then
  el=$(( ${EPOCHREALTIME/./} - t_start ))
  echo "frames: $frame   avg: $((el / frame / 1000)).$(( (el / frame % 1000) / 100 )) ms/frame   (budget $((FRAME_US / 1000)) ms)   score: $SCORE  saved: $RESCUED  lost: $LOST  lives: $LIVES  spazz left: $BOMBS"
elif [[ $MODE == snap ]]; then
  printf '%s\n' "${fb[*]}" > "$SNAP_FILE"
  echo "wrote $SNAP_FILE"
fi
