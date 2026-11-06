extends Node2D
## Draws the galaxy and animates what the rules say happened.

signal node_clicked(n: int)

const Rules = preload("res://scripts/rules.gd")

const INK := Color("2a2350")
const LANE := Color("4b4486")

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


func _ready() -> void:
	for n in ["planet_0", "planet_1", "planet_2", "planet_3", "home", "mystery", "lantern",
			"nest", "gloom", "icon_critter", "icon_shield", "icon_city", "icon_pinky",
			"critter_blorb", "critter_zibbit", "critter_moxie", "critter_ploot"]:
		tex[n] = load("res://assets/art/%s.svg" % n)
	_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 420:
		_stars.append([Vector2(rng.randf_range(-0.08, 1.08), rng.randf_range(-0.18, 1.18)),
			rng.randf_range(0.8, 2.6), rng.randf_range(0, TAU)])
	_label_settings = LabelSettings.new()
	_label_settings.font_size = 22
	_label_settings.outline_size = 8
	_label_settings.outline_color = Color("120f29")
	_label_settings.font_color = Color("e9e6ff")
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
		return
	size = s.get("size", Vector2(1600, 900))
	k = sqrt(maxf(1.0, size.x / 1600.0))
	for pl in s.get("players", []):
		_home_of[pl["home"]] = pl["id"]
	for nd in s["nodes"]:
		var h := Node2D.new()
		h.position = nd["pos"]
		h.scale = Vector2(k, k)
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
					Color("b9b0e0") if e.get("gloom", false) else Color("ffe96b"))
			"capture":
				_pulse(e["node"])
				if e["owner"] == Rules.GLOOM:
					float_text(s["nodes"][e["node"]]["pos"], "Gloomed!", Color("b9b0e0"))
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
				float_text((s["nodes"][e["a"]]["pos"] + s["nodes"][e["b"]]["pos"]) / 2.0, "Friends!", Color("ff8fb5"))


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
	var tw := create_tween()
	tw.tween_property(h, "scale", Vector2(1.2, 1.2) * k, 0.12)
	tw.tween_property(h, "scale", Vector2(k, k), 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


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
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _draw() -> void:
	var star_scale := size / Vector2(1600, 900)
	var sz := Vector2(1600, 900) * maxf(star_scale.x, star_scale.y)
	for st in _stars:
		var a := 0.35 + 0.35 * sin(t * 1.3 + st[2])
		draw_circle(st[0] * sz, st[1] * k, Color(1, 1, 1, a))
	var mid := size / 2.0
	draw_circle(mid, 520 * size.x / 1600.0, Color(0.35, 0.22, 0.6, 0.06))
	draw_circle(mid, 300 * size.x / 1600.0, Color(0.5, 0.35, 0.8, 0.05))
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
					col = Color("ff9a5c") if targets[other] == "dance" else (Color("ff8fb5") if targets[other] == "gift" else Color("8be08b"))
					w = 8.0
					hl = true
				draw_line(a, b, Color(0, 0, 0, 0.35), w + 6)
				if friends.has(i * 1000 + j) and not hl:
					draw_line(a, b, LANE, 6)
					_dashed_line(a, b, Color("ff8fb5"), 9)
				else:
					draw_line(a, b, col, w)
	# friends: one pink loop around both planets, so you can see at a glance who is teamed up
	for tr in s.get("truces", []):
		if tr.has("na") and Rules.friend_of(s, tr["na"]) == tr["nb"]:
			var loop := _capsule(nodes[tr["na"]]["pos"], nodes[tr["nb"]]["pos"], 92 * k)
			var pk := Color("ff8fb5")
			draw_colored_polygon(loop, Color(pk.r, pk.g, pk.b, 0.13))
			loop.append(loop[0])
			draw_polyline(loop, Color(0, 0, 0, 0.35), 15 * k, true)
			draw_polyline(loop, Color(pk.r, pk.g, pk.b, 0.75 + 0.25 * sin(t * 3)), 8 * k, true)
	for nd in nodes:
		var p: Vector2 = nd["pos"]
		if nd["owner"] >= 0 or nd["owner"] == Rules.GLOOM:
			var c := Rules.owner_color(s, nd["owner"])
			draw_circle(p, 56 * k, Color(c.r, c.g, c.b, 0.22))
			draw_arc(p, 56 * k, 0, TAU, 48, c, 7 * k, true)
		if nd["kind"] == "golden" and nd["owner"] < 0:
			draw_arc(p, 56 * k, 0, TAU, 48, Color(1, 0.85, 0.3, 0.35 + 0.2 * sin(t * 2)), 4 * k, true)


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
			_overlay.draw_arc(p, 64 * k, 0, TAU, 48, sc, 6, true)
			_overlay.draw_arc(p, 70 * k, 0, TAU, 48, Color(sc.r, sc.g, sc.b, 0.25), 4, true)
		if place_nodes.has(id):
			var g := 0.5 + 0.5 * sin(t * 4)
			_overlay.draw_arc(p, 64 * k, 0, TAU, 48, Color(1, 0.95, 0.5, 0.35 + 0.5 * g), 5, true)
		if city_nodes.has(id) and not nd["city"]:
			# a little "you could build a city here" sign
			var cs := 38.0 * k * (1.0 + 0.1 * sin(t * 4))
			var cp := p + Vector2(-58, -58) * k
			_overlay.draw_circle(cp, cs * 0.62, Color(0.64, 0.41, 0.16, 0.9))
			_overlay.draw_texture_rect(tex["icon_city"], Rect2(cp - Vector2(cs, cs) / 2.0, Vector2(cs, cs)), false, Color(1, 1, 1, 0.75 + 0.25 * sin(t * 4)))
		if card_nodes.has(id):
			var g2 := 0.5 + 0.5 * sin(t * 5)
			_overlay.draw_arc(p, 64 * k, 0, TAU, 48, Color(0.6, 0.95, 1, 0.4 + 0.5 * g2), 6, true)
		if targets.has(id):
			var kind: String = targets[id]
			var g3 := 0.6 + 0.4 * sin(t * 5)
			var tc := Color(1, 0.55, 0.3, g3) if kind == "dance" else (Color(1, 0.56, 0.71, g3) if kind == "gift" else Color(0.55, 1, 0.55, g3))
			_overlay.draw_arc(p, 64 * k, 0, TAU, 48, tc, 7, true)
		if id == selected_node:
			_overlay.draw_arc(p, 68 * k, 0, TAU, 48, Color("ffe96b"), 7, true)
		if id == hint_node or id == hint_from:
			var hh := 0.5 + 0.5 * sin(t * 7)
			_overlay.draw_arc(p, (76 + 6 * hh) * k, 0, TAU, 48, Color(1, 0.95, 0.4, 0.9), 6, true)
		_draw_badge(nd)


func _draw_badge(nd: Dictionary) -> void:
	var n: int = _shown_n.get(nd["id"], nd["n"])
	if n <= 0 and nd["owner"] == Rules.WILD:
		return
	var p: Vector2 = nd["pos"] + Vector2(40, 30) * k
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


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or s.is_empty() or planets.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		var best := -1
		var best_d := 62.0 * k
		for nd in s["nodes"]:
			var d: float = nd["pos"].distance_to(p)
			if d < best_d:
				best_d = d
				best = nd["id"]
		if best >= 0:
			node_clicked.emit(best)
			get_viewport().set_input_as_handled()
