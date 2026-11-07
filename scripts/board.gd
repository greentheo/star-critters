extends Node2D
## Draws the galaxy and animates what the rules say happened.

signal node_clicked(n: int)

const Rules = preload("res://scripts/rules.gd")

const INK := Color("13262e")
const LANE := Color("2a4a55")

var s: Dictionary = {}
var tex := {}
var planets := {}       # node id -> Node2D holder
var targets := {}       # node id -> send kind ("move", "gift", "take", "dance")
var place_nodes := {}   # node id -> true (where new critters can go)
var card_nodes := {}    # node id -> true (where a card can be played)
var city_nodes := {}    # node id -> true (a city could be built here right now)
var selected_node := -1
var hint_node := -1
var hint_from := -1
var input_enabled := true
var t := 0.0
var _stars: Array = []
var _label_settings: LabelSettings
var _float_settings: LabelSettings
var _overlay: Node2D
var _font: Font
var _home_of := {}      # node id -> player id whose home it is
var _shown_n := {}      # node id -> count currently shown (lags behind during fly-ins)
var k := 1.0            # planets/badges are drawn bigger on big galaxies (the board zooms out)
var size := Vector2(1600, 900)
const PLANET_SCALE := 1.12  # planets a notch bigger than v3 (mood lab pick)

# mood: Aurora sky, drifting gas clouds, comets, and a slow "breath" pulse (mood lab picks)
const SKY_TOP := Color("0b1d26")
const SKY_BOTTOM := Color("050b12")
const NEBULA := [Color("1f7a63"), Color("3d2f7a"), Color("2a6f8f")]
const STAR := Color("eafff6")
var pulse := 0.5          # 0..1, set by main every frame
var pulse_depth := 0.06   # 0 = pulse off
var _soft: GradientTexture2D   # round soft blob (clouds, glows)
var _sky: GradientTexture2D
var _vig: GradientTexture2D
var _clouds: Array = []        # {pos, vel, blobs: [[offset, radius, color]], big}
var _next_cloud := 8.0
var _comets: Array = []        # {pos, vel}
var _next_comet := 14.0
var _vignette: Node2D


func _ready() -> void:
	for n in ["planet_0", "planet_1", "planet_2", "planet_3", "home", "mystery", "lantern",
			"nest", "gloom", "icon_critter", "icon_shield", "icon_city", "icon_pinky",
			"critter_blorb", "critter_zibbit", "critter_moxie", "critter_ploot"]:
		tex[n] = load("res://assets/art/%s.svg" % n)
	_font = ThemeDB.fallback_font
	_soft = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.45, 1.0])
	_vig = _radial([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 1)], [0.0, 0.42, 1.0])
	_sky = GradientTexture2D.new()
	_sky.gradient = Gradient.new()
	_sky.gradient.colors = PackedColorArray([SKY_TOP, SKY_BOTTOM])
	_sky.fill_from = Vector2(0.5, 0.0)
	_sky.fill_to = Vector2(0.5, 1.0)
	_sky.width = 8
	_sky.height = 256
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 420:
		_stars.append([Vector2(rng.randf_range(-0.08, 1.08), rng.randf_range(-0.18, 1.18)),
			rng.randf_range(0.8, 2.6), rng.randf_range(0, TAU)])
	_label_settings = LabelSettings.new()
	_label_settings.font_size = 22
	_label_settings.outline_size = 8
	_label_settings.outline_color = Color("081419")
	_label_settings.font_color = Color("e8fff8")
	_float_settings = _label_settings.duplicate()
	_float_settings.font_size = 38
	_float_settings.outline_size = 12


# ---------------------------------------------------------------- build / sync

func setup(state: Dictionary) -> void:
	s = state
	for c in get_children():
		c.queue_free()
	planets.clear()
	_home_of.clear()
	_shown_n.clear()
	if s.is_empty() or not s.has("nodes"):
		_overlay = null
		size = Vector2(1600, 900)
		k = 1.0
		_make_clouds()  # the menu gets the drifting sky too
		return
	size = s.get("size", Vector2(1600, 900))
	k = sqrt(maxf(1.0, size.x / 1600.0))
	for pl in s.get("players", []):
		_home_of[pl["home"]] = pl["id"]
	for nd in s["nodes"]:
		var h := Node2D.new()
		h.position = nd["pos"]
		h.scale = Vector2.ONE * ps(nd)
		add_child(h)
		planets[nd["id"]] = h
		var spr := Sprite2D.new()
		spr.name = "Body"
		h.add_child(spr)
		var gl := Sprite2D.new()
		gl.name = "Gloom"
		gl.texture = tex["gloom"]
		gl.scale = Vector2(0.95, 0.95)
		h.add_child(gl)
		var city := Sprite2D.new()
		city.name = "City"
		city.texture = tex["icon_city"]
		city.position = Vector2(-40, -38)
		city.scale = Vector2(0.85, 0.85)
		city.visible = false
		h.add_child(city)
		var lab := Label.new()
		lab.name = "Name"
		lab.label_settings = _label_settings
		lab.text = nd["name"]
		lab.size = Vector2(200, 30)
		lab.position = Vector2(-100, 50)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(lab)
		_shown_n[nd["id"]] = nd["n"]
	_overlay = Node2D.new()
	_overlay.z_index = 10
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay.bind(_overlay))
	_vignette = Node2D.new()
	_vignette.z_index = 12
	add_child(_vignette)
	_vignette.draw.connect(_draw_vignette.bind(_vignette))
	_make_clouds()
	sync(false)


func set_state(state: Dictionary, animate := true) -> void:
	s = state
	sync(animate)


func sync(animate := true) -> void:
	if s.is_empty() or planets.is_empty():
		return
	var events: Array = s.get("events", [])
	for nd in s["nodes"]:
		var h: Node2D = planets[nd["id"]]
		var body: Sprite2D = h.get_node("Body")
		var sc := 0.78
		match nd["kind"]:
			"home":
				var who: int = _home_of.get(nd["id"], maxi(nd["owner"], 0))
				body.texture = tex["critter_" + s["players"][who]["species"]]
				sc = 0.40
			"planet":
				body.texture = tex["planet_%d" % nd["look"]]
			"mystery":
				body.texture = tex["mystery"]
			"golden":
				body.texture = tex["lantern"]
				sc = 0.9
			"nest":
				body.texture = tex["nest"]
				sc = 0.9
		body.scale = Vector2(sc, sc)
		body.modulate = Color(0.75, 0.75, 0.85) if nd["kind"] == "home" and nd["owner"] != _home_of.get(nd["id"], -9) else Color.WHITE
		h.get_node("Gloom").visible = nd["owner"] == Rules.GLOOM and nd["kind"] != "nest"
		var city: Sprite2D = h.get_node("City")
		city.visible = nd["city"]
		city.modulate = Color(0.6, 0.6, 0.7) if nd["owner"] == Rules.GLOOM else Color.WHITE
	# counts: show the final numbers, but let fly-ins arrive first
	var arriving := {}
	if animate:
		for e in events:
			if e["t"] == "move":
				arriving[e["to"]] = true
	for nd in s["nodes"]:
		if not arriving.has(nd["id"]):
			_shown_n[nd["id"]] = nd["n"]
	if animate:
		_play_effects(events)
	else:
		for nd in s["nodes"]:
			_shown_n[nd["id"]] = nd["n"]
	queue_redraw()


# ---------------------------------------------------------------- effects

func _play_effects(events: Array) -> void:
	var delay := 0.0
	for e in events:
		match e["t"]:
			"move":
				_fly(e["from"], e["to"], e["count"], e["owner"], delay)
				delay = minf(delay + 0.05, 0.3)
			"place":
				_pulse(e["node"])
				float_text(s["nodes"][e["node"]]["pos"], "+%d" % e["count"],
					Color("aab8c2") if e.get("gloom", false) else Color("ffe96b"))
			"capture":
				_pulse(e["node"])
				if e["owner"] == Rules.GLOOM:
					float_text(s["nodes"][e["node"]]["pos"], "Gloomed!", Color("aab8c2"))
				elif e["prev"] == Rules.GLOOM:
					float_text(s["nodes"][e["node"]]["pos"], "Sparkle!", Color("fff6a8"))
				else:
					float_text(s["nodes"][e["node"]]["pos"], "Yours!", s["players"][e["owner"]]["color"].lerp(Color.WHITE, 0.3))
			"text":
				float_text(s["nodes"][e["node"]]["pos"], e["text"], Color(e["color"]))
			"mystery":
				float_text(s["nodes"][e["node"]]["pos"] + Vector2(0, -40), "Surprise!", Color("ffe96b"))
			"roll":
				_wiggle(e.get("hit", e["to"] if e["att_wins"] else e["from"]))
			"city":
				_pulse(e["node"])
				float_text(s["nodes"][e["node"]]["pos"], "New city!", Color("ffd27a"))
			"friends":
				_pulse(e["a"])
				_pulse(e["b"])
				float_text((s["nodes"][e["a"]]["pos"] + s["nodes"][e["b"]]["pos"]) / 2.0, "Friends!", Color("8ff5d2"))


func _fly(from: int, to: int, count: int, owner: int, delay: float) -> void:
	var a: Vector2 = s["nodes"][from]["pos"]
	var b: Vector2 = s["nodes"][to]["pos"]
	var col := Rules.owner_color(s, owner).lerp(Color.WHITE, 0.15)
	var k := clampi(count, 1, 5)
	var dur := clampf(a.distance_to(b) / 900.0, 0.3, 0.7)
	for i in k:
		var spr := Sprite2D.new()
		spr.texture = tex["icon_critter"]
		spr.modulate = col
		spr.scale = Vector2(0.55, 0.55) * k
		spr.position = a
		spr.z_index = 15
		add_child(spr)
		var side := Vector2(0, (i - (k - 1) / 2.0) * 14).rotated((b - a).angle())
		var tw := create_tween()
		tw.tween_interval(delay + i * 0.07)
		tw.tween_property(spr, "position", b + side, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(spr.queue_free)
	var land := create_tween()
	land.tween_interval(delay + dur + (k - 1) * 0.07)
	land.tween_callback(func():
		if not s.is_empty() and to < s["nodes"].size():
			_shown_n[to] = s["nodes"][to]["n"]
			_pulse(to))


func _pulse(n: int) -> void:
	if not planets.has(n):
		return
	var h: Node2D = planets[n]
	var sc := ps(s["nodes"][n])
	var tw := create_tween()
	tw.tween_property(h, "scale", Vector2(1.2, 1.2) * sc, 0.12)
	tw.tween_property(h, "scale", Vector2(sc, sc), 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _wiggle(n: int) -> void:
	if not planets.has(n):
		return
	var h: Node2D = planets[n]
	var tw := create_tween()
	tw.tween_property(h, "rotation", 0.12, 0.06)
	tw.tween_property(h, "rotation", -0.12, 0.1)
	tw.tween_property(h, "rotation", 0.0, 0.06)


func float_text(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.label_settings = _float_settings.duplicate()
	l.label_settings.font_color = col
	l.text = text
	l.size = Vector2(360, 50)
	l.scale = Vector2(k, k)
	l.position = pos + Vector2(-180 * k, -100 * k)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 20
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 60, 1.4).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.6)
	tw.tween_callback(l.queue_free)


func node_screen_pos(n: int) -> Vector2:
	return position + s["nodes"][n]["pos"] * scale


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	t += delta
	# the breath: the whole board brightens and dims by a few percent
	var b := 1.0 + pulse_depth * (pulse - 0.5) * 2.0
	modulate = Color(b, b, b, 1.0)
	_move_sky(delta)
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()
	if _vignette:
		_vignette.queue_redraw()


func _draw() -> void:
	var star_scale := size / Vector2(1600, 900)
	var sz := Vector2(1600, 900) * maxf(star_scale.x, star_scale.y)
	draw_texture_rect(_sky, Rect2(-size * 0.6, size * 2.2), false)
	# gas & dust clouds (they breathe a little with the pulse)
	var cloud_a := 0.9 * (1.0 + pulse_depth * 6.0 * (pulse - 0.5))
	for c in _clouds:
		var a0: float = cloud_a * (1.0 if c["big"] else 0.8)
		for bl in c["blobs"]:
			var r: float = bl[1]
			var col: Color = bl[2]
			draw_texture_rect(_soft, Rect2(c["pos"] + bl[0] - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(col.r, col.g, col.b, 0.2 * a0))
	for i in _stars.size():
		var st: Array = _stars[i]
		var a := 0.3 + 0.45 * (0.5 + 0.5 * sin(t * 1.3 + st[2]))
		var sp: Vector2 = st[0]
		sp.x = fposmod(sp.x + 0.08 - t * 0.0007 * (1 + i % 3), 1.16) - 0.08  # a slow drift
		draw_circle(sp * sz, st[1] * k, Color(STAR.r, STAR.g, STAR.b, a))
	for cm in _comets:
		var head: Vector2 = cm["pos"]
		var tail: Vector2 = head - cm["vel"] * 0.9
		draw_polyline_colors(PackedVector2Array([head, tail]), PackedColorArray([Color(STAR, 0.75), Color(STAR, 0.0)]), 3.0 * k, true)
		draw_circle(head, 3.2 * k, Color(STAR, 0.95))
	if s.is_empty() or planets.is_empty():
		return
	var nodes: Array = s["nodes"]
	var friends := {}
	for tr in s.get("truces", []):
		if tr.has("na") and Rules.friend_of(s, tr["na"]) == tr["nb"]:
			friends[mini(tr["na"], tr["nb"]) * 1000 + maxi(tr["na"], tr["nb"])] = true
	for i in nodes.size():
		for j in s["adj"][i]:
			if j > i:
				var a: Vector2 = nodes[i]["pos"]
				var b: Vector2 = nodes[j]["pos"]
				var col := LANE
				var w := 6.0
				var oi: int = nodes[i]["owner"]
				# a lane between two planets of the same owner takes their colour: territory at a glance
				if oi == nodes[j]["owner"] and (oi >= 0 or oi == Rules.GLOOM):
					col = Rules.owner_color(s, oi).darkened(0.12)
					w = 11.0
				var hl := false
				if selected_node >= 0 and ((i == selected_node and targets.has(j)) or (j == selected_node and targets.has(i))):
					var other: int = j if i == selected_node else i
					col = Color("ff9a5c") if targets[other] == "dance" else (Color("8ff5d2") if targets[other] == "gift" else Color("8be08b"))
					w = 8.0
					hl = true
				draw_line(a, b, Color(0, 0, 0, 0.35), w + 6)
				if friends.has(i * 1000 + j) and not hl:
					draw_line(a, b, LANE, 6)
					_dashed_line(a, b, Color("8ff5d2"), 9)
				else:
					draw_line(a, b, col, w)
	# friends: one pink loop around both planets, so you can see at a glance who is teamed up
	for tr in s.get("truces", []):
		if tr.has("na") and Rules.friend_of(s, tr["na"]) == tr["nb"]:
			var loop := _capsule(nodes[tr["na"]]["pos"], nodes[tr["nb"]]["pos"], 82.0 * maxf(ps(nodes[tr["na"]]), ps(nodes[tr["nb"]])))
			var pk := Color("8ff5d2")
			draw_colored_polygon(loop, Color(pk.r, pk.g, pk.b, 0.13))
			loop.append(loop[0])
			draw_polyline(loop, Color(0, 0, 0, 0.35), 15 * k, true)
			draw_polyline(loop, Color(pk.r, pk.g, pk.b, 0.75 + 0.25 * sin(t * 3)), 8 * k, true)
	for nd in nodes:
		var p: Vector2 = nd["pos"]
		var r := 56.0 * ps(nd)
		if nd["owner"] >= 0 or nd["owner"] == Rules.GLOOM:
			var c := Rules.owner_color(s, nd["owner"])
			# a soft glow that breathes with the pulse
			var gr := r * 1.85 + pulse_depth * 150.0 * k * (pulse - 0.5)
			draw_texture_rect(_soft, Rect2(p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(c.r, c.g, c.b, 0.3))
			draw_circle(p, r, Color(c.r, c.g, c.b, 0.22))
			draw_arc(p, r, 0, TAU, 48, c, 7 * k, true)
		if nd["kind"] == "golden" and nd["owner"] < 0:
			draw_arc(p, r, 0, TAU, 48, Color(1, 0.85, 0.3, 0.35 + 0.2 * sin(t * 2)), 4 * k, true)


func _draw_overlay(ov: Node2D) -> void:
	if ov != _overlay or s.is_empty() or planets.is_empty():
		return  # an old overlay that is being freed
	var nodes: Array = s["nodes"]
	# hearts on friend lanes
	for tr in s.get("truces", []):
		if tr.has("na") and Rules.friend_of(s, tr["na"]) == tr["nb"]:
			var m: Vector2 = (nodes[tr["na"]]["pos"] + nodes[tr["nb"]]["pos"]) / 2.0
			var hs := 44.0 * k * (1.0 + 0.08 * sin(t * 4))
			_overlay.draw_texture_rect(tex["icon_pinky"], Rect2(m - Vector2(hs, hs) / 2.0, Vector2(hs, hs)), false)
	for nd in nodes:
		var p: Vector2 = nd["pos"]
		var id: int = nd["id"]
		if nd["shield"] >= 0:
			var sc := Color(0.55, 0.95, 1, 0.55 + 0.25 * sin(t * 3))
			_overlay.draw_arc(p, 64 * ps(nd), 0, TAU, 48, sc, 6, true)
			_overlay.draw_arc(p, 70 * ps(nd), 0, TAU, 48, Color(sc.r, sc.g, sc.b, 0.25), 4, true)
		if place_nodes.has(id):
			var g := 0.5 + 0.5 * sin(t * 4)
			_overlay.draw_arc(p, 64 * ps(nd), 0, TAU, 48, Color(1, 0.95, 0.5, 0.35 + 0.5 * g), 5, true)
		if city_nodes.has(id) and not nd["city"]:
			# a little "you could build a city here" sign
			var cs := 38.0 * k * (1.0 + 0.1 * sin(t * 4))
			var cp := p + Vector2(-58, -58) * ps(nd)
			_overlay.draw_circle(cp, cs * 0.62, Color(0.64, 0.41, 0.16, 0.9))
			_overlay.draw_texture_rect(tex["icon_city"], Rect2(cp - Vector2(cs, cs) / 2.0, Vector2(cs, cs)), false, Color(1, 1, 1, 0.75 + 0.25 * sin(t * 4)))
		if card_nodes.has(id):
			var g2 := 0.5 + 0.5 * sin(t * 5)
			_overlay.draw_arc(p, 64 * ps(nd), 0, TAU, 48, Color(0.6, 0.95, 1, 0.4 + 0.5 * g2), 6, true)
		if targets.has(id):
			var kind: String = targets[id]
			var g3 := 0.6 + 0.4 * sin(t * 5)
			var tc := Color(1, 0.55, 0.3, g3) if kind == "dance" else (Color(0.56, 0.96, 0.82, g3) if kind == "gift" else Color(0.55, 1, 0.55, g3))
			_overlay.draw_arc(p, 64 * ps(nd), 0, TAU, 48, tc, 7, true)
		if id == selected_node:
			_overlay.draw_arc(p, 68 * ps(nd), 0, TAU, 48, Color("ffe96b"), 7, true)
		if id == hint_node or id == hint_from:
			var hh := 0.5 + 0.5 * sin(t * 7)
			_overlay.draw_arc(p, (76 + 6 * hh) * ps(nd), 0, TAU, 48, Color(1, 0.95, 0.4, 0.9), 6, true)
		_draw_badge(nd)


func _draw_badge(nd: Dictionary) -> void:
	var n: int = _shown_n.get(nd["id"], nd["n"])
	if n <= 0 and nd["owner"] == Rules.WILD:
		return
	var p: Vector2 = nd["pos"] + Vector2(40, 30) * ps(nd)
	var o: int = nd["owner"]
	var fill := Rules.owner_color(s, o)
	var txt_col := Color.WHITE
	if o == Rules.WILD:
		txt_col = INK
	var r := (25.0 if n < 10 else 29.0 if n < 100 else 34.0) * k
	_overlay.draw_circle(p, r + 4 * k, INK)
	_overlay.draw_circle(p, r, fill)
	var str_n := str(n)
	var fs := int(32 * k)
	var w := _font.get_string_size(str_n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := p + Vector2(-w / 2.0, fs * 0.36)
	if txt_col == Color.WHITE:
		_overlay.draw_string_outline(_font, pos, str_n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(7 * k), INK)
	_overlay.draw_string(_font, pos, str_n, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
	# critters that already hopped this turn are resting
	if nd["owner"] >= 0 and Rules.tired(nd) > 0 and nd["owner"] == s["current"] and Rules.movable(s, nd["id"]) == 0:
		var zp := p + Vector2(r + 4 * k, -r)
		var zf := int(24 * k)
		_overlay.draw_string_outline(_font, zp, "zz", HORIZONTAL_ALIGNMENT_LEFT, -1, zf, int(6 * k), INK)
		_overlay.draw_string(_font, zp, "zz", HORIZONTAL_ALIGNMENT_LEFT, -1, zf, Color("bfe3ff"))


## A rounded loop (stadium shape) around two points.
func _capsule(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ang := (b - a).angle()
	for i in 17:
		pts.append(b + Vector2.from_angle(ang - PI / 2 + PI * i / 16.0) * r)
	for i in 17:
		pts.append(a + Vector2.from_angle(ang + PI / 2 + PI * i / 16.0) * r)
	return pts


func _dashed_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := a.distance_to(b)
	var dir := (b - a) / maxf(d, 1.0)
	var off := fmod(t * 60.0, 24.0)
	var x := off
	while x < d:
		draw_line(a + dir * x, a + dir * minf(x + 12, d), col, w)
		x += 24


## How big this planet is drawn: bigger on big galaxies, plus a little size variety.
func ps(nd: Dictionary) -> float:
	return k * PLANET_SCALE * float(nd.get("size", 1.0))


func _radial(cols: Array, offs: Array) -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray(cols)
	g.gradient.offsets = PackedFloat32Array(offs)
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 128
	g.height = 128
	return g


## A gas cloud: a loose pile of soft blobs in two colours (like the mood lab's clouds).
func _cloud(center: Vector2, w: float, h: float, c1: Color, c2: Color, big: bool, rng: RandomNumberGenerator) -> Dictionary:
	var blobs: Array = []
	for i in 26:
		var off := Vector2(rng.randf_range(-w * 0.32, w * 0.32), rng.randf_range(-h * 0.26, h * 0.26))
		blobs.append([off, rng.randf_range(40.0, minf(w, h) * 0.38) * 1.25, c1 if rng.randf() < 0.5 else c2])
	return {"pos": center, "vel": Vector2.ZERO, "blobs": blobs, "big": big, "home": center, "ph": rng.randf_range(0, TAU)}


func _make_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(size.x) * 31 + 5
	var u := size.x / 1200.0  # mood-lab units
	_clouds = [
		_cloud(Vector2(size.x * 0.22, size.y * 0.33), 900 * u, 560 * u, NEBULA[0], NEBULA[1], true, rng),
		_cloud(Vector2(size.x * 0.73, size.y * 0.67), 760 * u, 480 * u, NEBULA[2], NEBULA[0], true, rng),
	]
	var d := _cloud(Vector2(size.x * 0.25, size.y * 0.75), 520 * u, 300 * u, NEBULA[1], NEBULA[2], false, rng)
	d["vel"] = Vector2(9.0 * u, 0)
	_clouds.append(d)
	_comets.clear()


## Clouds drift and sway very slowly, a new one floats in now and then, and a comet passes by.
func _move_sky(delta: float) -> void:
	var u := size.x / 1200.0
	var keep: Array = []
	for c in _clouds:
		if c["big"]:
			c["pos"] = c["home"] + Vector2(sin(t * 0.013 + c["ph"]) * 30.0, cos(t * 0.011 + c["ph"]) * 18.0) * u
			keep.append(c)
		else:
			c["pos"] += c["vel"] * delta
			if c["pos"].x < size.x + 450 * u:
				keep.append(c)
	_clouds = keep
	_next_cloud -= delta
	if _next_cloud <= 0.0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var c := _cloud(Vector2(-350 * u, rng.randf_range(0.1, 0.9) * size.y), rng.randf_range(460, 520) * u,
			rng.randf_range(260, 300) * u, NEBULA[rng.randi_range(0, 2)], NEBULA[rng.randi_range(0, 2)], false, rng)
		c["vel"] = Vector2(rng.randf_range(7, 12) * u, 0)
		_clouds.append(c)
		_next_cloud = rng.randf_range(25, 45)
	_next_comet -= delta
	if _next_comet <= 0.0:
		_comets.append({"pos": Vector2(randf_range(0.1, 0.6) * size.x, -20.0),
			"vel": Vector2(randf_range(160, 240), randf_range(70, 120)) * u})
		_next_comet = randf_range(25, 50)
	var still: Array = []
	for cm in _comets:
		cm["pos"] += cm["vel"] * delta
		if cm["pos"].x < size.x + 300 * u and cm["pos"].y < size.y + 200 * u:
			still.append(cm)
	_comets = still


## The edges of the board darken a little, and breathe with the pulse.
func _draw_vignette(v: Node2D) -> void:
	if v != _vignette:
		return
	var a := 0.34 + pulse_depth * 3.0 * (pulse - 0.5)
	var r := Rect2(-size * 0.2, size * 1.4)
	v.draw_texture_rect(_vig, r, false, Color(1, 1, 1, clampf(a, 0.0, 1.0)))


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or s.is_empty() or planets.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		var best := -1
		var best_d := 1e9
		for nd in s["nodes"]:
			var d: float = nd["pos"].distance_to(p)
			if d < 62.0 * ps(nd) and d < best_d:
				best_d = d
				best = nd["id"]
		if best >= 0:
			node_clicked.emit(best)
			get_viewport().set_input_as_handled()
