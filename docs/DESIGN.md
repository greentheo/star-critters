# Star Critters — design (v3.1: "grab the galaxy, grow your cities")

A turn-based space strategy game for family game night. Ages 6–12 and grown-ups,
1–4 players around one laptop or TV. Area control with dice, like the classic
"conquer the map" board games, but nobody gets hurt: critters win planets in
**dance-offs**, and the losers just go home for a nap.

v1 had five ship types, stardust, beacons and a hard-to-read Gloom. Family feedback:
too many options per turn, the Gloom was confusing, and there was no luck. v2 answered that.
v2 feedback: too dice-driven, territory hard to read, maps too small. v3 adds a little
strategy (cities vs. expansion, one hop per turn, befriending), owner-coloured lanes and
bigger galaxies. v3.1 feedback: dice too fast, too few games actually won, cities hard to
spot, friendships invisible. v3.1: slower dice, 2 hops, ties to the attacker, Star Clock sized
so most games end with a winner, a city offer, and a pink loop around friends.

## Pillars
1. **Three steps per turn.** Place (and build), Send, (Cards). That's the whole turn.
2. **Luck you can feel.** Dice dance-offs, mystery planets, cosmic news, Lucky Cards.
3. **Part team, part every critter for themselves.** The Gloom threatens everyone, so rivals
   sometimes have to cooperate. Teammates gift critters. Befriending makes short truces.
4. **Games always end.** The Star Clock, a Star Rush at the end, and catch-up luck.
5. **A little strategy.** Cities (grow) vs. grabbing planets (expand), two hops per turn.
6. **Learn by playing.** A coached Learn to Play lesson on a small hand-made galaxy.

## The galaxy
A generated symmetric map, so every player starts in an equal spot: mirrored for 2 and 4
players, a 3-way spin for 3 players. **Small / Big / Huge** (about 20 / 30–37 / 40–57 planets);
the board zooms out to fit. The badge shows how many critters live on a planet, its ring shows
who owns it, and a lane between two planets of the same owner takes their colour.

| Place | What it does |
|---|---|
| **Home** | Where you start. +1 when defending a dance-off. Can be lost! |
| **Planet** | About half start empty, the rest have 1–2 wild critters. |
| **Golden planet** | 3 wild critters. Its owner gets +1 critter every turn. |
| **Mystery planet ?** | 1 wild critter. Whoever wins it first finds a surprise: 3 lost critters, a party (+1 on every planet you own), or a Lucky Card. |
| **Gloom nest** | Only when the Gloom is on. Starts the Gloom. +1 when defending. |

## A turn
1. **Place & build.** You get `2 + planets/2 + golden planets` new critters (minimum 3; Cadets +1;
   Star Rush +2). Click your planets to place them, or press *Place all*.
   **Build a city** (any time in your turn): it costs 5 critters from the planet itself
   (6 for your second city, 7 for the third...; one must stay). A city makes **+2 critters on
   its planet** at the start of each of your turns and gives **+1 when defending**. If someone
   wins the planet, the city is **knocked down**. At the start of your turn, and again when you
   finish placing, the game **offers** a city on any planet with enough critters (City on X /
   Not now), and a little city sign marks those planets. That's the big choice: grow cities, or
   spend critters grabbing planets and hope the dice like you.
2. **Send.** Click your planet, then a neighbour. Each critter can hop **two planets per turn**;
   after that it rests (zz) until your next turn. Winning a planet counts as a hop. One critter
   always stays behind.
   - an empty planet → **one** critter hops over and claims it (click it again to send everyone else);
   - your own planet → everyone who can go **moves**;
   - a teammate's planet → it's a **gift**; a friend's planet → a pop-up asks first
     (Send a gift / Never mind), because friends can't dance-off;
   - anyone else's → a pop-up: **Dance-off!**, **Befriend** (other players only) or Never mind.
   Send as many times as you like.
3. **Lucky Cards** (Full rules). Win at least one planet in a turn → draw a card at the end of
   it (hand of 3). Rocket Boost (+3 on a planet), Lucky Dice (roll 2, keep the best, rest of
   turn), Force Field (planet can't be danced on until your next turn), Instant City (free city).

Then press **Done**. Undo works for placing and moving, but never after dice, cards or surprises.

## Dance-offs
The dice roll by themselves, one roll every 1.6 seconds (0.9 for computers), and a little critter
appears on the side that won each roll. *Run away!* stops your own dance-off. Each roll:
attacker and defender each roll one die.
- Bigger crowd +1, twice as big +2 (attackers count everyone except the one staying behind).
- Homes, cities and Gloom nests +1 when defending.
- Higher total wins the roll; **a tie goes to the attacker**. The loser of the roll loses one critter.
- When the defenders reach 0, the dancers move in (that counts as a hop). It also stops when the attacker
  has no dancers left. When the Gloom wins, only half of its fog moves in (it spreads).

## Befriending (Everyone for themselves)
Pick Befriend instead of a dance-off. A person is asked on screen; a computer says yes unless
you're winning. If yes: no dance-offs between the two players for **3 rounds**, and those two
planets **defend together** (attackers face both crowds). Beat the pair and you win **both**.
One ask per turn. A pink loop goes around the two friend planets, and both players' chips show a
heart with the rounds left. The friendship is between the two players (no dance-offs anywhere),
and it ends early if either friend planet changes hands.

## The Gloom (optional in competitive games, always on in co-op)
A grey fog army that is **not a player**. After everyone has had a turn, the Gloom grows
(`base + round/div` fog critters on its strongest front) and starts a few dance-offs against
its weakest neighbours. If it ever covers about a third of the galaxy (shown top right as
"Gloom 4 / 8"), **everybody loses**. That's what makes rivals team up. In co-op, chase every
bit of Gloom out before the Star Clock runs out to win.

## Winning
- **Own every planet** → instant win (or your team does, in Teams).
- **Last one standing** → win.
- **Star Clock** runs out → most planets wins (ties: most critters). The rounds depend on the
  galaxy and the number of players: Medium is sized so about 8 in 10 computer games end with a
  winner first (Short ×0.7, Long ×1.3, Epic ×1.6). Medium: Small 13/19/27, Big 19/24/35,
  Huge 28/32/40 rounds for 2/3/4 players (Teams counts as 3). Co-op keeps 10/15/22/30 +3.
- The last 3 rounds are a **Star Rush**: +2 critters each turn to break stalemates.
- Lose your last planet? You **bounce back** once on a random wild planet with 4 critters.

## Luck & catch-up
- Each round may bring **space news**: Meteor Shower (+2 everyone), Lucky Comet (+4 to whoever
  has the fewest planets), Wild Bloom (+1 on wild planets), Golden Glow, Gloom Storm, or calm skies.
- Later seats start with a few extra critters (sim-tuned).

## Rules sets
| | Simple | Full |
|---|---|---|
| Place, Send, dance-offs, Gloom, news | ✓ | ✓ |
| Lucky Cards | | ✓ |
| Cities, two hops, befriending | ✓ | ✓ |

## Modes and seats
- **Everyone for themselves** (2–4), **Teams 2v2** (left vs right; gifts allowed),
  **Family vs the Gloom** (1–4, co-op).
- Seats: Player, **Cadet** (+1 critter a turn and an auto "Idea:" hint), Computer.
- **Learn to Play**: a 10-step coached lesson that walks through placing, grabbing, a dance-off,
  golden/mystery planets, the Gloom, ending a turn and Lucky Cards.

## Tuning (sim, 60–120 AI games each; real families will differ)
- v3 (one hop, ties to the defender, cautious computers): almost no game was ever won, even
  with no clock. Two hops + ties to the attacker + bolder computers (`AI.NEED` 1,
  `AI.DEF_PENALTY` 0.1) made winning normal: 2p ~77%, 3p ~75%, 4p ~60–70% on Medium, Big map.
- With cheap attacks, an early city became a huge prize and the first seat won 2 of 3 games.
  Start bonuses, peace rounds and 1-hop opening rounds didn't fix it (`PEACE_ROUNDS`,
  `SLOW_ROUNDS` are still there to try). Knocked-down cities (`CITY_FALLS`) plus city defence
  (`CITY_DEFENDS`) plus later-seat start bonuses did: 2p 30/30, 3p 24/18/18, 4p 15/21/13/11
  (of 60). The Small 2-player map still leans to seat 1 (about 38/22).
- The 3-player map is a 3-way spin; a mirrored 4-corner map left one player boxed in.
- Scoring at the end of your own last turn (v2) favoured early seats, so it's off (`FINAL_SNAPSHOT`).
- Co-op Gloom was retuned for two hops: about 83% solo (Simple rules), 78% with 2, 75% with 3,
  82% with 4; games last about 7–11 rounds.
- `tools/sim.gd -- table <galaxy> <players>` measures when games end (for the clock),
  `-- bonus`, `-- gtune`, `-- conq` and `set <knob> <value>` try variants; run them in parallel
  in the foreground (`xargs -P`), since macOS throttles background Godot runs.
