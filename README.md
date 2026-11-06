# Star Critters

A turn-based "grab the galaxy" strategy game for family game night (ages 6–12 and grown-ups).
1–4 players share one laptop or TV. Every turn is three steps: place critters (and maybe build
a city), send critters (two hops), play a Lucky Card. Planets are won in dice **dance-offs**, so
there's real luck; cities and befriending add a little strategy; and a grey fog called the
Gloom threatens everyone, so rivals sometimes have to team up.

- **Play it:** https://greentheo.github.io/star-critters/ (works best on a laptop or TV with a mouse)
- **Rules & design:** [docs/DESIGN.md](docs/DESIGN.md)
- **Modes:** Everyone for themselves · Teams (2v2) · Family vs the Gloom (co-op) · Learn to Play lesson
- **Options:** Simple / Full rules, Gloom on/off, Galaxy Small / Big / Huge, Star Clock Short / Medium / Long / Epic
- **Engine:** Godot 4.7, GL Compatibility, web export in `docs/` (served by GitHub Pages)

## Run it
```bash
godot --path .                      # play on the desktop
godot --headless --path . --export-release Web docs/index.html   # rebuild the web version
python3 -m http.server 8799 --directory docs                     # then open http://localhost:8799
```

## Code map
| File | What it does |
|---|---|
| `scripts/rules.gd` | All game rules. The whole game is one Dictionary, so Undo is a deep copy. Dice use a saved RNG state. |
| `scripts/mapgen.gd` | Symmetric galaxy generator (mirrored for 2/4 players, 3-way spin for 3), three sizes. |
| `scripts/ai.gd` | Greedy planner. Drives computer players, the Hint button and Cadet ideas. |
| `scripts/board.gd` | Draws the galaxy, count badges and highlights; animates critters flying along lanes. |
| `scripts/main.gd` | Setup screen, HUD, dance-off / befriend pop-up, auto-rolling dice panel, cities, turn screen with "while you were away" news, Learn to Play coach, game over. |
| `tools/make_art.py` | Writes every SVG in `assets/art/`. |
| `tools/sim.gd` | Headless AI-vs-AI balance sim: `godot --headless --path . -s tools/sim.gd` (`-- quick`, `-- one <i>`, `-- table`, `-- bonus`, `-- gtune`, `-- conq`, `-- coop`, `-- cities`, `-- maps`, `set <knob> <value>`) |
| `tools/smoke.gd`, `tools/click_test.gd` | Headless tests that drive the real UI and input pipeline (incl. an on-screen layout check). |

## Tuning knobs (all in `scripts/rules.gd`)
`GLOOM_TUNE` (Gloom growth, dance-offs per round, size limit, nest size per mode/player count),
`START_BONUS` (extra critters for later seats), `CITY_COST` / `CITY_STEP` / `CITY_MAKES`,
`FRIEND_ROUNDS`, `COOP_EXTRA`, `CLOCK` / `CLOCK_SCALE` (Star Clock; `LENGTHS` for co-op), `MAX_HOPS`, `TIES`, `CITY_FALLS`, `CITY_DEFENDS`, `RUSH_BONUS`,
`COSMIC` (space news and how often), `income()`, `crowd_bonus()`.
