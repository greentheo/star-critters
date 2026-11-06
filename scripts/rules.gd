extends RefCounted
## Pure game rules. The whole game is one Dictionary `s` so it can be
## duplicated for Undo and simulated headless.
##
## Planets hold critters. Each turn: 1) place new critters (and maybe build a city),
## 2) send critters ONE hop next door (grab empty planets, dance-off or befriend
## occupied ones), 3) play a Lucky Card. Dance-offs are dice rolls. Own every planet
## to win, or have the most when the Star Clock runs out. Cities make critters on
## their planet every turn. The Gloom is a grey army that grows every round; if it
## gets too big, everybody loses.

const MapGen = preload("res://scripts/mapgen.gd")

const WILD := -1
const GLOOM := -2
const MAX_HAND := 3
const LENGTHS := {"short": 10, "medium": 15, "long": 22, "epic": 30}  # co-op (+COOP_EXTRA)
# Star Clock "Medium" for everyone-for-themselves and teams: about 8 in 10 computer
# games end with a winner before the clock runs out (tools/sim.gd -- table).
const CLOCK := {
	"normal": {2: 13, 3: 19, 4: 27},
	"big": {2: 19, 3: 24, 4: 35},
	"huge": {2: 28, 3: 32, 4: 40},
}
const CLOCK_SCALE := {"short": 0.7, "medium": 1.0, "long": 1.3, "epic": 1.6}
const GALAXIES := ["normal", "big", "huge"]
const RUSH_ROUNDS := 3   # the last rounds are a Star Rush
const RUSH_BONUS := 2

const SPECIES := [
	{"id": "blorb", "name": "Blorbs", "color": Color("5ad16a")},
	{"id": "zibbit", "name": "Zibbits", "color": Color("b784ff")},
	{"id": "moxie", "name": "Moxies", "color": Color("ff9a3c")},
	{"id": "ploot", "name": "Ploots", "color": Color("4cc3ff")},
]
const GLOOM_COLOR := Color("8e86b5")
const WILD_COLOR := Color("d8d4ee")

const FRIEND_ROUNDS := 3  # befriending: no dance-offs between you for this many rounds

const CARD_ORDER := ["rocket", "dice", "shield", "city"]
const CARDS := {
	"rocket": {"name": "Rocket Boost", "icon": "icon_rocket", "target": "own",
		"tip": "+3 critters on one of your planets."},
	"dice": {"name": "Lucky Dice", "icon": "icon_dice", "target": "",
		"tip": "For the rest of this turn you roll 2 dice and keep the best one."},
	"shield": {"name": "Force Field", "icon": "icon_shield", "target": "own",
		"tip": "Pick one of your planets. Nobody can dance-off there until your next turn."},
	"city": {"name": "Instant City", "icon": "icon_city", "target": "own",
		"tip": "Build a city on one of your planets for free."},
}

# later seats start with a few extra critters at home to make up for going later
# seats 0 & 2 vs 1 & 3; the Gloom slows everyone down, so the head start matters less with it on
static var TEAM_BONUS := {false: [0, 1, 1, 2], true: [0, 1, 1, 1]}
static var START_BONUS := {1: [0], 2: [0, 3], 3: [0, 1, 3], 4: [0, 0, 0, 1]}
# Gloom strength. base: fog critters per round, div: +1 more every N rounds,
# attacks: dance-offs per round (1.5 = 1, 2, 1, 2...), limit: share of the galaxy that means everyone loses,
# nest: fog critters on each nest at the start.
# Cities: cost critters from the planet itself (+STEP for every city you already have),
# then make MAKES new critters on that planet at the start of each of your turns.
static var FINAL_SNAPSHOT := false  # true: score counted at the end of your own last turn
static var COOP_EXTRA := 3
static var CITY_COST := 5
static var CITY_STEP := 1
static var CITY_MAKES := 2
static var MAX_HOPS := 2     # how many planets a critter may hop each turn
static var HOME_BONUS := 1     # homes and nests defend with +1
static var PEACE_ROUNDS := 0   # no dance-offs against other players in the first rounds
static var CITY_FALLS := true  # true: a city is knocked down when its planet is won
static var CITY_DEFENDS := true  # true: city planets get +1 when defending
static var SLOW_ROUNDS := 0    # in the first rounds critters hop only 1 planet (nobody races to the middle)
static var TIES := "att"     # who wins a tied roll: "def", "att" or "none" (nobody loses, roll again)
static var GLOOM_TUNE := {
	"coop": {
		1: {"base": 3, "div": 4, "attacks": 2, "limit": 0.40, "nest": 8},
		2: {"base": 4, "div": 3, "attacks": 2, "limit": 0.34, "nest": 8},
		3: {"base": 8, "div": 3, "attacks": 3, "limit": 0.34, "nest": 12},
		4: {"base": 10, "div": 3, "attacks": 3.5, "limit": 0.34, "nest": 12},
	},
	"ffa": {
		2: {"base": 2, "div": 3, "attacks": 1, "limit": 0.30, "nest": 4},
		3: {"base": 2, "div": 3, "attacks": 2, "limit": 0.30, "nest": 4},
		4: {"base": 3, "div": 3, "attacks": 2, "limit": 0.30, "nest": 4},
	},
	"teams": {4: {"base": 3, "div": 3, "attacks": 2, "limit": 0.30, "nest": 4}},
}


# ---------------------------------------------------------------- setup

## cfg = {mode: "ffa"|"teams"|"coop", rules: "simple"|"full", gloom: bool,
##        length: "short"|"medium"|"long"|"epic", galaxy: "normal"|"big"|"huge", seed: int,
##        players: [{species: int, ai: bool, cadet: bool}]}
static func new_game(cfg: Dictionary) -> Dictionary:
	var mode: String = cfg.get("mode", "ffa")
	var pcfg: Array = cfg["players"]
	var n := pcfg.size()
	var seed_value: int = cfg.get("seed", randi())
	var gloom: bool = cfg.get("gloom", false) or mode == "coop"
	var galaxy: String = cfg.get("galaxy", "normal")
	var map := MapGen.generate(maxi(n, 2), "coop" if gloom else "ffa", seed_value, galaxy)
	var s := _base_state(cfg, map["nodes"], map["adj"])
	s["gloom"] = gloom
	s["max_rounds"] = clock_rounds(mode, n, galaxy, cfg.get("length", "medium"))
	s["size"] = map["size"]
	s["galaxy"] = galaxy
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	# wild critters are rolled once per symmetric group, so every start stays equally good
	var orbit_n := {}
	for nd in s["nodes"]:
		_init_node(nd)
		var o: int = nd.get("orbit", nd["id"])
		if not orbit_n.has(o):
			orbit_n[o] = [0, 0, 1, 2][rng.randi_range(0, 3)]  # half the plain planets start empty
		match nd["kind"]:
			"lantern":
				nd["kind"] = "golden"
				nd["n"] = 3
			"asteroid":
				nd["kind"] = "planet"
				nd["n"] = 0
			"nest":
				nd["owner"] = GLOOM
				nd["n"] = 3  # set from GLOOM_TUNE once players exist
			"mystery":
				nd["n"] = 1
			_:
				nd["n"] = orbit_n[o]
	var homes: Array = map["homes"]
	var home_for: Array = []
	if mode == "teams" and n == 4:
		home_for = [homes[0], homes[1], homes[3], homes[2]]  # left side vs right side
	elif homes.size() == 2:
		home_for = [homes[0], homes[1]]
	else:
		home_for = homes.duplicate()
	for i in n:
		var pc: Dictionary = pcfg[i]
		var home: int = home_for[i]
		s["nodes"][home]["owner"] = i
		s["nodes"][home]["n"] = 3 + _start_bonus(mode, n, i, gloom)
		_add_player(s, i, pc, home)
	for nd in s["nodes"]:
		if nd["kind"] == "home" and nd["owner"] < 0:
			nd["kind"] = "planet"
	_set_gloom_limit(s)
	if gloom:
		for nd in s["nodes"]:
			if nd["kind"] == "nest":
				nd["n"] = int(_gloom_tune(s)["nest"])
	start_turn(s)
	return s


## A small hand-made galaxy for the Learn to Play lesson.
static func new_tutorial(seed_value := 3) -> Dictionary:
	var pts := [
		Vector2(250, 360), Vector2(520, 220), Vector2(520, 520), Vector2(800, 370),
		Vector2(1080, 220), Vector2(1080, 520), Vector2(1350, 360), Vector2(800, 90),
	]
	var kinds := ["home", "planet", "planet", "golden", "mystery", "planet", "home", "nest"]
	var names := ["Home", "Pebble", "Waffle", "Goldie", "Mystery", "Muffin", "Zib Home", "Gloomy"]
	var lanes := [[0, 1], [0, 2], [1, 3], [2, 3], [3, 4], [3, 5], [4, 6], [5, 6], [1, 7], [7, 4]]
	var nodes: Array = []
	var adj: Array = []
	for i in pts.size():
		var nd := {"id": i, "name": names[i], "pos": pts[i], "kind": kinds[i], "look": i % 4}
		_init_node(nd)
		nodes.append(nd)
		adj.append([])
	for l in lanes:
		adj[l[0]].append(l[1])
		adj[l[1]].append(l[0])
	var cfg := {"mode": "ffa", "rules": "full", "length": "long", "seed": seed_value,
		"players": [{"species": 0}, {"species": 1, "ai": true}]}
	var s := _base_state(cfg, nodes, adj)
	s["gloom"] = true
	s["size"] = Vector2(1600, 900)
	s["tutorial"] = true
	var wild := [0, 0, 1, 3, 1, 2, 0, 2]
	for i in nodes.size():
		nodes[i]["n"] = wild[i]
	nodes[7]["owner"] = GLOOM
	_add_player(s, 0, cfg["players"][0], 0)
	_add_player(s, 1, cfg["players"][1], 6)
	nodes[0]["owner"] = 0
	nodes[0]["n"] = 4
	nodes[6]["owner"] = 1
	nodes[6]["n"] = 4
	s["gloom_limit"] = 5
	start_turn(s)
	return s


## How many rounds the Star Clock gives for this setup.
static func clock_rounds(mode: String, n: int, galaxy: String, length: String) -> int:
	if mode == "coop":
		return LENGTHS.get(length, 15) + COOP_EXTRA  # chasing every last bit of fog takes a while
	var k := 3 if mode == "teams" else clampi(n, 2, 4)  # two teams play about like three players
	var base: int = CLOCK.get(galaxy, CLOCK["normal"])[k]
	return int(round(base * float(CLOCK_SCALE.get(length, 1.0))))


static func _base_state(cfg: Dictionary, nodes: Array, adj: Array) -> Dictionary:
	var seed_value: int = cfg.get("seed", 1)
	return {
		"mode": cfg.get("mode", "ffa"), "rules": cfg.get("rules", "simple"),
		"nodes": nodes, "adj": adj, "players": [], "truces": [],
		"current": 0, "round": 1, "max_rounds": LENGTHS.get(cfg.get("length", "medium"), 15),
		"size": Vector2(1600, 900), "galaxy": "normal",
		"phase": "place", "gloom": false, "gloom_limit": 99, "cosmic": {}, "tutorial": false,
		"rng_seed": seed_value + 77, "rng_state": 0,
		"over": false, "result": "", "winners": [],
		"log": [], "log_seq": 0, "events": [], "seed": seed_value,
	}


static func _init_node(nd: Dictionary) -> void:
	nd["owner"] = WILD
	nd["n"] = 0
	nd["shield"] = -1
	nd["city"] = false
	nd["used"] = _zeros()  # used[i]: critters that already hopped i+1 times this turn


static func _add_player(s: Dictionary, i: int, pc: Dictionary, home: int) -> void:
	var sp: Dictionary = SPECIES[pc.get("species", i)]
	var mode: String = s["mode"]
	s["players"].append({
		"id": i, "name": sp["name"], "species": sp["id"], "color": sp["color"],
		"team": (i % 2) if mode == "teams" else (0 if mode == "coop" else i),
		"ai": pc.get("ai", false), "cadet": pc.get("cadet", false), "home": home,
		"to_place": 0, "cards": [], "captured": false, "out": false, "comeback": false,
		"lucky": false, "asked": false,
	})


static func _start_bonus(mode: String, n: int, i: int, gloom: bool) -> int:
	if mode == "coop":
		return 0
	if mode == "teams":
		return TEAM_BONUS[gloom][i]
	return START_BONUS[n][i]


static func _set_gloom_limit(s: Dictionary) -> void:
	if not s["gloom"]:
		return
	var t := _gloom_tune(s)
	s["gloom_limit"] = maxi(4, int(round(s["nodes"].size() * float(t["limit"]))))


static func _gloom_tune(s: Dictionary) -> Dictionary:
	var table: Dictionary = GLOOM_TUNE.get(s["mode"], GLOOM_TUNE["ffa"])
	var n: int = s["players"].size()
	if table.has(n):
		return table[n]
	return table.values()[0]


# ---------------------------------------------------------------- queries

static func node(s: Dictionary, i: int) -> Dictionary:
	return s["nodes"][i]


static func full_rules(s: Dictionary) -> bool:
	return s["rules"] == "full"


static func owner_name(s: Dictionary, o: int) -> String:
	if o == GLOOM:
		return "the Gloom"
	if o == WILD:
		return "wild critters"
	return s["players"][o]["name"]


static func owner_color(s: Dictionary, o: int) -> Color:
	if o == GLOOM:
		return GLOOM_COLOR
	if o == WILD:
		return WILD_COLOR
	return s["players"][o]["color"]


## Same side: teammates in Teams, everyone in co-op.
static func ally(s: Dictionary, a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or b < 0 or s["mode"] == "ffa":
		return false
	return s["players"][a]["team"] == s["players"][b]["team"]


## Are players a and b friends right now? A friendship only lasts while both
## friend planets (the pink loop) still belong to the two friends.
static func truce(s: Dictionary, a: int, b: int) -> bool:
	return friend_rounds(s, a, b) > 0


## Rounds of friendship left between a and b (0 = not friends).
static func friend_rounds(s: Dictionary, a: int, b: int) -> int:
	for t in s["truces"]:
		if ((t["a"] == a and t["b"] == b) or (t["a"] == b and t["b"] == a)) and _truce_ok(s, t):
			return t["until"] - s["round"] + 1
	return 0


static func _truce_ok(s: Dictionary, t: Dictionary) -> bool:
	return s["nodes"][t["na"]]["owner"] == t["a"] and s["nodes"][t["nb"]]["owner"] == t["b"]


static func peaceful(s: Dictionary, a: int, b: int) -> bool:
	return ally(s, a, b) or truce(s, a, b)


static func planets(s: Dictionary, p: int) -> int:
	var c := 0
	for nd in s["nodes"]:
		if nd["owner"] == p:
			c += 1
	return c


static func critters(s: Dictionary, p: int) -> int:
	var c := 0
	for nd in s["nodes"]:
		if nd["owner"] == p:
			c += nd["n"]
	return c


static func team_planets(s: Dictionary, team: int) -> int:
	var c := 0
	for pl in s["players"]:
		if pl["team"] == team:
			c += planets(s, pl["id"])
	return c


static func gloom_count(s: Dictionary) -> int:
	return planets(s, GLOOM)


static func golden_owned(s: Dictionary, p: int) -> int:
	var c := 0
	for nd in s["nodes"]:
		if nd["owner"] == p and nd["kind"] == "golden":
			c += 1
	return c


static func cities(s: Dictionary, p: int) -> int:
	var c := 0
	for nd in s["nodes"]:
		if nd["owner"] == p and nd["city"]:
			c += 1
	return c


static func city_cost(s: Dictionary, p: int) -> int:
	return CITY_COST + CITY_STEP * cities(s, p)


## Critters on n that can still hop this turn. One always stays behind, and
## critters that used up all their hops this turn are resting.
static func movable(s: Dictionary, n: int) -> int:
	var nd: Dictionary = s["nodes"][n]
	var resting := tired(nd)
	if s["round"] <= SLOW_ROUNDS:
		resting = hopped(nd)  # one hop only for now
	return maxi(0, nd["n"] - maxi(1, resting))


## Critters on this planet that used all their hops this turn (resting, zz).
static func tired(nd: Dictionary) -> int:
	var u: Array = nd["used"]
	return u[u.size() - 1]


## Critters on this planet that hopped at all this turn.
static func hopped(nd: Dictionary) -> int:
	var c := 0
	for v in nd["used"]:
		c += v
	return c


static func _zeros() -> Array:
	var a: Array = []
	a.resize(MAX_HOPS)
	a.fill(0)
	return a


## Take c critters off a planet to hop, freshest first. Returns how many of each
## kind left: lv[0] had not hopped yet, lv[i] had hopped i times.
static func _take(nd: Dictionary, c: int) -> Array:
	var u: Array = nd["used"]
	var lv := _zeros()
	var fresh: int = nd["n"] - hopped(nd)
	var t := mini(c, fresh)
	lv[0] = t
	c -= t
	for i in u.size() - 1:
		t = mini(c, u[i])
		lv[i + 1] = t
		u[i] -= t
		c -= t
	nd["n"] -= _sum(lv)
	return lv


## The hoppers land: each of them has now hopped once more.
static func _land(nd: Dictionary, lv: Array) -> void:
	for i in lv.size():
		nd["used"][i] += lv[i]
		nd["n"] += lv[i]


## Split k critters (freshest first) off a group of hoppers.
static func _split(lv: Array, k: int) -> Array:
	var out := _zeros()
	for i in lv.size():
		var t := mini(k, lv[i])
		out[i] = t
		lv[i] -= t
		k -= t
	return out


static func _sum(a: Array) -> int:
	var c := 0
	for v in a:
		c += v
	return c


## After critters were lost, make the hop counts fit again (fresh ones go first).
static func _fix(nd: Dictionary) -> void:
	var extra := hopped(nd) - int(nd["n"])
	var u: Array = nd["used"]
	for i in u.size():
		if extra <= 0:
			break
		var t := mini(extra, u[i])
		u[i] -= t
		extra -= t


## The friend planet that defends together with n (-1 if none).
static func friend_of(s: Dictionary, n: int) -> int:
	for t in s["truces"]:
		var other := -1
		if t["na"] == n:
			other = t["nb"]
		elif t["nb"] == n:
			other = t["na"]
		else:
			continue
		var a_ok: bool = s["nodes"][t["na"]]["owner"] == t["a"]
		var b_ok: bool = s["nodes"][t["nb"]]["owner"] == t["b"]
		if a_ok and b_ok:
			return other
	return -1


## Everyone defending n: its own critters plus its friend planet's.
static func defenders(s: Dictionary, n: int) -> int:
	var f := friend_of(s, n)
	return s["nodes"][n]["n"] + (s["nodes"][f]["n"] if f >= 0 else 0)


static func star_rush(s: Dictionary) -> bool:
	return s["round"] > s["max_rounds"] - RUSH_ROUNDS


static func income(s: Dictionary, p: int) -> int:
	var pl: Dictionary = s["players"][p]
	if pl["out"]:
		return 0
	var v := 2 + planets(s, p) / 2 + golden_owned(s, p)
	if pl["cadet"]:
		v += 1
	if star_rush(s):
		v += RUSH_BONUS
	return maxi(3, v)


## Homes, cities and Gloom nests get +1 when defending.
static func defends(nd: Dictionary) -> bool:
	if CITY_DEFENDS and nd["city"] and nd["owner"] >= 0:
		return true
	return (nd["kind"] == "home" and nd["owner"] >= 0) or (nd["kind"] == "nest" and nd["owner"] == GLOOM)


static func shielded(s: Dictionary, n: int, attacker: int) -> bool:
	var sh: int = s["nodes"][n]["shield"]
	return sh >= 0 and sh != attacker


## What sending from `from` to `to` would do: "move", "gift", "take", "dance" or "" (not allowed).
## move/gift send everyone who can go; take sends ONE critter to claim an empty planet.
static func send_kind(s: Dictionary, p: int, from: int, to: int) -> String:
	if s["over"] or s["phase"] != "go" or p != s["current"] or from == to:
		return ""
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	if a["owner"] != p or movable(s, from) < 1:
		return ""
	if not (to in s["adj"][from]):
		return ""
	if b["owner"] == p:
		return "move"
	if b["owner"] >= 0 and (ally(s, p, b["owner"]) or truce(s, p, b["owner"])):
		return "gift"
	if shielded(s, to, p) or (b["owner"] >= 0 and peace_time(s)):
		return ""
	if b["owner"] == WILD and b["n"] == 0:
		return "take"
	return "dance"


## The first rounds are peace time: grab wild planets, but leave other players alone.
static func peace_time(s: Dictionary) -> bool:
	return s["round"] <= PEACE_ROUNDS and s["mode"] != "coop"


static func targets(s: Dictionary, p: int, from: int) -> Dictionary:
	## node id -> send kind, for every place `from` can send to right now.
	var out := {}
	var cands: Array = s["adj"][from]
	for to in cands:
		var k := send_kind(s, p, from, to)
		if k != "":
			out[to] = k
	return out


## Crowd bonus for a dance-off: +1 for the bigger crowd, +2 when twice as big.
static func crowd_bonus(mine: int, theirs: int) -> int:
	if mine >= theirs * 2 and mine > theirs:
		return 2
	if mine > theirs:
		return 1
	return 0


## The dancers on each side and their bonuses, before rolling.
static func dance_info(s: Dictionary, from: int, to: int) -> Dictionary:
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	var att: int = movable(s, from)
	var dfn: int = defenders(s, to)
	var ab := crowd_bonus(att, dfn)
	var db := crowd_bonus(dfn, att)
	var home: bool = defends(b)
	if home:
		db += HOME_BONUS
	return {"att": att, "def": dfn, "ab": ab, "db": db, "home": home, "friend": friend_of(s, to),
		"lucky": a["owner"] >= 0 and s["players"][a["owner"]]["lucky"]}


# ---------------------------------------------------------------- step 1: place

static func can_place(s: Dictionary, p: int, n: int) -> bool:
	return not s["over"] and s["phase"] == "place" and p == s["current"] \
		and s["players"][p]["to_place"] > 0 and s["nodes"][n]["owner"] == p


static func place(s: Dictionary, p: int, n: int, count := 1) -> bool:
	if not can_place(s, p, n):
		return false
	var pl: Dictionary = s["players"][p]
	count = clampi(count, 1, pl["to_place"])
	s["nodes"][n]["n"] += count
	pl["to_place"] -= count
	_event(s, {"t": "place", "node": n, "count": count})
	if pl["to_place"] == 0:
		s["phase"] = "go"
	return true


## Build a city on your planet, paid for by critters already living there (one stays).
static func can_build(s: Dictionary, p: int, n: int) -> bool:
	if s["over"] or p != s["current"] or p < 0:
		return false
	var nd: Dictionary = s["nodes"][n]
	return nd["owner"] == p and not nd["city"] and nd["n"] > city_cost(s, p)


static func build_city(s: Dictionary, p: int, n: int, free := false) -> bool:
	var nd: Dictionary = s["nodes"][n]
	if free:
		if s["over"] or nd["owner"] != p or nd["city"]:
			return false
	elif not can_build(s, p, n):
		return false
	var cost := 0 if free else city_cost(s, p)
	nd["n"] -= cost
	_fix(nd)
	nd["city"] = true
	_event(s, {"t": "city", "node": n, "cost": cost})
	_log(s, "The %s built a city on %s! It will make %d critters every turn." % [owner_name(s, p), nd["name"], CITY_MAKES], p)
	return true


# ---------------------------------------------------------------- step 2: send

## Move / gift / take. For "dance" this does ONE roll (see roll()).
static func send(s: Dictionary, p: int, from: int, to: int) -> bool:
	var k := send_kind(s, p, from, to)
	if k == "":
		return false
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	match k:
		"move", "gift":
			var c := movable(s, from)
			_land(b, _take(a, c))
			_event(s, {"t": "move", "from": from, "to": to, "count": c, "owner": p})
			if k == "gift":
				_event(s, {"t": "text", "node": to, "text": "Gift!", "color": "ff8fb5"})
				_log(s, "%s gave %d critter%s to the %s!" % [owner_name(s, p), c, "" if c == 1 else "s", owner_name(s, b["owner"])], p)
		"take":
			_capture(s, p, from, to, WILD, 1)
		"dance":
			roll(s, p, from, to)
	return true


## One dance-off roll. The loser of the roll loses one critter. A befriended
## planet defends together with its friend; beat them both and you win both.
static func roll(s: Dictionary, p: int, from: int, to: int) -> Dictionary:
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	if a["owner"] != p or movable(s, from) < 1 or defenders(s, to) < 1 or not (to in s["adj"][from]):
		return {}
	if b["owner"] == p or peaceful(s, p, b["owner"]) or shielded(s, to, p):
		return {}
	var info := dance_info(s, from, to)
	var friend: int = info["friend"]
	var rng := _rng(s)
	var ad := rng.randi_range(1, 6)
	var ad2 := 0
	if info["lucky"]:
		ad2 = rng.randi_range(1, 6)
	var dd := rng.randi_range(1, 6)
	_save_rng(s, rng)
	var at: int = maxi(ad, ad2) + info["ab"]
	var dt: int = dd + info["db"]
	var tie := at == dt and TIES == "none"
	var att_wins := at > dt or (at == dt and TIES == "att")
	var hit := to
	if tie:
		hit = -1  # a tie: nobody loses, roll again
	elif att_wins:
		# friends share the losses: the bigger crowd loses one
		if friend >= 0 and s["nodes"][friend]["n"] > b["n"]:
			hit = friend
		s["nodes"][hit]["n"] -= 1
		_fix(s["nodes"][hit])
	else:
		hit = from
		a["n"] -= 1
		_fix(a)
	var left := defenders(s, to)
	var res := {"t": "roll", "from": from, "to": to, "att_owner": p, "def_owner": b["owner"],
		"ad": ad, "ad2": ad2, "dd": dd, "ab": info["ab"], "db": info["db"], "home": info["home"],
		"att_total": at, "def_total": dt, "att_wins": att_wins, "tie": tie, "captured": false, "hit": hit,
		"friend": friend, "att_left": movable(s, from), "def_left": left}
	if left <= 0:
		res["captured"] = true
		res["def_left"] = 0
		var prev: int = b["owner"]
		_event(s, res)
		# the fog spreads: only half of the Gloom moves in
		var cnt := maxi(1, movable(s, from) / 2) if p == GLOOM else -1
		_capture(s, p, from, to, prev, cnt, friend)
	else:
		_event(s, res)
	return res


## Keep rolling until the planet is won or only one critter is left behind.
static func roll_all(s: Dictionary, p: int, from: int, to: int) -> Dictionary:
	var last := {}
	var guard := 0
	while guard < 200:
		guard += 1
		var r := roll(s, p, from, to)
		if r.is_empty():
			break
		last = r
		if r["captured"] or r["att_left"] <= 0:
			break
	return last


## Win `to` with everyone who can hop (or `count` critters). If `friend` >= 0 the
## friend planet is won too: half the dancers go there (at least one new friend joins).
static func _capture(s: Dictionary, p: int, from: int, to: int, prev := -99, count := -1, friend := -1) -> void:
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	if prev == -99:
		prev = b["owner"]
	var moving: int = movable(s, from) if count < 0 else mini(count, movable(s, from))
	var lv := _take(a, moving)
	var fprev := -99
	var fcount := 0
	if friend >= 0:
		fprev = s["nodes"][friend]["owner"]
		fcount = moving / 2 if moving >= 2 else 0
	var flv := _split(lv, fcount)
	b["owner"] = p
	b["n"] = 0
	b["used"] = _zeros()
	_land(b, lv)
	b["shield"] = -1
	if CITY_FALLS and b["city"] and prev >= 0:
		b["city"] = false
		_event(s, {"t": "text", "node": to, "text": "City lost!", "color": "ffb36b"})
		_log(s, "The city on %s was knocked down!" % b["name"], prev)
	_event(s, {"t": "move", "from": from, "to": to, "count": moving - fcount, "owner": p})
	_event(s, {"t": "capture", "node": to, "owner": p, "prev": prev})
	if friend >= 0:
		var f: Dictionary = s["nodes"][friend]
		f["owner"] = p
		f["n"] = 0
		f["used"] = _zeros()
		_land(f, flv)
		if f["n"] == 0:
			f["n"] = 1  # at least one new friend joins
			f["used"][f["used"].size() - 1] = 1
		f["shield"] = -1
		if fcount > 0:
			_event(s, {"t": "move", "from": from, "to": friend, "count": fcount, "owner": p})
		_event(s, {"t": "capture", "node": friend, "owner": p, "prev": fprev})
		_log(s, "The %s beat the friends and won BOTH %s and %s!" % [owner_name(s, p).trim_prefix("the "), b["name"], f["name"]], p)
		if fprev >= 0 and fprev != prev and planets(s, fprev) == 0:
			s["players"][fprev]["out"] = true
			_log(s, "The %s lost their last planet!" % owner_name(s, fprev), fprev)
	if p >= 0:
		s["players"][p]["captured"] = true
		var what := "won over"
		if prev == GLOOM:
			what = "chased the Gloom off"
		elif prev == WILD:
			what = "moved onto"
		var tail := "" if prev < 0 else " from the %s" % owner_name(s, prev)
		_log(s, "%s %s %s%s!" % [owner_name(s, p), what, b["name"], tail], p)
		if b["kind"] == "mystery":
			_open_mystery(s, p, to)
	else:
		_log(s, "The Gloom swallowed %s!" % b["name"], -1)
	if prev >= 0 and planets(s, prev) == 0:
		s["players"][prev]["out"] = true
		var back := "" if s["players"][prev]["comeback"] else " They will bounce back next turn!"
		_log(s, "The %s lost their last planet!%s" % [owner_name(s, prev), back], prev)
	_check_win(s)


static func _open_mystery(s: Dictionary, p: int, n: int) -> void:
	var nd: Dictionary = s["nodes"][n]
	nd["kind"] = "planet"
	var rng := _rng(s)
	var r := rng.randi_range(0, 2)
	_save_rng(s, rng)
	var pl: Dictionary = s["players"][p]
	var txt := ""
	if r == 2 and full_rules(s) and pl["cards"].size() < MAX_HAND:
		var c := _draw_card(s)
		pl["cards"].append(c)
		txt = "found a %s card" % CARDS[c]["name"]
	elif r == 1:
		for o in s["nodes"]:
			if o["owner"] == p:
				o["n"] += 1
				_event(s, {"t": "text", "node": o["id"], "text": "+1", "color": "ffe96b"})
		txt = "found a party: +1 critter on every planet"
	else:
		nd["n"] += 3
		txt = "found 3 lost critters"
	_event(s, {"t": "mystery", "node": n, "text": txt})
	_log(s, "Surprise! The %s %s on %s!" % [pl["name"], txt, nd["name"]], p)


# ---------------------------------------------------------------- step 3: cards & friends

static func can_play(s: Dictionary, p: int, idx: int, n := -1) -> bool:
	if s["over"] or p != s["current"] or not full_rules(s):
		return false
	var pl: Dictionary = s["players"][p]
	if idx < 0 or idx >= pl["cards"].size():
		return false
	var c: Dictionary = CARDS[pl["cards"][idx]]
	if pl["cards"][idx] == "city":
		return n >= 0 and s["nodes"][n]["owner"] == p and not s["nodes"][n]["city"]
	if c["target"] == "own":
		return n >= 0 and s["nodes"][n]["owner"] == p
	if pl["cards"][idx] == "dice":
		return not pl["lucky"]
	return true


static func play_card(s: Dictionary, p: int, idx: int, n := -1) -> bool:
	if not can_play(s, p, idx, n):
		return false
	var pl: Dictionary = s["players"][p]
	var c: String = pl["cards"][idx]
	pl["cards"].remove_at(idx)
	match c:
		"rocket":
			s["nodes"][n]["n"] += 3
			_event(s, {"t": "text", "node": n, "text": "+3 Rocket!", "color": "ffe96b"})
		"dice":
			pl["lucky"] = true
		"shield":
			s["nodes"][n]["shield"] = p
			_event(s, {"t": "text", "node": n, "text": "Force Field!", "color": "9ff5ff"})
		"city":
			build_city(s, p, n, true)
	_event(s, {"t": "card", "card": c, "node": n})
	_log(s, "%s played %s!" % [pl["name"], CARDS[c]["name"]], p)
	return true


static func _draw_card(s: Dictionary) -> String:
	var rng := _rng(s)
	var c: String = CARD_ORDER[rng.randi_range(0, CARD_ORDER.size() - 1)]
	_save_rng(s, rng)
	return c


## Befriend (everyone-for-themselves): click a rival's planet next to yours and ask.
## If they say yes: no dance-offs between you for FRIEND_ROUNDS rounds, and the two
## planets defend together. One ask per turn.
static func can_befriend(s: Dictionary, p: int, from: int, to: int) -> bool:
	if s["over"] or s["mode"] != "ffa" or p != s["current"] or s["phase"] != "go":
		return false
	if not (to in s["adj"][from]) or s["nodes"][from]["owner"] != p:
		return false
	var q: int = s["nodes"][to]["owner"]
	if q < 0 or q == p or s["players"][q]["out"] or s["players"][p]["asked"]:
		return false
	if truce(s, p, q) or friend_of(s, from) >= 0 or friend_of(s, to) >= 0:
		return false
	return true


static func befriend(s: Dictionary, p: int, from: int, to: int) -> bool:
	if not can_befriend(s, p, from, to):
		return false
	var q: int = s["nodes"][to]["owner"]
	s["players"][p]["asked"] = true
	s["truces"].append({"a": p, "b": q, "na": from, "nb": to, "until": s["round"] + FRIEND_ROUNDS - 1})
	_event(s, {"t": "friends", "a": from, "b": to})
	_log(s, "The %s and the %s are friends! No dance-offs between them for %d rounds, and %s and %s defend together." % [
		owner_name(s, p), owner_name(s, q), FRIEND_ROUNDS, s["nodes"][from]["name"], s["nodes"][to]["name"]], p)
	return true


## Mark that p asked this turn (and was told no).
static func befriend_declined(s: Dictionary, p: int, q: int) -> void:
	s["players"][p]["asked"] = true
	_log(s, "The %s said \"no thanks\" to being friends with the %s." % [owner_name(s, q), owner_name(s, p)], q)


# ---------------------------------------------------------------- turns

static func start_turn(s: Dictionary) -> void:
	var guard := 0
	while not s["over"] and guard < 10:
		guard += 1
		var p: int = s["current"]
		var pl: Dictionary = s["players"][p]
		if pl["out"] and not pl["comeback"]:
			_comeback(s, p)
		if pl["out"]:
			_advance(s)
			continue
		for nd in s["nodes"]:
			nd["used"] = _zeros()
			if nd["shield"] == p:
				nd["shield"] = -1
			if nd["owner"] == p and nd["city"]:
				nd["n"] += CITY_MAKES
				_event(s, {"t": "text", "node": nd["id"], "text": "+%d City" % CITY_MAKES, "color": "ffd27a"})
		pl["lucky"] = false
		pl["captured"] = false
		pl["asked"] = false
		pl["to_place"] = income(s, p)
		s["phase"] = "place"
		return


static func _comeback(s: Dictionary, p: int) -> void:
	var pl: Dictionary = s["players"][p]
	pl["comeback"] = true
	var free: Array = []
	for nd in s["nodes"]:
		if nd["owner"] == WILD and nd["n"] == 0:
			free.append(nd["id"])
	if free.is_empty():
		for nd in s["nodes"]:
			if nd["owner"] == WILD:
				free.append(nd["id"])
	if free.is_empty():
		_log(s, "The %s have nowhere to land. They cheer from the sidelines!" % pl["name"], p)
		return
	var rng := _rng(s)
	var n: int = free[rng.randi_range(0, free.size() - 1)]
	_save_rng(s, rng)
	s["nodes"][n]["owner"] = p
	s["nodes"][n]["n"] = 4
	pl["out"] = false
	_event(s, {"t": "capture", "node": n, "owner": p, "prev": WILD})
	_event(s, {"t": "text", "node": n, "text": "Bounce back!", "color": "ffe96b"})
	_log(s, "The %s bounced back on %s!" % [pl["name"], s["nodes"][n]["name"]], p)


static func end_turn(s: Dictionary) -> void:
	if s["over"]:
		return
	var p: int = s["current"]
	var pl: Dictionary = s["players"][p]
	# leftover critters land at home (or the biggest planet) so nothing is wasted
	if pl["to_place"] > 0:
		var n := _biggest(s, p)
		if n >= 0:
			s["nodes"][n]["n"] += pl["to_place"]
		pl["to_place"] = 0
	# on the last round, your score is counted when YOUR turn ends, so nobody gets the last word
	if s["round"] >= s["max_rounds"] and FINAL_SNAPSHOT:
		pl["final"] = [planets(s, p), critters(s, p)]
	if full_rules(s) and pl["captured"] and pl["cards"].size() < MAX_HAND:
		var c := _draw_card(s)
		pl["cards"].append(c)
		_event(s, {"t": "newcard", "card": c, "player": p})
		_log(s, "The %s found a Lucky Card: %s!" % [pl["name"], CARDS[c]["name"]], p)
	_advance(s)
	if not s["over"]:
		start_turn(s)


static func _advance(s: Dictionary) -> void:
	s["current"] += 1
	if s["current"] >= s["players"].size():
		s["current"] = 0
		_end_round(s)


static func _biggest(s: Dictionary, p: int) -> int:
	var home: int = s["players"][p]["home"]
	if s["nodes"][home]["owner"] == p:
		return home
	var best := -1
	for nd in s["nodes"]:
		if nd["owner"] == p and (best < 0 or nd["n"] > s["nodes"][best]["n"]):
			best = nd["id"]
	return best


static func _end_round(s: Dictionary) -> void:
	if s["gloom"] and gloom_count(s) > 0 and not (s["tutorial"] and s["round"] < 3):
		_gloom_turn(s)
		if s["over"]:
			return
		if gloom_count(s) >= s["gloom_limit"]:
			_finish(s, "gloom", [])
			_log(s, "The Gloom got too big! Everybody loses this time.", -1)
			return
	# friendships run out
	var keep: Array = []
	for t in s["truces"]:
		if not _truce_ok(s, t):
			continue  # one of the friend planets changed hands: the friendship is gone
		if t["until"] > s["round"]:
			keep.append(t)
		else:
			_log(s, "The friendship between the %s and the %s is over. Watch out!" % [owner_name(s, t["a"]), owner_name(s, t["b"])], -1)
			for k in ["na", "nb"]:
				var nd: Dictionary = s["nodes"][t[k]]
				if nd["owner"] >= 0 and nd["n"] <= 0:
					nd["owner"] = WILD  # nobody left to hold it
					nd["n"] = 0
					nd["used"] = _zeros()
	s["truces"] = keep
	if s["round"] >= s["max_rounds"]:
		_finish_by_count(s)
		return
	s["round"] += 1
	_cosmic(s)


# ---------------------------------------------------------------- the Gloom

static func gloom_income(s: Dictionary) -> int:
	var t := _gloom_tune(s)
	return int(t["base"]) + (s["round"] - 1) / int(t["div"])


static func _gloom_turn(s: Dictionary) -> void:
	var t := _gloom_tune(s)
	var inc := gloom_income(s)
	# place everything on the Gloom planet next to the weakest prey
	var best := _gloom_pick(s, true)
	if best.is_empty():
		return
	s["nodes"][best["from"]]["n"] += inc
	_event(s, {"t": "place", "node": best["from"], "count": inc, "gloom": true})
	_log(s, "The Gloom grew %d more fog critters." % inc, -1)
	# fractional attacks: 1.5 means 1, 2, 1, 2, ...
	var atk: float = float(t["attacks"])
	var count := int(floor(atk * s["round"])) - int(floor(atk * (s["round"] - 1)))
	for k in count:
		var pick := _gloom_pick(s, false)
		if pick.is_empty():
			break
		var tgt: Dictionary = s["nodes"][pick["to"]]
		if tgt["owner"] == WILD and tgt["n"] == 0:
			# empty planet: the fog just drifts in
			_capture(s, GLOOM, pick["from"], pick["to"], WILD, maxi(1, movable(s, pick["from"]) / 2))
		else:
			roll_all(s, GLOOM, pick["from"], pick["to"])
		if s["over"]:
			return


## Gloom's choice: its planet with the best odds against a neighbour.
static func _gloom_pick(s: Dictionary, any: bool) -> Dictionary:
	var best := {}
	var best_score := -999.0
	for nd in s["nodes"]:
		if nd["owner"] != GLOOM:
			continue
		for to in s["adj"][nd["id"]]:
			var b: Dictionary = s["nodes"][to]
			if b["owner"] == GLOOM or shielded(s, to, GLOOM) or (not any and movable(s, nd["id"]) < 1):
				continue
			var att: int = movable(s, nd["id"])
			var dfn: int = defenders(s, to) + (1 if defends(b) else 0)
			if not any and att <= dfn:
				continue
			var score := float(att - dfn)
			if b["owner"] >= 0:
				score += 0.5  # it likes players' planets best
			if b["kind"] == "home":
				score -= 1.5
			if score > best_score:
				best_score = score
				best = {"from": nd["id"], "to": to}
	return best


# ---------------------------------------------------------------- round events

const COSMIC := [
	["calm", 3, "Calm skies", "A quiet night in space."],
	["meteor", 1, "Meteor Shower", "Everyone gets +2 critters at home!"],
	["comet", 2, "Lucky Comet", "The %s get +4 critters!"],
	["bloom", 1, "Wild Bloom", "Every wild planet gets +1 wild critter."],
	["glow", 1, "Golden Glow", "Golden planets get +2 critters."],
	["storm", 1, "Gloom Storm", "The Gloom gets +3 fog critters!"],
]


static func _cosmic(s: Dictionary) -> void:
	if s["tutorial"]:
		s["cosmic"] = {}
		return
	var pool: Array = []
	for c in COSMIC:
		if c[0] == "storm" and (not s["gloom"] or gloom_count(s) == 0):
			continue
		for w in c[1]:
			pool.append(c)
	var rng := _rng(s)
	var c: Array = pool[rng.randi_range(0, pool.size() - 1)]
	var text: String = c[3]
	match c[0]:
		"meteor":
			for pl in s["players"]:
				var n := _biggest(s, pl["id"])
				if n >= 0 and not pl["out"]:
					s["nodes"][n]["n"] += 2
					_event(s, {"t": "text", "node": n, "text": "+2 Meteor!", "color": "ffe96b"})
		"comet":
			var least := 999
			var who: Array = []
			for pl in s["players"]:
				if pl["out"]:
					continue
				var k := planets(s, pl["id"])
				if k < least:
					least = k
					who = [pl["id"]]
				elif k == least:
					who.append(pl["id"])
			if who.is_empty():
				c = COSMIC[0]
				text = c[3]
			else:
				var lucky: int = who[rng.randi_range(0, who.size() - 1)]
				var n := _biggest(s, lucky)
				s["nodes"][n]["n"] += 4
				_event(s, {"t": "text", "node": n, "text": "+4 Comet!", "color": "ffe96b"})
				text = text % owner_name(s, lucky)
		"bloom":
			for nd in s["nodes"]:
				if nd["owner"] == WILD:
					nd["n"] += 1
		"glow":
			for nd in s["nodes"]:
				if nd["kind"] == "golden":
					nd["n"] += 2
					_event(s, {"t": "text", "node": nd["id"], "text": "+2 Glow!", "color": "ffd94a"})
		"storm":
			var g := -1
			for nd in s["nodes"]:
				if nd["owner"] == GLOOM and (g < 0 or nd["n"] > s["nodes"][g]["n"]):
					g = nd["id"]
			if g >= 0:
				s["nodes"][g]["n"] += 3
				_event(s, {"t": "text", "node": g, "text": "+3 Storm", "color": "b9b0e0"})
	_save_rng(s, rng)
	s["cosmic"] = {"id": c[0], "name": c[2], "text": text}
	if star_rush(s) and s["round"] == s["max_rounds"] - RUSH_ROUNDS + 1:
		_log(s, "STAR RUSH! Last %d rounds: everyone gets +%d critters each turn!" % [RUSH_ROUNDS, RUSH_BONUS], -1)
	if c[0] != "calm":
		_log(s, "Round %d: %s! %s" % [s["round"], c[2], text], -1)


# ---------------------------------------------------------------- winning

static func _check_win(s: Dictionary) -> void:
	if s["over"]:
		return
	if s["mode"] == "coop":
		if s["gloom"] and gloom_count(s) == 0:
			_finish(s, "win", range(s["players"].size()))
			_log(s, "The Gloom is gone! The galaxy is saved!", -1)
		return
	# does one player (or one team) own every planet?
	var owners := {}
	for nd in s["nodes"]:
		var o: int = nd["owner"]
		if o >= 0 and s["mode"] == "teams":
			o = s["players"][o]["team"]
		owners[o] = true
	if owners.size() == 1 and int(owners.keys()[0]) >= 0:
		var k: int = owners.keys()[0]
		_finish(s, "conquer", _members(s, k))
		return
	# is only one player (or team) still in the game?
	var alive := {}
	for pl in s["players"]:
		if not pl["out"] or not pl["comeback"]:
			alive[pl["team"]] = true
	if alive.size() == 1:
		_finish(s, "last", _members(s, alive.keys()[0]))


static func _members(s: Dictionary, team_or_player: int) -> Array:
	var out: Array = []
	for pl in s["players"]:
		if pl["team"] == team_or_player:
			out.append(pl["id"])
	return out


static func _finish_by_count(s: Dictionary) -> void:
	if s["mode"] == "coop":
		_finish(s, "clock", [])
		_log(s, "The Star Clock ran out before the Gloom was gone.", -1)
		return
	var best := -1
	var best_c := -1
	var winners: Array = []
	var keys: Array = []
	if s["mode"] == "teams":
		keys = [0, 1]
	else:
		for pl in s["players"]:
			keys.append(pl["id"])
	for k in keys:
		var pc := 0
		var cc := 0
		for pid in _members(s, k):
			var fin: Array = s["players"][pid].get("final", [planets(s, pid), critters(s, pid)])
			pc += fin[0]
			cc += fin[1]
		if pc > best or (pc == best and cc > best_c):
			best = pc
			best_c = cc
			winners = [k]
		elif pc == best and cc == best_c:
			winners.append(k)
	var out: Array = []
	for k in winners:
		out += _members(s, k)
	_finish(s, "clock", out)


static func _finish(s: Dictionary, result: String, winners: Array) -> void:
	s["over"] = true
	s["result"] = result
	s["winners"] = winners


# ---------------------------------------------------------------- helpers

static func dist_from(s: Dictionary, start: int) -> Array:
	return MapGen.bfs(s["adj"], start)


static func _rng(s: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s["rng_seed"]
	if s["rng_state"] != 0:
		r.state = s["rng_state"]
	return r


static func _save_rng(s: Dictionary, r: RandomNumberGenerator) -> void:
	s["rng_state"] = r.state


static func _log(s: Dictionary, text: String, p: int) -> void:
	s["log_seq"] += 1
	s["log"].append({"text": text, "p": p, "round": s["round"], "seq": s["log_seq"]})
	if s["log"].size() > 60:
		s["log"].pop_front()


static func _event(s: Dictionary, e: Dictionary) -> void:
	s["events"].append(e)
