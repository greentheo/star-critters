extends RefCounted
## Generates a mirror-symmetric galaxy so every starting spot is equally good.
## 4-fold (mirror X and Y) for 4 players, 3-fold (rotate 120, stretched to fill the
## screen) for 3 players, 2-fold (rotate 180) for 1-2 players.

## Galaxy sizes: the canvas grows and more planets are added; the board zooms out to fit.
const SIZES := {"normal": 1.0, "big": 1.3, "huge": 1.6}
static var W := 1600.0
static var H := 900.0
static var CX := 800.0
static var CY := 450.0
static var SX := 1.0  # horizontal stretch of 3-fold maps
static var LAST_FAIL := ""
const MIN_DIST := 165.0
const MAX_LANE := 330.0
const MAX_DEG := 4
# Natural spacing (mood lab picks): the spacing swells and shrinks across the galaxy so planets
# gather in loose clumps (like a Poisson-disk sky, not a grid), planets vary a little in size,
# and lanes follow the "relative neighbourhood" rule (fewer, more natural lanes). Every value is
# shared by a whole symmetric group, so all starts stay equally good.
static var CLUMP := 0.8          # 0 = even spacing
static var SIZE_VARIETY := 0.24  # planets are 76%..124% of normal size
static var LANES := "rng"        # "rng" (fewer) or "greedy" (the v3 lanes)
const RING := 63.0               # drawn ring radius of a size-1 planet (56 x 1.12)
static var _gaps: Array = []     # local spacing of every point
static var _sizes: Array = []    # size of every point
static var _waves: Array = []
static var _draw_k := 1.0        # planets are drawn bigger on big galaxies (board.gd k)
static var _relax := 1.0         # eased off if a galaxy is hard to fit (never fails outright)

const NAMES := [
	"Pebble", "Marshmallow", "Wobble", "Zoop", "Biscuit", "Noodle", "Glimmer", "Pudding",
	"Snorkel", "Jellybean", "Bloop", "Waffle", "Tumble", "Fizz", "Pickle", "Bonbon",
	"Dumpling", "Sprinkle", "Toffee", "Puddle", "Giggle", "Muffin", "Squish", "Nugget",
	"Bubbles", "Cocoa", "Pip", "Sock", "Taco", "Boop", "Gumdrop", "Pancake", "Wiggle", "Mango",
	"Cupcake", "Doodle", "Fudge", "Jiggle", "Kazoo", "Lollipop", "Meatball", "Nacho", "Oodle",
	"Popcorn", "Quokka", "Raisin", "Snickle", "Twinkle", "Ukulele", "Waddle", "Yoyo", "Zigzag",
	"Bumble", "Crumpet", "Dimple", "Flapjack", "Gizmo", "Hiccup", "Noodlebug", "Tater",
]

# transforms: 0 identity, 1 flip x, 2 flip y, 3 rotate 180
static func _apply(t: int, p: Vector2) -> Vector2:
	match t:
		1: return Vector2(W - p.x, p.y)
		2: return Vector2(p.x, H - p.y)
		3: return Vector2(W - p.x, H - p.y)
		4, 5:
			var u := Vector2((p.x - CX) / SX, p.y - CY).rotated(TAU / 3.0 * (1 if t == 4 else 2))
			return Vector2(CX + u.x * SX, CY + u.y)
	return p


## A point given in "round" polar coordinates (angle, radius) around the centre.
static func _polar(ang: float, r: float) -> Vector2:
	var u := Vector2.from_angle(ang) * r
	return Vector2(CX + u.x * SX, CY + u.y)


## How roomy the galaxy is around p: -1 (crowded) .. 1 (empty), a few slow overlapping waves.
static func _field(p: Vector2) -> float:
	var v := 0.0
	for w in _waves:
		v += sin(p.x * w.x + p.y * w.y + w.z)
	return v / maxf(1.0, _waves.size())


static func _new_field(rng: RandomNumberGenerator) -> void:
	_waves = []
	for i in 3:
		_waves.append(Vector3(rng.randf_range(0.003, 0.015) * 0.75, rng.randf_range(0.003, 0.015) * 0.75, rng.randf_range(0, TAU)))
	_gaps = []
	_sizes = []


static func _size_for(kind: String, rng: RandomNumberGenerator) -> float:
	if kind == "home":
		return 1.08
	return 1.0 + SIZE_VARIETY * rng.randf_range(-1.0, 1.0)


static func generate(num_players: int, mode: String, seed_value: int, size := "normal") -> Dictionary:
	var f: float = SIZES.get(size, 1.0)
	W = 1600.0 * f
	H = 900.0 * f
	CX = W / 2.0
	CY = H / 2.0
	_draw_k = sqrt(maxf(1.0, W / 1600.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# try the full natural look first; if it won't fit, ease the clumping and spacing a little at a time
	for relax in [1.0, 0.7, 0.4, 0.0]:
		_relax = relax
		for attempt in 120:
			var m := _try(num_players, mode, rng, size, f)
			if not m.is_empty():
				return m
	push_error("map generation failed")
	return {}


static func _try(num_players: int, mode: String, rng: RandomNumberGenerator, size: String, f: float) -> Dictionary:
	if num_players == 3:
		return _try3(mode, rng, size)
	var four := num_players >= 3
	var group: Array = [0, 1, 2, 3] if four else [0, 3]
	SX = 1.0
	_new_field(rng)
	var pts: Array = []    # Vector2
	var kinds: Array = []  # String
	var orbits: Array = [] # which symmetric group each node belongs to (same orbit = same start)

	# fixed axis nodes: centre lantern, two side lanterns, two gloom nests
	_add_orbit(rng, pts, kinds, orbits, group, Vector2(CX, CY), "lantern")
	_add_orbit(rng, pts, kinds, orbits, group, Vector2(CX - rng.randf_range(250, 300) * f, CY), "lantern")
	_add_orbit(rng, pts, kinds, orbits, group, Vector2(CX, rng.randf_range(70, 95)), "nest")

	# fundamental region
	var reg: Rect2
	var extra: Array
	if four:
		reg = Rect2(70, 60, CX - 70 - 75, CY - 60 - 75)
		extra = ["planet", "planet", "asteroid", "mystery"]
		if size != "normal":
			extra += ["planet", "asteroid", "lantern"]
		if size == "huge":
			extra += ["planet", "asteroid", "planet", "mystery", "asteroid"]
	else:
		reg = Rect2(70, 60, CX - 70 - 85, H - 120)
		extra = ["planet", "planet", "planet", "asteroid", "asteroid", "mystery"]
		if size != "normal":
			extra += ["planet", "asteroid", "lantern", "planet"]
		if size == "huge":
			extra += ["planet", "asteroid", "planet", "mystery", "asteroid", "planet", "asteroid"]

	var home_pos := Vector2(rng.randf_range(120, 190) * f, rng.randf_range(110, 170) * f)
	if not _try_place(rng, pts, kinds, orbits, group, home_pos, "home"):
		return {}
	for k in extra:
		var placed := false
		for tries in 300:
			var p := Vector2(rng.randf_range(reg.position.x, reg.end.x), rng.randf_range(reg.position.y, reg.end.y))
			if _try_place(rng, pts, kinds, orbits, group, p, k):
				placed = true
				break
		if not placed:
			return {}

	return _finish(pts, kinds, orbits, group, mode, rng)


## Three players: every home sits in its own 120 degree slice of a round galaxy.
static func _try3(mode: String, rng: RandomNumberGenerator, size: String) -> Dictionary:
	var group: Array = [0, 4, 5]
	_new_field(rng)
	var R := CY - 70.0
	SX = (CX - 80.0) / R
	var pts: Array = []
	var kinds: Array = []
	var orbits: Array = []
	var top := -PI / 2.0  # home slice points up
	_add_orbit(rng, pts, kinds, orbits, group, Vector2(CX, CY), "lantern")
	_add_orbit(rng, pts, kinds, orbits, group, _polar(top + PI / 3.0, R * rng.randf_range(0.42, 0.5)), "lantern")
	_add_orbit(rng, pts, kinds, orbits, group, _polar(top + PI / 3.0, R * 0.97), "nest")
	var extra: Array = ["planet", "asteroid", "mystery", "planet"]
	if size != "normal":
		extra += ["planet", "asteroid", "lantern", "planet"]
	if size == "huge":
		extra += ["planet", "asteroid", "mystery", "asteroid"]
	var home := _polar(top + rng.randf_range(-0.2, 0.2), R * rng.randf_range(0.8, 0.92))
	if not _try_place(rng, pts, kinds, orbits, group, home, "home"):
		LAST_FAIL = "home"
		return {}
	for k in extra:
		var placed := false
		for tries in 300:
			var p := _polar(top + rng.randf_range(-PI / 3.0, PI / 3.0), R * sqrt(rng.randf_range(0.04, 1.0)))
			if _try_place(rng, pts, kinds, orbits, group, p, k):
				placed = true
				break
		if not placed:
			LAST_FAIL = "place " + k
			return {}
	return _finish(pts, kinds, orbits, group, mode, rng)


static func _finish(pts: Array, kinds: Array, orbits: Array, group: Array, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var n := pts.size()
	# permutation of node indices under each transform
	var perm := {}
	for t in group:
		var arr: Array = []
		for i in n:
			arr.append(_find(pts, _apply(t, pts[i])))
		perm[t] = arr

	# greedy symmetric planar lanes, shortest first
	var cands: Array = []
	for i in n:
		for j in range(i + 1, n):
			var d: float = pts[i].distance_to(pts[j])
			if d <= MAX_LANE and (LANES != "rng" or _neighbourly(pts, i, j, d)):
				cands.append([d, i, j])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var edges := {}
	var deg: Array = []
	deg.resize(n)
	deg.fill(0)
	for c in cands:
		var i: int = c[1]
		var j: int = c[2]
		if edges.has(_key(i, j)):
			continue
		var orbit := {}
		for t in group:
			var a: int = perm[t][i]
			var b: int = perm[t][j]
			orbit[_key(a, b)] = [mini(a, b), maxi(a, b)]
		var ok := true
		var add_deg := {}
		for e in orbit.values():
			add_deg[e[0]] = add_deg.get(e[0], 0) + 1
			add_deg[e[1]] = add_deg.get(e[1], 0) + 1
		for v in add_deg:
			var cap := 6 if kinds[v] == "lantern" else MAX_DEG
			if deg[v] + add_deg[v] > cap:
				ok = false
		if ok:
			for e in orbit.values():
				if _near_other_node(pts, e[0], e[1]):
					ok = false
					break
				for k2 in edges.values():
					if _cross(pts, e[0], e[1], k2[0], k2[1]):
						ok = false
						break
				if not ok:
					break
		if ok:
			var ov: Array = orbit.values()
			for a in ov.size():
				for b in range(a + 1, ov.size()):
					if _cross(pts, ov[a][0], ov[a][1], ov[b][0], ov[b][1]):
						ok = false
		if not ok:
			continue
		for e in orbit.values():
			edges[_key(e[0], e[1])] = e
			deg[e[0]] += 1
			deg[e[1]] += 1

	var adj: Array = []
	for i in n:
		adj.append([])
	for e in edges.values():
		adj[e[0]].append(e[1])
		adj[e[1]].append(e[0])

	# quality checks
	var homes: Array = []
	for i in n:
		if kinds[i] == "home":
			homes.append(i)
			if adj[i].size() < 2:
				LAST_FAIL = "home deg"
				return {}
	var d0 := bfs(adj, homes[0])
	for i in n:
		if d0[i] < 0:
			LAST_FAIL = "disconnected"
			return {}  # disconnected
		if adj[i].size() == 0:
			return {}
	for h in homes:
		if h != homes[0] and d0[h] < 4:
			LAST_FAIL = "homes close"
			return {}
	# every home should reach the centre lantern in the same number of hops (it does by symmetry)
	if d0[0] < 3:
		LAST_FAIL = "centre close"
		return {}
	LAST_FAIL = "ok"

	# order homes clockwise starting top-left
	homes.sort_custom(func(a, b):
		return _angle(pts[a]) < _angle(pts[b]))

	var names := NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp

	var nodes: Array = []
	for i in n:
		var kind: String = kinds[i]
		if kind == "nest" and mode != "coop":
			kind = "planet"
		nodes.append({
			"id": i, "name": names[i % names.size()], "pos": pts[i], "kind": kind,
			"owner": -1, "orbit": orbits[i], "look": rng.randi_range(0, 3), "size": _sizes[i],
		})
	return {"nodes": nodes, "adj": adj, "homes": homes, "size": Vector2(W, H)}


static func _angle(p: Vector2) -> float:
	# clockwise from top-left: TL, TR, BR, BL
	var a := atan2(p.y - CY, p.x - CX)  # TL is about -2.7
	var r := a + PI
	while r < 0:
		r += TAU
	return r


static func _add_orbit(rng: RandomNumberGenerator, pts: Array, kinds: Array, orbits: Array, group: Array, p: Vector2, kind: String) -> void:
	var o := 0 if orbits.is_empty() else int(orbits.back()) + 1
	var gap := _gap_at(p)
	var sz := _size_for(kind, rng)
	for t in group:
		var q := _apply(t, p)
		if _find(pts, q) < 0:
			pts.append(q)
			kinds.append(kind)
			orbits.append(o)
			_gaps.append(gap)
			_sizes.append(sz)


static func _gap_at(p: Vector2) -> float:
	return MIN_DIST * (1.0 + CLUMP * _relax * 0.55 * _field(p))


## Far enough apart? The local spacing of both, and never so close that the planets touch.
static func _room(q: Vector2, gq: float, sq: float, e: Vector2, ge: float, se: float) -> bool:
	return q.distance_to(e) >= maxf((gq + ge) / 2.0, RING * lerpf(1.0, _draw_k, _relax) * (sq + se) + 26.0 * _relax)


static func _try_place(rng: RandomNumberGenerator, pts: Array, kinds: Array, orbits: Array, group: Array, p: Vector2, kind: String) -> bool:
	var gap := _gap_at(p)
	var sz := _size_for(kind, rng)
	var imgs: Array = []
	for t in group:
		imgs.append(_apply(t, p))
	for a in imgs.size():
		for b in range(a + 1, imgs.size()):
			if not _room(imgs[a], gap, sz, imgs[b], gap, sz):
				return false
	for q in imgs:
		for i in pts.size():
			if not _room(q, gap, sz, pts[i], _gaps[i], _sizes[i]):
				return false
	var o := 0 if orbits.is_empty() else int(orbits.back()) + 1
	for q in imgs:
		pts.append(q)
		kinds.append(kind)
		orbits.append(o)
		_gaps.append(gap)
		_sizes.append(sz)
	return true


static func _find(pts: Array, p: Vector2) -> int:
	for i in pts.size():
		if pts[i].distance_to(p) < 1.0:
			return i
	return -1


static func _key(a: int, b: int) -> int:
	return mini(a, b) * 1000 + maxi(a, b)


## Relative neighbourhood rule: a lane i-j only if no planet is closer to both of them.
static func _neighbourly(pts: Array, i: int, j: int, d: float) -> bool:
	for k2 in pts.size():
		if k2 == i or k2 == j:
			continue
		if maxf(pts[i].distance_to(pts[k2]), pts[j].distance_to(pts[k2])) < d - 0.5:
			return false
	return true


static func _near_other_node(pts: Array, a: int, b: int) -> bool:
	var pa: Vector2 = pts[a]
	var pb: Vector2 = pts[b]
	for i in pts.size():
		if i == a or i == b:
			continue
		var q := Geometry2D.get_closest_point_to_segment(pts[i], pa, pb)
		if q.distance_to(pts[i]) < 70.0 * (_sizes[i] if i < _sizes.size() else 1.0):
			return true
	return false


static func _cross(pts: Array, a: int, b: int, c: int, d: int) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	return Geometry2D.segment_intersects_segment(pts[a], pts[b], pts[c], pts[d]) != null


static func bfs(adj: Array, start: int) -> Array:
	var dist: Array = []
	dist.resize(adj.size())
	dist.fill(-1)
	dist[start] = 0
	var q: Array = [start]
	var head := 0
	while head < q.size():
		var u: int = q[head]
		head += 1
		for v in adj[u]:
			if dist[v] < 0:
				dist[v] = dist[u] + 1
				q.append(v)
	return dist
