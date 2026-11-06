extends RefCounted
## Greedy computer player. next_command() returns one command at a time so the
## same code drives computer seats, the Hint button and Cadet ideas.

const Rules = preload("res://scripts/rules.gd")

## How keen computers are on cities (the sim tunes / compares this). 0 = never build.
static var CITY_WANT := 1.0
static var FRIENDLY := true  # (sim switch) do computers ask to be friends?
static var NEED := 1           # extra dancers a computer wants before attacking a player
static var DEF_PENALTY := 0.1 # how much a big defending crowd puts it off


static func next_command(s: Dictionary, p: int) -> Dictionary:
	if s["over"] or s["current"] != p:
		return {"cmd": "end"}
	var pl: Dictionary = s["players"][p]
	if s["phase"] == "place":
		var city := _city_plan(s, p, pl["to_place"])
		if city >= 0:
			return {"cmd": "place", "node": city, "count": pl["to_place"], "why": "city"}
		return {"cmd": "place", "node": _best_stage(s, p), "count": pl["to_place"]}
	var card := _best_card(s, p)
	if not card.is_empty():
		return card
	var build := _best_build(s, p)
	if build >= 0:
		return {"cmd": "build", "node": build}
	var atk := _best_attack(s, p)
	if not atk.is_empty():
		var kind := Rules.send_kind(s, p, atk["from"], atk["to"])
		return {"cmd": "attack" if kind == "dance" else "send", "from": atk["from"], "to": atk["to"], "kind": kind}
	var fr := _best_friend(s, p)
	if not fr.is_empty():
		return fr
	var mv := _best_fortify(s, p)
	if not mv.is_empty():
		return mv
	return {"cmd": "end"}


static func apply(s: Dictionary, c: Dictionary) -> bool:
	var p: int = s["current"]
	match c["cmd"]:
		"place":
			return Rules.place(s, p, c["node"], c.get("count", 1))
		"build":
			return Rules.build_city(s, p, c["node"])
		"card":
			return Rules.play_card(s, p, c["idx"], c.get("node", -1))
		"attack":
			return not Rules.roll_all(s, p, c["from"], c["to"]).is_empty()
		"send":
			return Rules.send(s, p, c["from"], c["to"])
		"befriend":
			var q: int = s["nodes"][c["to"]]["owner"]
			if q >= 0 and s["players"][q]["ai"] and accepts_friend(s, q, p):
				return Rules.befriend(s, p, c["from"], c["to"])
			Rules.befriend_declined(s, p, q)
			return true
		"end":
			Rules.end_turn(s)
			return true
	return false


## Would a computer say yes to being friends? Yes, unless the asker is winning.
static func accepts_friend(s: Dictionary, ai: int, asker: int) -> bool:
	return Rules.planets(s, asker) <= Rules.planets(s, ai) + 1


# ---------------------------------------------------------------- scoring

static func _hostile(s: Dictionary, p: int, n: int) -> bool:
	var o: int = s["nodes"][n]["owner"]
	if o == p:
		return false
	if o >= 0 and Rules.peaceful(s, p, o):
		return false
	return true


static func _leader_planets(s: Dictionary) -> int:
	var lead := 0
	for q in s["players"]:
		lead = maxi(lead, Rules.planets(s, q["id"]))
	return lead


static func _value(s: Dictionary, p: int, to: int) -> float:
	var b: Dictionary = s["nodes"][to]
	var v := 1.0
	match b["kind"]:
		"golden":
			v = 3.0
		"mystery":
			v = 2.5
		"home":
			v = 2.0
		"nest":
			v = 1.5
	if b["city"]:
		v += 2.0
	if Rules.friend_of(s, to) >= 0:
		v += 1.0  # two planets for one dance-off
	match b["owner"]:
		Rules.WILD:
			v += 0.3
		Rules.GLOOM:
			# the bigger the Gloom gets, the more everyone should fight it
			v += 0.5 + 4.0 * float(Rules.gloom_count(s)) / maxf(1.0, s["gloom_limit"])
			if s["mode"] == "coop":
				v += 2.0  # chasing the Gloom out is the whole point
		_:
			if Rules.planets(s, b["owner"]) >= _leader_planets(s):
				v += 0.6
	return v


## Biggest hostile crowd next to n (what might attack it next turn).
static func _threat(s: Dictionary, p: int, n: int) -> int:
	var t := 0
	for m in s["adj"][n]:
		var o: int = s["nodes"][m]["owner"]
		if o == Rules.WILD or not _hostile(s, p, m):
			continue
		t = maxi(t, s["nodes"][m]["n"] - 1)
	return t


static func _attack_score(s: Dictionary, p: int, from: int, to: int, att: int) -> float:
	var b: Dictionary = s["nodes"][to]
	var dfn: int = Rules.defenders(s, to) + (1 if Rules.defends(b) else 0)
	var need := NEED if b["owner"] >= 0 or b["owner"] == Rules.GLOOM else mini(1, NEED)
	if b["owner"] == Rules.WILD and b["n"] == 0:
		need = 0
		dfn = 0
	if att < 1 or att < dfn + need:
		return -99.0
	var score := _value(s, p, to) + 0.25 * (att - dfn) - DEF_PENALTY * dfn
	var a: Dictionary = s["nodes"][from]
	if (a["kind"] == "home" or a["city"]) and _threat(s, p, from) >= 2:
		score -= 1.2
	return score


static func _best_attack(s: Dictionary, p: int) -> Dictionary:
	var best := {}
	var best_score := 0.4
	for nd in s["nodes"]:
		if nd["owner"] != p or Rules.movable(s, nd["id"]) < 1:
			continue
		var tg := Rules.targets(s, p, nd["id"])
		for to in tg:
			if tg[to] == "move" or tg[to] == "gift":
				continue
			var sc := _attack_score(s, p, nd["id"], to, Rules.movable(s, nd["id"]))
			if sc > best_score:
				best_score = sc
				best = {"from": nd["id"], "to": to, "score": sc}
	return best


## Where to put this turn's new critters.
static func _best_stage(s: Dictionary, p: int) -> int:
	var extra: int = s["players"][p]["to_place"]
	var best := -1
	var best_score := -999.0
	for nd in s["nodes"]:
		if nd["owner"] != p:
			continue
		var n: int = nd["id"]
		var sc := -50.0
		for to in s["adj"][n]:
			if not _hostile(s, p, to) or Rules.shielded(s, to, p):
				continue
			sc = maxf(sc, _attack_score(s, p, n, to, Rules.movable(s, n) + extra))
		# protect a planet that is in danger
		var danger: int = _threat(s, p, n) - nd["n"]
		if danger > 0:
			sc = maxf(sc, 1.0 + danger * 0.5 + (1.5 if nd["kind"] == "home" or nd["city"] else 0.0))
		if sc > best_score:
			best_score = sc
			best = n
	if best < 0:
		best = s["players"][p]["home"]
	return best


# ---------------------------------------------------------------- cities

static func _rounds_left(s: Dictionary) -> int:
	return s["max_rounds"] - s["round"]


## How good a city on n would be (<= 0: not worth it). `extra` = critters we could add first.
static func _city_score(s: Dictionary, p: int, n: int, extra: int) -> float:
	if CITY_WANT <= 0.0:
		return -1.0
	var nd: Dictionary = s["nodes"][n]
	if nd["owner"] != p or nd["city"]:
		return -1.0
	var cost := Rules.city_cost(s, p)
	if nd["n"] + extra <= cost:
		return -1.0
	var left: int = nd["n"] + extra - cost
	var threat := _threat(s, p, n)
	if threat >= left + 2:
		return -1.0  # it would be taken right away
	var payback: float = float(Rules.CITY_MAKES * _rounds_left(s)) - float(cost) * 1.6
	var sc := payback * CITY_WANT - threat * 0.6
	if nd["kind"] == "home" or nd["kind"] == "golden":
		sc += 1.0
	return sc


static func _best_build(s: Dictionary, p: int) -> int:
	var best := -1
	var best_sc := 2.0
	for nd in s["nodes"]:
		if not Rules.can_build(s, p, nd["id"]):
			continue
		var sc := _city_score(s, p, nd["id"], 0)
		if sc > best_sc:
			best_sc = sc
			best = nd["id"]
	return best


## In the place step: put everything on one planet so a city can go up there, if
## that beats attacking this turn.
static func _city_plan(s: Dictionary, p: int, extra: int) -> int:
	var atk_best := -50.0
	var stage := _best_stage(s, p)
	for to in s["adj"][stage]:
		if _hostile(s, p, to):
			atk_best = maxf(atk_best, _attack_score(s, p, stage, to, Rules.movable(s, stage) + extra))
	var best := -1
	var best_sc := maxf(2.0, atk_best * 1.5)
	for nd in s["nodes"]:
		var sc := _city_score(s, p, nd["id"], extra)
		if sc > best_sc:
			best_sc = sc
			best = nd["id"]
	return best


# ---------------------------------------------------------------- friends

## Ask a neighbour to be friends when they could hurt us and they're not the leader.
static func _best_friend(s: Dictionary, p: int) -> Dictionary:
	if not FRIENDLY or s["mode"] != "ffa" or s["players"][p]["asked"]:
		return {}
	var alive := 0
	for q in s["players"]:
		if not q["out"]:
			alive += 1
	var gloom_big: bool = s["gloom"] and Rules.gloom_count(s) >= s["gloom_limit"] - 3
	if alive < 3 and not gloom_big:
		return {}
	var lead := _leader_planets(s)
	for nd in s["nodes"]:
		if nd["owner"] != p:
			continue
		for to in s["adj"][nd["id"]]:
			var b: Dictionary = s["nodes"][to]
			var q: int = b["owner"]
			if q < 0 or q == p or not Rules.can_befriend(s, p, nd["id"], to):
				continue
			if Rules.send_kind(s, p, nd["id"], to) != "dance":
				continue  # a person asks through the pop-up, which needs a critter that can hop
			if Rules.planets(s, q) >= lead and alive >= 3:
				continue  # don't make friends with the leader
			if b["n"] - 1 >= nd["n"]:
				return {"cmd": "befriend", "from": nd["id"], "to": to}
	return {}


# ---------------------------------------------------------------- moving

static func _best_fortify(s: Dictionary, p: int) -> Dictionary:
	## Walk idle critters from safe inside planets toward the front (one hop per turn).
	var front := {}
	for nd in s["nodes"]:
		if nd["owner"] != p:
			continue
		for m in s["adj"][nd["id"]]:
			if _hostile(s, p, m):
				front[nd["id"]] = true
	if front.is_empty():
		return {}
	var dist := _front_dist(s, p, front)
	for nd in s["nodes"]:
		var n: int = nd["id"]
		if nd["owner"] != p or Rules.movable(s, n) < 1 or front.has(n):
			continue
		if nd["city"] and _city_score(s, p, n, 0) > -1.0 and Rules.movable(s, n) < 2:
			continue
		var best_m := -1
		for m in s["adj"][n]:
			if s["nodes"][m]["owner"] == p and dist.get(m, 99) < dist.get(n, 99):
				if best_m < 0 or dist[m] < dist[best_m]:
					best_m = m
		if best_m >= 0:
			return {"cmd": "send", "from": n, "to": best_m, "kind": "move"}
	return {}


static func _front_dist(s: Dictionary, p: int, front: Dictionary) -> Dictionary:
	var dist := {}
	var q: Array = []
	for f in front:
		dist[f] = 0
		q.append(f)
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
		for v in s["adj"][u]:
			if s["nodes"][v]["owner"] == p and not dist.has(v):
				dist[v] = dist[u] + 1
				q.append(v)
	return dist


static func _best_card(s: Dictionary, p: int) -> Dictionary:
	var pl: Dictionary = s["players"][p]
	if not Rules.full_rules(s):
		return {}
	var cards: Array = pl["cards"]
	for i in cards.size():
		match cards[i]:
			"shield":
				var home: int = pl["home"]
				if s["nodes"][home]["owner"] == p and _threat(s, p, home) >= s["nodes"][home]["n"]:
					return {"cmd": "card", "idx": i, "node": home, "card": "shield"}
			"rocket":
				var atk := _best_attack(s, p)
				if not atk.is_empty() and Rules.send_kind(s, p, atk["from"], atk["to"]) == "dance":
					return {"cmd": "card", "idx": i, "node": atk["from"], "card": "rocket"}
			"dice":
				if not pl["lucky"]:
					var atk2 := _best_attack(s, p)
					if not atk2.is_empty() and Rules.send_kind(s, p, atk2["from"], atk2["to"]) == "dance":
						return {"cmd": "card", "idx": i, "card": "dice"}
			"city":
				var best := -1
				var best_sc := -999.0
				for nd in s["nodes"]:
					if nd["owner"] != p or nd["city"]:
						continue
					var sc: float = nd["n"] - _threat(s, p, nd["id"]) * 1.5 + (2.0 if nd["kind"] == "home" else 0.0)
					if sc > best_sc:
						best_sc = sc
						best = nd["id"]
				if best >= 0:
					return {"cmd": "card", "idx": i, "node": best, "card": "city"}
	return {}
