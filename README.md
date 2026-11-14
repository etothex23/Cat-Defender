# MEOWTRON

A Defender-style shooter in Bash. You are a small orange tabby cat.
(Project folder is `Cat-Defender`; the game's name is Meowtron. Named by the crew: the human, C-Dog (Claude) and, OOR, G-Money (Gemini) is still welcome to pitch a better one.)

- **Cat swipe** (space) flings a biscuit with a speed trail. It pierces everything in its path.
- **Spazz-out** (X) is your smart bomb: the cat freaks out and pops every mouse on screen. You get 3.
- **Lives:** 3. Losing a kitten (splat or carried off) costs one. Bonus life every 5000 points.
- **Mice** run to a kitten, grab it, and float off on a balloon. Pop them with a swipe.
- **Kittens** are the people to rescue. If you pop the mouse, the kitten drops: catch it with the cat before it hits the ground, or it lands safely if the drop is short.
- The street (cardboard boxes, trash cans) is the mountain range.
- **Pigeons** home in on the cat. A hit costs a life (then you blink, safe, for 2 seconds). Pop them with a biscuit for 250.
- **Rats** run the street on a pattern, jump, turn around and bite if you fly low. Biscuit them for 200. They follow patterns you can edit (see below).
- The radar and more are still to come.

## Settings
`settings.conf` is plain text: edit it in any editor. The title screen (left/right, Enter) picks **easy / medium / hard** and saves it there.
- Each difficulty is a short block of numbers: lives, spazz bombs, how often mice, pigeons and rats show up, how many at once, rat speed.
- **Rat patterns** are one line each: `R` run, `J` jump, `T` turn around, `H` face the cat. `pattern1 = R R R J J` means run, run, run, jump, jump, then loop. Add `pattern5`, `pattern6`... for more. Each rat gets the next pattern in order.

## Play
```
bin/meowtron          # or bin/cat-defender
```
Arrows or WASD fly. Space throws a biscuit. X spazz-out. q quits.
Needs Bash 4+ and a 120x30 UTF-8 colour terminal. See docs/ENVIRONMENT.md. Check your terminal: `tools/termcheck.sh`

## Develop
- `tests/run_checks.sh`: syntax, speed and a "no ghost pixels" replay test.
- Headless play for testing: `AUTO=lazy TRACE=1 bash src/game.sh --bench 2000` (see the header of src/game.sh).
- Sprites are text files in `sprites/` (palette in `sprites/palette.txt`). `tools/spr_map.py` draws a labeled cell map.
