extends Node
## Game flow + all the UI: setup screen, HUD, dance-offs, pass-and-play turn
## screen, Learn to Play coach and game over.

const Rules = preload("res://scripts/rules.gd")
const AI = preload("res://scripts/ai.gd")
const Board = preload("res://scripts/board.gd")
const Sound = preload("res://scripts/sound.gd")
const PULSE_HZ := 0.25     # one slow breath every 4 s (mood lab pick)
const PULSE_DEPTH := 0.06

const INK := Color("13262e")
const BG := Color("081419")
const PANEL := Color("0e2129")
const GOLD := Color("ffe08a")
const SOFT := Color("a3c9c0")
const GREEN := Color("2fa85a")
const GREEN_HI := Color("3cc46c")
const BOARD_AREA := Rect2(0, 96, 1500, 904)
var AI_DELAY := 0.45  # (vars so tests can speed things up)
var ROLL_EVERY := 1.6      # seconds between dice rolls in your dance-offs
var AI_ROLL_EVERY := 0.9   # ... and in the computer's

enum Seat { EMPTY, PLAYER, CADET, COMPUTER }
const SEAT_TEXT := ["Empty seat", "Player", "Cadet (extra help)", "Computer"]
const MODES := [
	["ffa", "Everyone for\nthemselves", "Grab the galaxy!"],
	["teams", "Teams\n2 vs 2", "Left side vs right side"],
	["coop", "Family vs\nthe Gloom", "Work together!"],
]


## A big friendly die drawn with pips.
class DieFace extends Control:
	var value := 1
	var col := Color.WHITE
	var dim := false

	func _init() -> void:
		custom_minimum_size = Vector2(86, 86)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if not dim else col.darkened(0.5)
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(5)
		sb.border_color = Color("13262e")
		draw_style_box(sb, Rect2(Vector2(3, 3), size - Vector2(6, 6)))
		var spots := {
			1: [Vector2(0.5, 0.5)], 2: [Vector2(0.27, 0.27), Vector2(0.73, 0.73)],
			3: [Vector2(0.27, 0.27), Vector2(0.5, 0.5), Vector2(0.73, 0.73)],
			4: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
			5: [Vector2(0.27, 0.27), Vector2(0.73, 0.27), Vector2(0.5, 0.5), Vector2(0.27, 0.73), Vector2(0.73, 0.73)],
			6: [Vector2(0.27, 0.25), Vector2(0.73, 0.25), Vector2(0.27, 0.5), Vector2(0.73, 0.5), Vector2(0.27, 0.75), Vector2(0.73, 0.75)],
		}
		for p in spots.get(value, []):
			draw_circle(p * size, size.x * 0.085, Color("13262e"))

	func show_value(v: int, tumble := true) -> void:
		if not tumble:
			value = v
			queue_redraw()
			return
		var tw := create_tween()
		for i in 7:
			tw.tween_callback(func():
				value = randi_range(1, 6)
				rotation = randf_range(-0.25, 0.25)
				queue_redraw())
			tw.tween_interval(0.05)
		tw.tween_callback(func():
			value = v
			rotation = 0.0
			queue_redraw())


var s: Dictionary = {}
var last_cfg: Dictionary = {}
var undo_stack: Array = []
var selected := -1        # planet chosen to send from
var info_node := -1       # planet whose info is shown
var last_place := -1      # last planet a critter was placed on
var pending_card := -1    # card waiting for a planet to be clicked
var dance: Dictionary = {}      # {from, to, ai} while a dance-off is playing
var dance_last: Dictionary = {} # last roll result
var dance_tally := {"a": 0, "d": 0}
var dance_token := 0
var pending_build := false
var choice: Dictionary = {}     # {from, to} while the dance-off / befriend pop-up is open
var ai_waiting := false         # a computer asked a person to be friends and waits for the answer
var city_offered := {}          # planets we already offered a city on this turn
var offer_cities := true        # tests can switch the start-of-turn city offer off
var over_shown := false
var tip_override := ""
var gen := 0  # bumps every new game so stale AI timers stop
var news_seq := 0
var tut_step := -1
var sound: Node
var _pulse_t := 0.0

var mode := "ffa"
var rules := "simple"
var gloom_on := false
var length := "medium"
var galaxy := "big"
var seats: Array = [Seat.PLAYER, Seat.PLAYER, Seat.EMPTY, Seat.EMPTY]

var theme: Theme
var tex := {}
var board: Node2D
var ui: Control
var setup_screen: Control
var game_ui: Control
var overlay: Control

# HUD refs
var round_label: Label
var rush_label: Label
var status_box: HBoxContainer
var chips_box: HBoxContainer
var turn_portrait: TextureRect
var turn_name: Label
var turn_sub: Label
var step_rows: Array = []   # [panel, title label, detail label]
var cards_box: GridContainer
var place_all_btn: Button
var build_btn: Button
var info_box: VBoxContainer
var dance_box: VBoxContainer
var dance_refs := {}
var tip_label: Label
var undo_btn: Button
var hint_btn: Button
var end_btn: Button
var coach: PanelContainer
var coach_text: Label
var coach_btns: HBoxContainer


func _ready() -> void:
	for n in ["critter_blorb", "critter_zibbit", "critter_moxie", "critter_ploot", "icon_star",
			"icon_bulb", "icon_warn", "icon_heart", "lantern", "nest", "gloom", "mystery",
			"icon_rocket", "icon_dice", "icon_shield", "icon_wormhole", "icon_clock", "icon_card",
			"icon_pinky", "icon_critter", "icon_city", "planet_0", "planet_2"]:
		tex[n] = load("res://assets/art/%s.svg" % n)
	theme = _make_theme()
	sound = Sound.new()
	add_child(sound)
	board = Board.new()
	add_child(board)
	_fit_board(Vector2(1600, 900))
	board.node_clicked.connect(_on_node_clicked)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = theme
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_show_setup()
	_setup_test_hook()


## The breath: one shared slow pulse for the board's light and the music.
func _process(delta: float) -> void:
	_pulse_t += delta
	var p := 0.5 - 0.5 * cos(TAU * PULSE_HZ * _pulse_t)
	var depth := PULSE_DEPTH if sound.pulse_on else 0.0
	board.pulse = p
	board.pulse_depth = depth
	sound.set_pulse(p, depth)


## Zoom the board so the whole galaxy fits next to the side panel.
func _fit_board(size: Vector2) -> void:
	var z := minf(BOARD_AREA.size.x / size.x, BOARD_AREA.size.y / size.y)
	board.scale = Vector2(z, z)
	board.position = BOARD_AREA.position + (BOARD_AREA.size - size * z) / 2.0


## Web-only hook so automated play-tests can click: window.scClick(x, y) in 1920x1080 coords.
var _js_cb
var _js_call_cb


func _setup_test_hook() -> void:
	if not OS.has_feature("web"):
		return
	_js_cb = JavaScriptBridge.create_callback(_js_click)
	JavaScriptBridge.get_interface("window").scClick = _js_cb
	_js_call_cb = JavaScriptBridge.create_callback(_js_call)
	JavaScriptBridge.get_interface("window").scCall = _js_call_cb


## window.scCall("method", arg1, ...) calls a method on Main; returns nothing.
func _js_call(args: Array) -> void:
	var m: String = str(args[0])
	var rest: Array = []
	for i in range(1, args.size()):
		var a = args[i]
		rest.append(int(a) if typeof(a) == TYPE_FLOAT and float(int(a)) == a else a)
	callv(m, rest)


func _js_click(args: Array) -> void:
	var p := get_viewport().get_final_transform() * Vector2(float(args[0]), float(args[1]))
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	Input.parse_input_event(mm)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	d.position = p
	d.global_position = p
	Input.parse_input_event(d)
	var u: InputEventMouseButton = d.duplicate()
	u.pressed = false
	u.button_mask = 0
	Input.parse_input_event(u)


## Test helpers (called through scCall in play-tests).
func _test_start(m: String, humans: int, ais: int, seed_value: int, r := "full", g := true, gx := "big") -> void:
	var players: Array = []
	for i in humans + ais:
		players.append({"species": i, "ai": i >= humans})
	start_game({"mode": m, "players": players, "seed": seed_value, "rules": r, "gloom": g, "length": "medium", "galaxy": gx})


func _test_dance(open_only = 0) -> void:
	## Place everything, then open the first good dance-off the hint finds and start it.
	if s["phase"] == "place":
		_place_all()
	for k in 30:
		var c := AI.next_command(s, s["current"])
		if c["cmd"] == "attack":
			_on_node_clicked(c["from"])
			_on_node_clicked(c["to"])
			if not open_only:
				_choose_dance()
			return
		if c["cmd"] == "end" or not AI.apply(s, c):
			return
		_after_change(false)


func _test_friends() -> void:
	## Make the current player friends with a neighbour, to look at the pink loop.
	var p: int = s["current"]
	for nd in s["nodes"]:
		if nd["owner"] != p:
			continue
		for to in s["adj"][nd["id"]]:
			var q: int = s["nodes"][to]["owner"]
			if q >= 0 and q != p:
				s["truces"] = [{"a": p, "b": q, "na": nd["id"], "nb": to, "until": s["round"] + 2}]
				_after_change(false)
				return


func _test_audio() -> void:
	## Prints what the audio system is doing (for checking sound in the web build).
	sound.play("turn")
	var best := {}
	for i in 60:
		await get_tree().process_frame
		for b in AudioServer.bus_count:
			var n := AudioServer.get_bus_name(b)
			best[n] = maxf(best.get(n, -200.0), AudioServer.get_bus_peak_volume_left_db(b, 0))
	print("AUDIO driver=%s mix=%d buses=%d music_on=%s sfx_on=%s drone=%s peaks=%s" % [AudioServer.get_driver_name(),
		AudioServer.get_mix_rate(), AudioServer.bus_count, sound.music_on, sound.sfx_on, sound._drone.playing, best])


func _test_fast_forward(rounds: int) -> void:
	## Let the AI play every seat (instantly) until `rounds` more rounds have passed.
	var stop_round: int = s["round"] + rounds
	var guard := 0
	while not s["over"] and s["round"] < stop_round and guard < 5000:
		guard += 1
		var c := AI.next_command(s, s["current"])
		if not AI.apply(s, c):
			Rules.end_turn(s)
	while not s["over"] and _cur()["ai"] and guard < 6000:
		guard += 1
		var c2 := AI.next_command(s, s["current"])
		if not AI.apply(s, c2):
			Rules.end_turn(s)
	s["events"].clear()
	board.setup(s)
	_close_overlay()
	_refresh()


# =================================================================== theme

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 26
	var normal := _box(Color("1e5560"), 16, 4)
	var hover := _box(Color("287080"), 16, 4)
	var pressed := _box(Color("12303a"), 16, 4)
	var disabled := _box(Color("132a31"), 16, 4)
	disabled.border_color = Color("25444d")
	for st in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled],
			["hover_pressed", pressed]]:
		th.set_stylebox(st[0], "Button", st[1])
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_disabled_color", "Button", Color("6f8f94"))
	th.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.3))
	th.set_constant("h_separation", "Button", 12)
	th.set_color("font_color", "Label", Color("e8fff8"))
	th.set_stylebox("panel", "PanelContainer", _box(PANEL, 20, 4))
	th.set_stylebox("panel", "Panel", _box(PANEL, 0, 0))
	th.set_color("font_outline_color", "Label", BG)
	return th


func _box(col: Color, radius: int, border: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(radius)
	b.set_border_width_all(border)
	b.border_color = INK
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b


func _label(text: String, size := 26, col := Color("e8fff8"), outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	return l


func _wrap_label(text: String, size: int, col: Color, width := 370) -> Label:
	var l := _label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _icon(name: String, size: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex[name]
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _icon_text(icon: String, text: String, size := 26, col := Color("e8fff8")) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(_icon(icon, size + 6))
	h.add_child(_label(text, size, col))
	return h


func _button(text: String, cb: Callable, size := 28, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if icon != "":
		b.icon = tex[icon]
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", int(size * 1.8))
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _green(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _box(GREEN, 18, 5))
	b.add_theme_stylebox_override("hover", _box(GREEN_HI, 18, 5))
	b.add_theme_stylebox_override("disabled", _box(Color("132a31"), 18, 5))
	return b


func _tinted(b: Button, col: Color) -> Button:
	b.add_theme_stylebox_override("normal", _box(col, 16, 4))
	b.add_theme_stylebox_override("hover", _box(col.lightened(0.15), 16, 4))
	return b


func _clear(c: Node) -> void:
	for ch in c.get_children():
		ch.queue_free()


func _bounce(node: Control, amount := 12.0, period := 0.9) -> void:
	var y := node.position.y
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "position:y", y - amount, period / 2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:y", y, period / 2).set_trans(Tween.TRANS_SINE)


func _flash(b: Control) -> void:
	if b == null or not is_instance_valid(b):
		return
	var tw := b.create_tween()
	for i in 3:
		tw.tween_property(b, "modulate", Color(1.6, 1.5, 0.6), 0.18)
		tw.tween_property(b, "modulate", Color.WHITE, 0.18)


# =================================================================== setup screen

func _show_setup() -> void:
	if game_ui:
		game_ui.queue_free()
		game_ui = null
	_close_overlay()
	if setup_screen:
		setup_screen.queue_free()
	setup_screen = Control.new()
	setup_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(setup_screen)
	board.visible = true  # starfield behind
	_fit_board(Vector2(1600, 900))
	board.setup({})

	var col := VBoxContainer.new()
	col.position = Vector2(110, 24)
	col.size = Vector2(1700, 1040)
	col.add_theme_constant_override("separation", 16)
	setup_screen.add_child(col)

	var title := _label("Star Critters", 96, GOLD, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("Grab the galaxy, one dance-off at a time!", 32, SOFT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 24)
	col.add_child(modes)
	for m in MODES:
		var b := _button("%s\n%s" % [m[1], m[2]], _set_mode.bind(m[0]), 28)
		b.custom_minimum_size = Vector2(400, 128)
		if m[0] == mode:
			_selected_style(b)
		modes.add_child(b)

	# options
	var opts := HBoxContainer.new()
	opts.alignment = BoxContainer.ALIGNMENT_CENTER
	opts.add_theme_constant_override("separation", 46)
	col.add_child(opts)
	opts.add_child(_option_group("Rules", [["simple", "Simple"], ["full", "Full"]], rules, _set_rules))
	if mode == "coop":
		var g := _option_group("The Gloom", [["on", "Always on"]], "on", func(_v): pass)
		opts.add_child(g)
	else:
		opts.add_child(_option_group("The Gloom", [["off", "Off"], ["on", "On"]], "on" if gloom_on else "off", _set_gloom))
	var opts2 := HBoxContainer.new()
	opts2.alignment = BoxContainer.ALIGNMENT_CENTER
	opts2.add_theme_constant_override("separation", 46)
	col.add_child(opts2)
	opts2.add_child(_option_group("Galaxy", [["normal", "Small"], ["big", "Big"], ["huge", "Huge"]], galaxy, _set_galaxy))
	var clock_opts: Array = []
	for k in ["short", "medium", "long", "epic"]:
		var filled := 0
		for st in seats:
			if st != Seat.EMPTY:
				filled += 1
		clock_opts.append([k, "%s %d" % [k.capitalize(), Rules.clock_rounds(mode, filled, galaxy, k)]])
	opts2.add_child(_option_group("Star Clock", clock_opts, length, _set_length))
	var expl := "Simple: place critters, build cities, send critters, done!" if rules == "simple" \
		else "Full: adds Lucky Cards."
	if mode != "coop" and gloom_on:
		expl += "  The Gloom is a grey fog that grows each round. Too much Gloom and EVERYONE loses!"
	elif mode == "coop":
		expl += "  Chase every bit of Gloom out of the galaxy before the Star Clock runs out!"
	var el := _label(expl, 24, SOFT)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	el.custom_minimum_size = Vector2(1700, 0)
	col.add_child(el)

	# seats
	var seats_row := HBoxContainer.new()
	seats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seats_row.add_theme_constant_override("separation", 24)
	col.add_child(seats_row)
	for i in 4:
		var sp: Dictionary = Rules.SPECIES[i]
		var card := PanelContainer.new()
		var cb := _box(PANEL, 20, 6)
		cb.border_color = sp["color"] if seats[i] != Seat.EMPTY else Color("25444d")
		card.add_theme_stylebox_override("panel", cb)
		card.custom_minimum_size = Vector2(340, 250)
		seats_row.add_child(card)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var pic := _icon("critter_" + sp["id"], 120)
		if seats[i] == Seat.EMPTY:
			pic.modulate = Color(1, 1, 1, 0.25)
		v.add_child(pic)
		var nm := _label(sp["name"], 32, sp["color"] if seats[i] != Seat.EMPTY else Color("6f8f94"))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		v.add_child(_button(SEAT_TEXT[seats[i]], _cycle_seat.bind(i), 26))

	var msg := _label(_setup_problem(), 26, Color("ffb4b4"))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(msg)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	col.add_child(row)
	var learn := _tinted(_button("Learn to play", _start_tutorial, 32, "icon_bulb"), Color("b8862a"))
	learn.custom_minimum_size = Vector2(340, 96)
	row.add_child(learn)
	var how := _button("How to play", _show_how_to, 32, "icon_card")
	how.custom_minimum_size = Vector2(320, 96)
	row.add_child(how)
	var gear := _button("Settings", _show_settings, 28)
	gear.custom_minimum_size = Vector2(200, 96)
	row.add_child(gear)
	var go := _green(_button("Blast off!", _start_from_setup, 44, "icon_rocket"))
	go.custom_minimum_size = Vector2(420, 96)
	go.disabled = _setup_problem() != ""
	row.add_child(go)


func _selected_style(b: Button) -> void:
	var sel := _box(Color("4e62c9"), 16, 6)
	sel.border_color = GOLD
	b.add_theme_stylebox_override("normal", sel)
	b.add_theme_stylebox_override("hover", sel)


func _option_group(title: String, options: Array, current: String, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(title + ":", 28, GOLD)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	for o in options:
		var b := _button(o[1], cb.bind(o[0]), 26)
		b.custom_minimum_size = Vector2(130, 60)
		if o[0] == current:
			_selected_style(b)
		h.add_child(b)
	return h


func _set_mode(m: String) -> void:
	sound.play("click")
	mode = m
	if mode == "teams":
		for i in 4:
			if seats[i] == Seat.EMPTY:
				seats[i] = Seat.COMPUTER
	_show_setup()


func _set_rules(v: String) -> void:
	sound.play("click")
	rules = v
	_show_setup()


func _set_gloom(v: String) -> void:
	sound.play("click")
	gloom_on = v == "on"
	_show_setup()


func _set_length(v: String) -> void:
	sound.play("click")
	length = v
	_show_setup()


func _set_galaxy(v: String) -> void:
	sound.play("click")
	galaxy = v
	_show_setup()


func _cycle_seat(i: int) -> void:
	sound.play("click")
	seats[i] = (seats[i] + 1) % 4
	if mode == "teams" and seats[i] == Seat.EMPTY:
		seats[i] = Seat.PLAYER
	_show_setup()


func _setup_problem() -> String:
	var on := 0
	var humans := 0
	for st in seats:
		if st != Seat.EMPTY:
			on += 1
		if st == Seat.PLAYER or st == Seat.CADET:
			humans += 1
	if mode == "ffa" and on < 2:
		return "Pick at least 2 critters."
	if mode == "teams" and on < 4:
		return "Teams needs all 4 critters (computers can fill in)."
	if mode == "coop" and on < 1:
		return "Pick at least 1 critter."
	if humans == 0:
		return "At least one critter should be a person!"
	return ""


func _start_from_setup() -> void:
	var players: Array = []
	for i in 4:
		if seats[i] != Seat.EMPTY:
			players.append({"species": i, "ai": seats[i] == Seat.COMPUTER, "cadet": seats[i] == Seat.CADET})
	start_game({"mode": mode, "players": players, "seed": randi() % 1000000,
		"rules": rules, "gloom": gloom_on or mode == "coop", "length": length, "galaxy": galaxy})


# =================================================================== game

func start_game(cfg: Dictionary) -> void:
	last_cfg = cfg
	tut_step = -1
	_begin_state(Rules.new_game(cfg))


func _start_tutorial() -> void:
	last_cfg = {"tutorial": true}
	tut_step = 0
	_begin_state(Rules.new_tutorial())


func _begin_state(state: Dictionary) -> void:
	gen += 1
	s = state
	over_shown = false
	news_seq = 0
	dance = {}
	choice = {}
	ai_waiting = false
	if setup_screen:
		setup_screen.queue_free()
		setup_screen = null
	_close_overlay()
	board.visible = true
	_fit_board(s.get("size", Vector2(1600, 900)))
	board.setup(s)
	_build_game_ui()
	s["events"].clear()
	_begin_turn()


func _humans() -> int:
	var h := 0
	for pl in s["players"]:
		if not pl["ai"]:
			h += 1
	return h


func _cur() -> Dictionary:
	return s["players"][s["current"]]


func _is_human_turn() -> bool:
	return not s.is_empty() and not s["over"] and not _cur()["ai"]


func _begin_turn() -> void:
	undo_stack.clear()
	selected = -1
	info_node = -1
	last_place = -1
	pending_card = -1
	pending_build = false
	dance = {}
	tip_override = ""
	city_offered = {}
	board.hint_node = -1
	board.hint_from = -1
	_refresh()
	if _cur()["ai"]:
		board.input_enabled = false
		get_tree().create_timer(AI_DELAY * 1.4).timeout.connect(_ai_step.bind(gen))
	else:
		board.input_enabled = true
		var rush_start: bool = Rules.star_rush(s) and s["round"] == s["max_rounds"] - Rules.RUSH_ROUNDS + 1
		sound.play("rush" if rush_start else "turn")
		var news := _news()
		if (_humans() >= 2 or news.size() > 0) and tut_step < 0:
			_show_turn_splash(news)
		else:
			_offer_city()
		news_seq = s["log_seq"]


func _news() -> Array:
	## What happened since the last person's turn that's worth telling them.
	var out: Array = []
	var me: int = s["current"]
	for e in s["log"]:
		if e["seq"] <= news_seq:
			continue
		var p: int = e["p"]
		var t: String = e["text"]
		if p < 0 or (p >= 0 and s["players"][p]["ai"]) or t.find(Rules.owner_name(s, me)) >= 0:
			if p == me:
				continue
			out.append(t)
	if out.size() > 5:
		out = out.slice(out.size() - 5)
	return out


func _after_change(animate := true) -> void:
	var rng_used := false
	for e in s["events"]:
		if e["t"] in ["roll", "mystery", "card", "newcard"]:
			rng_used = true
	if rng_used:
		undo_stack.clear()
	_sound_events(s["events"])
	board.set_state(s, animate)
	s["events"].clear()
	_refresh()
	if s["over"] and not over_shown:
		over_shown = true
		board.input_enabled = false
		var g := gen
		get_tree().create_timer(1.6).timeout.connect(func():
			if g == gen and not s.is_empty() and s["over"]:
				_show_game_over())


func _ai_step(g: int) -> void:
	if g != gen or s.is_empty() or s["over"] or not _cur()["ai"] or ai_waiting:
		return
	if overlay != null:  # e.g. How to play is open: wait
		get_tree().create_timer(0.5).timeout.connect(_ai_step.bind(g))
		return
	var c := AI.next_command(s, s["current"])
	var delay := AI_DELAY
	board.hint_from = -1
	board.hint_node = -1
	match c["cmd"]:
		"end":
			_end_turn()
			return
		"attack":
			board.hint_from = c["from"]
			board.hint_node = c["to"]
			if not _start_dance(c["from"], c["to"], true):
				_end_turn()
			return
		"befriend":
			var q: int = s["nodes"][c["to"]]["owner"]
			if q >= 0 and not s["players"][q]["ai"]:
				board.hint_from = c["from"]
				board.hint_node = c["to"]
				_refresh()
				ai_waiting = true
				_ask_friend(c["from"], c["to"], true)
				return
			delay = 1.2
		"send":
			board.hint_from = c["from"]
			board.hint_node = c["to"]
		"place", "build":
			board.hint_node = c["node"]
		"card":
			delay = 0.9
	if not AI.apply(s, c):
		_end_turn()
		return
	_after_change()
	get_tree().create_timer(delay).timeout.connect(_ai_step.bind(gen))


## What the rules just did, as sounds (each sound at most once per change).
func _sound_events(events: Array) -> void:
	if events.is_empty():
		return
	var rolls := 0
	var captured := {}
	for e in events:
		if e["t"] == "roll":
			rolls += 1
		elif e["t"] == "capture":
			captured[e["node"]] = true
	var done := {}
	for e in events:
		match e["t"]:
			"place":
				if e.get("gloom", false):
					_once(done, "gloomgrow")
				elif e["count"] > 1:
					_once(done, "placeall")
				else:
					sound.place_note()
			"move":
				if not captured.has(e["to"]):
					_once(done, "hop")
			"capture":
				var o: int = e["owner"]
				var prev: int = e["prev"]
				if o == Rules.GLOOM:
					_once(done, "gloomtake")
				elif prev == Rules.GLOOM:
					_once(done, "gloomchase")
				elif prev == Rules.WILD:
					_once(done, "claim")
				else:
					_once(done, "capture")
				if prev >= 0 and s["players"][prev]["out"]:
					_once(done, "out", 1.2)
			"roll":
				if rolls <= 2:
					if not e.get("tie", false):
						sound.roll(e["att_wins"])
					if not e["captured"] and e["att_left"] <= 0:
						_once(done, "defend", 0.5)
				else:
					_once(done, "dice_0")
			"city":
				_once(done, "city")
			"friends":
				_once(done, "friends")
			"mystery":
				_once(done, "mystery")
			"card":
				if e["card"] == "dice":
					_once(done, "luckydice")
			"newcard":
				_once(done, "card", 0.4)
			"text":
				var tx: String = e["text"]
				if tx.ends_with("City"):
					_once(done, "harvest")
				elif tx == "City lost!":
					_once(done, "citylost")
				elif tx == "Gift!":
					_once(done, "gift")
				elif tx == "Force Field!":
					_once(done, "shield")
				elif tx.contains("Rocket"):
					_once(done, "rocket")
				elif tx.contains("Meteor"):
					_once(done, "meteor")
				elif tx.contains("Comet"):
					_once(done, "comet")
				elif tx.contains("Glow"):
					_once(done, "glow")
				elif tx.contains("Storm"):
					_once(done, "storm")
				elif tx.begins_with("Bounce"):
					_once(done, "bounce")


func _once(done: Dictionary, name: String, delay := 0.0) -> void:
	if not done.has(name):
		done[name] = true
		sound.play(name, delay)


## Music, sound effects and the gentle pulse can each be switched off.
func _show_settings() -> void:
	var v := _overlay(0.8)
	v.add_child(_center(_label("Settings", 56, GOLD, 12)))
	var opts := [["music", "Music", sound.music_on], ["sfx", "Sound effects", sound.sfx_on],
		["pulse", "Gentle pulse (the board slowly breathes)", sound.pulse_on]]
	for o in opts:
		var b := _button("%s:  %s" % [o[1], "On" if o[2] else "Off"], _toggle_setting.bind(o[0]), 32)
		b.custom_minimum_size = Vector2(820, 86)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if o[2]:
			_selected_style(b)
		v.add_child(b)
	var close := _green(_button("Done", _close_overlay, 36))
	close.custom_minimum_size = Vector2(300, 90)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)


func _toggle_setting(which: String) -> void:
	match which:
		"music":
			sound.set_music(not sound.music_on)
		"sfx":
			sound.set_sfx(not sound.sfx_on)
		"pulse":
			sound.set_pulse_on(not sound.pulse_on)
	sound.play("click")
	_show_settings()


func _end_turn() -> void:
	if s["over"]:
		return
	dance = {}
	dance_token += 1
	var round_before: int = s["round"]
	Rules.end_turn(s)
	if s["round"] > round_before and not s["cosmic"].is_empty() and s["cosmic"]["id"] != "calm":
		sound.play("news", 0.6)
	board.hint_node = -1
	board.hint_from = -1
	_after_change()
	if not s["over"]:
		_begin_turn()


func _end_turn_pressed() -> void:
	if _is_human_turn() and dance.is_empty():
		sound.play("done")
		_end_turn()


func _push_undo() -> void:
	var copy: Dictionary = s.duplicate(true)
	copy["events"] = []
	undo_stack.append(copy)


func _undo() -> void:
	if undo_stack.is_empty() or not _is_human_turn() or not dance.is_empty():
		return
	s = undo_stack.pop_back()
	selected = -1
	info_node = -1
	pending_card = -1
	pending_build = false
	dance = {}
	board.hint_node = -1
	board.hint_from = -1
	tip_override = ""
	_after_change(false)


# =================================================================== clicks

func _on_node_clicked(n: int) -> void:
	if not _is_human_turn() or overlay != null or not dance.is_empty():
		return
	var p: int = s["current"]
	var nd: Dictionary = s["nodes"][n]
	board.hint_node = -1
	board.hint_from = -1
	tip_override = ""
	# playing a card on a planet
	if pending_card >= 0:
		if Rules.can_play(s, p, pending_card, n):
			Rules.play_card(s, p, pending_card, n)
			pending_card = -1
			_after_change()
		else:
			pending_card = -1
			tip_override = "Card put away. Click it again to use it."
			_refresh()
		return
	# building a city
	if pending_build:
		pending_build = false
		if Rules.can_build(s, p, n):
			_push_undo()
			Rules.build_city(s, p, n)
			tip_override = "A city on %s! It makes %d new critters there at the start of every one of your turns." % [nd["name"], Rules.CITY_MAKES]
			_after_change()
		else:
			tip_override = _why_no_city(n)
			_refresh()
		return
	# step 1: place
	if s["phase"] == "place":
		if Rules.can_place(s, p, n):
			_push_undo()
			Rules.place(s, p, n, 1)
			last_place = n
			_after_change()
			if s["phase"] == "go":
				_offer_city()
		else:
			info_node = n
			sound.play("invalid")
			tip_override = "First put your new critters on YOUR planets (the glowing ones)."
			_refresh()
		return
	# step 2: send
	if selected >= 0 and selected != n:
		var from := selected
		var kind := Rules.send_kind(s, p, from, n)
		if kind == "dance":
			_show_dance_choice(from, n)
			return
		if kind == "gift" and not Rules.ally(s, p, nd["owner"]):
			_show_gift_choice(from, n)
			return
		if kind != "":
			if kind != "take" or nd["kind"] != "mystery":
				_push_undo()
			Rules.send(s, p, from, n)
			info_node = -1
			if kind == "take":
				tip_override = "One critter hopped over and claimed %s! Click %s again to send everyone else who can go." % [nd["name"], nd["name"]]
			elif kind == "gift":
				tip_override = "A gift for the %s!" % Rules.owner_name(s, nd["owner"])
			else:
				tip_override = "They hopped to %s. Critters can hop %d planets per turn: the ones that just hopped twice rest there (zz)." % [nd["name"], Rules.MAX_HOPS] if Rules.movable(s, n) == 0 else "They hopped to %s. They can hop ONE more planet this turn: click %s, then where to go next." % [nd["name"], nd["name"]]
			selected = from if Rules.movable(s, from) > 0 else -1
			_after_change()
			return
	if nd["owner"] == p and Rules.movable(s, n) > 0:
		selected = n
		info_node = -1
		sound.play("select")
	else:
		selected = -1
		info_node = n
		if nd["owner"] == p:
			sound.play("invalid")
			if Rules.tired(nd) > 0 and nd["n"] > 1:
				tip_override = "The critters on %s already hopped %d times this turn. They rest (zz) until your next turn." % [nd["name"], Rules.MAX_HOPS]
			else:
				tip_override = "%s has only 1 critter. One always stays home, so it can't send anyone." % nd["name"]
	_refresh()


func _why_no_city(n: int) -> String:
	var nd: Dictionary = s["nodes"][n]
	var cost := Rules.city_cost(s, s["current"])
	if nd["owner"] != s["current"]:
		return "Cities go on YOUR planets."
	if nd["city"]:
		return "%s already has a city." % nd["name"]
	return "A city costs %d critters from the planet itself, and 1 must stay. %s needs at least %d critters." % [cost, nd["name"], cost + 1]


func _build_pressed() -> void:
	if not _is_human_turn() or not dance.is_empty():
		return
	pending_build = not pending_build
	pending_card = -1
	selected = -1
	tip_override = "Click one of your glowing planets to build a city there (costs %d critters from that planet)." % Rules.city_cost(s, s["current"]) if pending_build else ""
	_refresh()


func _place_all() -> void:
	if not _is_human_turn() or s["phase"] != "place":
		return
	var n := last_place
	if n < 0 or s["nodes"][n]["owner"] != s["current"]:
		n = AI.next_command(s, s["current"]).get("node", _cur()["home"])
	_push_undo()
	Rules.place(s, s["current"], n, _cur()["to_place"])
	last_place = n
	_after_change()
	_offer_city()


# =================================================================== dance-offs and friends

## The pop-up when you send critters at someone else's planet: dance-off or befriend?
func _show_dance_choice(from: int, to: int) -> void:
	var p: int = s["current"]
	var a: Dictionary = s["nodes"][from]
	var b: Dictionary = s["nodes"][to]
	var info := Rules.dance_info(s, from, to)
	var q: int = b["owner"]
	var v := _overlay(0.55)
	sound.play("popup")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	v.add_child(row)
	row.add_child(_side_card(p, info["att"], "from " + a["name"], info["ab"], ""))
	row.add_child(_label("vs", 54, GOLD, 10))
	var extra := ""
	if info["home"]:
		extra = "+1 city" if b["city"] else "+1 home"
	if info["friend"] >= 0:
		extra = ("%s  " % extra if extra != "" else "") + "with friend %s" % s["nodes"][info["friend"]]["name"]
	row.add_child(_side_card(q, info["def"], b["name"], info["db"] - (1 if info["home"] else 0), extra))
	var who := Rules.owner_name(s, q)
	var q_txt := "%s lives on %s." % [who.capitalize(), b["name"]]
	if q >= 0:
		q_txt = "The %s live on %s." % [who, b["name"]]
	v.add_child(_center(_label(q_txt + " What will you do?", 34, Color.WHITE)))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 26)
	v.add_child(btns)
	var go := _tinted(_button("Dance-off!", _choose_dance, 38, "icon_dice"), Color("c8562f"))
	go.custom_minimum_size = Vector2(340, 100)
	go.tooltip_text = "Roll dice until one side runs out. Win and they move in!"
	btns.add_child(go)
	if q >= 0 and s["mode"] == "ffa":
		var fr := _tinted(_button("Befriend", _choose_friend, 38, "icon_pinky"), Color("2f8f78"))
		fr.custom_minimum_size = Vector2(320, 100)
		fr.disabled = not Rules.can_befriend(s, p, from, to)
		fr.tooltip_text = "Ask to be friends: no dance-offs between you for %d rounds, and these two planets defend together." % Rules.FRIEND_ROUNDS
		btns.add_child(fr)
	var no := _button("Never mind", _close_overlay, 30)
	no.custom_minimum_size = Vector2(260, 100)
	btns.add_child(no)
	if q >= 0 and s["mode"] == "ffa":
		var why := "Befriend: no dance-offs between you for %d rounds. Anyone who attacks %s or %s has to beat BOTH planets' critters, but if they win, they get both!" % [Rules.FRIEND_ROUNDS, a["name"], b["name"]]
		if s["players"][p]["asked"]:
			why = "You already asked someone to be friends this turn."
		elif Rules.friend_of(s, from) >= 0 or Rules.friend_of(s, to) >= 0:
			why = "One of these planets already has a friend."
		v.add_child(_center(_wrap_label(why, 24, SOFT, 1100)))
	choice = {"from": from, "to": to}


## Sending critters to a friend's planet gives them away, so ask first.
func _show_gift_choice(from: int, to: int) -> void:
	var b: Dictionary = s["nodes"][to]
	var q: int = b["owner"]
	var v := _overlay(0.55)
	sound.play("popup")
	var pic := _icon("icon_pinky", 120)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	v.add_child(_center(_label("You and the %s are friends!" % Rules.owner_name(s, q), 48, Color("8ff5d2"), 10)))
	var left := Rules.friend_rounds(s, s["current"], q)
	v.add_child(_center(_wrap_label("Friends can't dance-off each other (%d more round%s, see the pink loop on the map). If you send critters to %s, they become %s critters: a gift." % [
		left, "" if left == 1 else "s", b["name"], Rules.owner_name(s, q)], 30, Color.WHITE, 1100)))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 26)
	v.add_child(btns)
	var give := _tinted(_button("Send a gift", func():
		_close_overlay()
		_push_undo()
		Rules.send(s, s["current"], from, to)
		selected = -1
		tip_override = "A gift for the %s!" % Rules.owner_name(s, q)
		_after_change(), 34, "icon_pinky"), Color("2f8f78"))
	give.custom_minimum_size = Vector2(320, 96)
	btns.add_child(give)
	var no := _green(_button("Never mind", func():
		_close_overlay()
		_refresh(), 34))
	no.custom_minimum_size = Vector2(300, 96)
	btns.add_child(no)


## Planets you could build a city on right now, biggest first.
func _city_spots() -> Array:
	var out: Array = []
	for nd in s["nodes"]:
		if Rules.can_build(s, s["current"], nd["id"]):
			out.append(nd["id"])
	out.sort_custom(func(a, b): return s["nodes"][a]["n"] > s["nodes"][b]["n"])
	return out


## At the start of your turn (and when you finish placing), offer a city on any
## planet that has enough critters, so nobody has to remember the button.
func _offer_city() -> void:
	if not offer_cities or not _is_human_turn() or tut_step >= 0 or overlay != null or not dance.is_empty():
		return
	var spots := _city_spots()
	var fresh := false
	for n in spots:
		if not city_offered.has(n):
			fresh = true
		city_offered[n] = true
	if not fresh:
		return
	var p: int = s["current"]
	var cost := Rules.city_cost(s, p)
	var v := _overlay(0.55)
	sound.play("offer")
	var pic := _icon("icon_city", 120)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	_bounce(pic, 10, 1.0)
	v.add_child(_center(_label("You can build a city!", 54, GOLD, 12)))
	v.add_child(_center(_wrap_label("A city costs %d critters from its own planet (1 stays). It makes +%d new critters there at the start of every one of your turns, and +1 when defending. Or keep the critters to grab more planets!" % [cost, Rules.CITY_MAKES], 28, Color.WHITE, 1100)))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 20)
	v.add_child(btns)
	for n in spots.slice(0, 3):
		var nd: Dictionary = s["nodes"][n]
		var b := _tinted(_button("City on %s (%d)" % [nd["name"], nd["n"]], _accept_city.bind(n), 30, "icon_city"), Color("a4692a"))
		b.custom_minimum_size = Vector2(0, 96)
		b.tooltip_text = "%s has %d critters: %d build the city, %d stay." % [nd["name"], nd["n"], cost, nd["n"] - cost]
		btns.add_child(b)
	var no := _button("Not now", func():
		_close_overlay()
		_refresh(), 30)
	no.custom_minimum_size = Vector2(240, 96)
	btns.add_child(no)


func _accept_city(n: int) -> void:
	_close_overlay()
	var p: int = s["current"]
	if not Rules.can_build(s, p, n):
		_refresh()
		return
	_push_undo()
	Rules.build_city(s, p, n)
	tip_override = "A city on %s! It makes %d new critters there at the start of every one of your turns." % [s["nodes"][n]["name"], Rules.CITY_MAKES]
	_after_change()


func _side_card(o: int, n: int, place_name: String, bonus: int, extra: String) -> Control:
	var pc := PanelContainer.new()
	var sb := _box(PANEL, 22, 6)
	sb.border_color = Rules.owner_color(s, o)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(380, 0)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(v)
	var pic: TextureRect
	if o >= 0:
		pic = _icon("critter_" + s["players"][o]["species"], 130)
	elif o == Rules.GLOOM:
		pic = _icon("gloom", 130)
	else:
		pic = _icon("icon_critter", 130)
		pic.modulate = Rules.WILD_COLOR
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	v.add_child(_center(_label("%d dancer%s" % [n, "" if n == 1 else "s"], 40, Rules.owner_color(s, o).lerp(Color.WHITE, 0.3), 8)))
	v.add_child(_center(_label(place_name, 26, SOFT)))
	var b := []
	if bonus > 0:
		b.append("+%d bigger crowd" % bonus)
	if extra != "":
		b.append(extra)
	v.add_child(_center(_label("  ".join(b) if b.size() > 0 else " ", 24, Color("8be08b"))))
	return pc


func _choose_dance() -> void:
	var from: int = choice.get("from", -1)
	var to: int = choice.get("to", -1)
	choice = {}
	_close_overlay()
	if from < 0:
		return
	_start_dance(from, to, false)


func _choose_friend() -> void:
	var from: int = choice.get("from", -1)
	var to: int = choice.get("to", -1)
	choice = {}
	_close_overlay()
	if from < 0:
		return
	_ask_friend(from, to, false)


## Start a dance-off that rolls by itself, one roll at a time.
func _start_dance(from: int, to: int, ai: bool) -> bool:
	if Rules.roll(s.duplicate(true), s["current"], from, to).is_empty():
		return false
	dance = {"from": from, "to": to, "ai": ai, "att_owner": s["current"], "def_owner": s["nodes"][to]["owner"],
		"def_name": s["nodes"][to]["name"], "att_name": s["nodes"][from]["name"]}
	dance_last = {}
	dance_tally = {"a": 0, "d": 0}
	sound.reset_streak()
	sound.play("dance")
	selected = -1
	info_node = -1
	pending_build = false
	dance_token += 1
	_clear(dance_refs["tally_a"])
	_clear(dance_refs["tally_d"])
	_refresh()
	get_tree().create_timer(0.35).timeout.connect(_dance_tick.bind(dance_token, gen))
	return true


func _dance_tick(tok: int, g: int) -> void:
	if tok != dance_token or g != gen or dance.is_empty() or s["over"]:
		return
	var r := Rules.roll(s, s["current"], dance["from"], dance["to"])
	if r.is_empty():
		_dance_done()
		return
	dance_last = r
	if not r.get("tie", false):
		var side := "a" if r["att_wins"] else "d"
		dance_tally[side] += 1
		var who: int = r["att_owner"] if r["att_wins"] else r["def_owner"]
		_add_tally(side, who)
	_after_change()
	_show_roll(r, true)
	if r["captured"] or r["att_left"] <= 0 or s["over"]:
		_dance_done()
		return
	get_tree().create_timer(AI_ROLL_EVERY if dance["ai"] else ROLL_EVERY).timeout.connect(_dance_tick.bind(tok, g))


func _add_tally(side: String, who: int) -> void:
	var box: Control = dance_refs["tally_" + side]
	var pic: TextureRect
	if who >= 0:
		pic = _icon("critter_" + s["players"][who]["species"], 40)
	elif who == Rules.GLOOM:
		pic = _icon("gloom", 40)
	else:
		pic = _icon("icon_critter", 40)
		pic.modulate = Rules.WILD_COLOR
	box.add_child(pic)
	pic.pivot_offset = Vector2(20, 20)
	pic.scale = Vector2(1.8, 1.8)
	var tw := pic.create_tween()
	tw.tween_property(pic, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Run away from your own dance-off (keeps the critters you still have).
func _stop_dance() -> void:
	if dance.is_empty() or dance["ai"]:
		return
	dance_token += 1
	sound.play("runaway")
	tip_override = "You stopped the dance-off. The critters that are left stay home."
	dance = {}
	_refresh()


func _dance_done() -> void:
	dance_token += 1
	var tok := dance_token
	var was_ai: bool = dance.get("ai", false)
	var r := dance_last
	get_tree().create_timer(1.6 if not was_ai else 1.1).timeout.connect(func():
		if tok != dance_token or dance.is_empty():
			return
		dance = {}
		if was_ai:
			_refresh()
			get_tree().create_timer(AI_DELAY).timeout.connect(_ai_step.bind(gen))
			return
		selected = -1
		if r.get("captured", false):
			var to: int = r["to"]
			tip_override = "%s is yours! The dancers moved in. Winning a planet counts as a hop." % s["nodes"][to]["name"]
		_refresh())


## Ask the owner of `to` to be friends. A computer decides right away; a person gets asked.
func _ask_friend(from: int, to: int, from_ai: bool) -> void:
	sound.play("ask")
	var p: int = s["current"]
	var q: int = s["nodes"][to]["owner"]
	var other: Dictionary = s["players"][q]
	if other["ai"]:
		if AI.accepts_friend(s, q, p):
			Rules.befriend(s, p, from, to)
			tip_override = "The computer %s said YES! You're friends for %d rounds." % [other["name"], Rules.FRIEND_ROUNDS]
		else:
			Rules.befriend_declined(s, p, q)
			sound.play("nothanks", 0.5)
			tip_override = "The computer %s said \"no thanks\". Maybe you're winning too much!" % other["name"]
		selected = -1
		_after_change()
		return
	var v := _overlay(0.9)
	var pics := HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	pics.add_theme_constant_override("separation", 30)
	v.add_child(pics)
	pics.add_child(_icon("critter_" + _cur()["species"], 180))
	pics.add_child(_icon("icon_pinky", 110))
	pics.add_child(_icon("critter_" + other["species"], 180))
	var asker: String = ("The computer " if from_ai else "The ") + _cur()["name"]
	v.add_child(_center(_label("%s, %s want to be friends!" % [other["name"], asker], 54, other["color"], 10)))
	v.add_child(_center(_wrap_label("No dance-offs between you for %d rounds. %s and %s defend together: anyone who attacks one has to beat both. But if they win, they get BOTH planets!" % [
		Rules.FRIEND_ROUNDS, s["nodes"][from]["name"], s["nodes"][to]["name"]], 30, SOFT, 1300)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	var yes := _green(_button("Be friends!", _friend_answer.bind(from, to, true, from_ai), 36, "icon_pinky"))
	yes.custom_minimum_size = Vector2(380, 96)
	row.add_child(yes)
	var no := _button("No thanks", _friend_answer.bind(from, to, false, from_ai), 36)
	no.custom_minimum_size = Vector2(300, 96)
	row.add_child(no)


func _friend_answer(from: int, to: int, yes: bool, from_ai: bool) -> void:
	var p: int = s["current"]
	if yes:
		Rules.befriend(s, p, from, to)
	else:
		Rules.befriend_declined(s, p, s["nodes"][to]["owner"])
		sound.play("nothanks")
	tip_override = ""
	selected = -1
	ai_waiting = false
	_close_overlay()
	_after_change()
	if from_ai:
		get_tree().create_timer(1.0).timeout.connect(_ai_step.bind(gen))


func _card_pressed(idx: int) -> void:
	if not _is_human_turn() or not dance.is_empty():
		return
	var p: int = s["current"]
	var c: String = _cur()["cards"][idx]
	if Rules.CARDS[c]["target"] == "own":
		pending_card = idx
		pending_build = false
		selected = -1
		tip_override = "%s: now click one of your planets." % Rules.CARDS[c]["name"]
		_refresh()
		return
	if Rules.play_card(s, p, idx):
		tip_override = Rules.CARDS[c]["tip"]
		_after_change()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed):
			_undo()
		elif event.keycode == KEY_H and _is_human_turn():
			_hint()
		elif event.keycode == KEY_ESCAPE:
			_deselect()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_deselect()


func _deselect() -> void:
	selected = -1
	info_node = -1
	pending_card = -1
	pending_build = false
	if not s.is_empty() and game_ui:
		_refresh()


# =================================================================== hints

func _hint() -> void:
	if not _is_human_turn() or not dance.is_empty():
		return
	var c := AI.next_command(s, s["current"])
	tip_override = "Hint: " + _describe(c)
	match c["cmd"]:
		"place", "build":
			board.hint_node = c["node"]
			if c["cmd"] == "place":
				last_place = c["node"]
		"send", "attack", "befriend":
			selected = c["from"]
			board.hint_from = c["from"]
			board.hint_node = c["to"]
		"card":
			if cards_box.get_child_count() > c["idx"]:
				_flash(cards_box.get_child(c["idx"]))
		"end":
			_flash(end_btn)
	_refresh()


func _describe(c: Dictionary) -> String:
	var nodes: Array = s["nodes"]
	match c["cmd"]:
		"place":
			var nd: Dictionary = nodes[c["node"]]
			if c.get("why", "") == "city":
				return "Put your new critters on %s, then build a city there with the Build button." % nd["name"]
			return "Put your new critters on %s (click it, or press Place all)." % nd["name"]
		"build":
			return "Build a city on %s: press Build a city, then click %s." % [nodes[c["node"]]["name"], nodes[c["node"]]["name"]]
		"send":
			var a: Dictionary = nodes[c["from"]]
			var b: Dictionary = nodes[c["to"]]
			if c.get("kind", "") == "take":
				return "Click %s, then %s. Nobody lives there, so one critter hops over and claims it!" % [a["name"], b["name"]]
			return "Move critters from %s to %s, closer to the action." % [a["name"], b["name"]]
		"attack":
			var a2: Dictionary = nodes[c["from"]]
			var b2: Dictionary = nodes[c["to"]]
			return "Dance-off! Click %s, then %s: %d dancers against %d." % [a2["name"], b2["name"], Rules.movable(s, c["from"]), Rules.defenders(s, c["to"])]
		"befriend":
			return "Ask the %s to be friends: click %s, then %s, and choose Befriend." % [Rules.owner_name(s, nodes[c["to"]]["owner"]), nodes[c["from"]]["name"], nodes[c["to"]]["name"]]
		"card":
			return "Play your %s card! %s" % [Rules.CARDS[c["card"]]["name"], Rules.CARDS[c["card"]]["tip"]]
	return "Looks like you're all done. Press Done!"


# =================================================================== HUD

func _build_game_ui() -> void:
	if game_ui:
		game_ui.queue_free()
	game_ui = Control.new()
	game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(game_ui)

	# top bar
	var top := Panel.new()
	top.size = Vector2(1920, 96)
	var tb := _box(Color("0b1b22"), 0, 0)
	tb.border_width_bottom = 4
	top.add_theme_stylebox_override("panel", tb)
	game_ui.add_child(top)
	var th := HBoxContainer.new()
	th.position = Vector2(16, 8)
	th.size = Vector2(1888, 80)
	th.add_theme_constant_override("separation", 18)
	top.add_child(th)
	var clock := HBoxContainer.new()
	clock.add_theme_constant_override("separation", 6)
	clock.add_child(_icon("icon_clock", 48))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -6)
	round_label = _label("", 28, GOLD)
	cv.add_child(round_label)
	rush_label = _label("STAR RUSH!", 20, Color("ff9ad1"))
	cv.add_child(rush_label)
	clock.add_child(cv)
	clock.custom_minimum_size = Vector2(210, 0)
	th.add_child(clock)
	chips_box = HBoxContainer.new()
	chips_box.add_theme_constant_override("separation", 12)
	th.add_child(chips_box)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp)
	status_box = HBoxContainer.new()
	status_box.add_theme_constant_override("separation", 18)
	status_box.alignment = BoxContainer.ALIGNMENT_END
	th.add_child(status_box)
	var gear := _button("Settings", _show_settings, 22)
	gear.custom_minimum_size = Vector2(120, 64)
	gear.tooltip_text = "Music, sound effects and the gentle pulse"
	th.add_child(gear)
	var help := _button("?", _show_how_to, 32)
	help.custom_minimum_size = Vector2(64, 64)
	help.tooltip_text = "How to play"
	th.add_child(help)
	var menu := _button("Menu", _confirm_menu, 24)
	menu.custom_minimum_size = Vector2(100, 64)
	th.add_child(menu)

	# right panel
	var side := PanelContainer.new()
	side.position = Vector2(1500, 96)
	side.size = Vector2(420, 984)
	var sb := _box(Color("0b1b22"), 0, 0)
	sb.border_width_left = 4
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	side.add_theme_stylebox_override("panel", sb)
	game_ui.add_child(side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	side.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	turn_portrait = _icon("critter_blorb", 84)
	head.add_child(turn_portrait)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	head.add_child(hv)
	turn_name = _label("", 32, Color.WHITE)
	hv.add_child(turn_name)
	turn_sub = _label("", 22, SOFT)
	hv.add_child(turn_sub)

	# the three steps
	step_rows.clear()
	var titles := ["1  Place critters & build", "2  Send critters (2 hops)", "3  Lucky Cards"]
	for i in 3:
		if i == 2 and not Rules.full_rules(s):
			break
		var pc := PanelContainer.new()
		var ps := _box(PANEL, 14, 3)
		ps.content_margin_top = 6
		ps.content_margin_bottom = 8
		pc.add_theme_stylebox_override("panel", ps)
		v.add_child(pc)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 2)
		pc.add_child(pv)
		var tl := _label(titles[i], 26, Color.WHITE)
		pv.add_child(tl)
		var dl := _wrap_label("", 21, SOFT, 350)
		pv.add_child(dl)
		if i == 0:
			var prow := HBoxContainer.new()
			prow.add_theme_constant_override("separation", 6)
			pv.add_child(prow)
			place_all_btn = _button("Place all", _place_all, 22)
			place_all_btn.custom_minimum_size = Vector2(0, 46)
			place_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prow.add_child(place_all_btn)
			build_btn = _tinted(_button("Build a city", _build_pressed, 22, "icon_city"), Color("a4692a"))
			build_btn.custom_minimum_size = Vector2(0, 46)
			build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prow.add_child(build_btn)
		if i == 2:
			cards_box = GridContainer.new()
			cards_box.columns = 2
			cards_box.add_theme_constant_override("h_separation", 6)
			cards_box.add_theme_constant_override("v_separation", 6)
			pv.add_child(cards_box)
		step_rows.append([pc, tl, dl])
	if cards_box and not Rules.full_rules(s):
		cards_box = null

	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info_box)
	_build_dance_box(v)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	hint_btn = _button("Hint", _hint, 26, "icon_bulb")
	hint_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_btn.custom_minimum_size = Vector2(0, 60)
	brow.add_child(hint_btn)
	undo_btn = _button("Undo", _undo, 26)
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.custom_minimum_size = Vector2(0, 60)
	brow.add_child(undo_btn)
	end_btn = _green(_button("Done", _end_turn_pressed, 38))
	end_btn.custom_minimum_size = Vector2(0, 84)
	v.add_child(end_btn)

	# tip bar
	var bot := Panel.new()
	bot.position = Vector2(0, 1000)
	bot.size = Vector2(1500, 80)
	var bb := _box(Color("0b1b22"), 0, 0)
	bb.border_width_top = 4
	bot.add_theme_stylebox_override("panel", bb)
	game_ui.add_child(bot)
	tip_label = _label("", 27, Color("e8fff8"))
	tip_label.position = Vector2(24, 0)
	tip_label.size = Vector2(1450, 80)
	tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bot.add_child(tip_label)

	# Learn to Play coach
	coach = PanelContainer.new()
	var cs := _box(Color("123039"), 22, 5)
	cs.border_color = GOLD
	cs.content_margin_left = 20
	cs.content_margin_right = 20
	coach.add_theme_stylebox_override("panel", cs)
	coach.position = Vector2(20, 760)
	coach.custom_minimum_size = Vector2(1040, 0)
	coach.visible = false
	game_ui.add_child(coach)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 16)
	coach.add_child(ch)
	var cpic := _icon("critter_blorb", 110)
	ch.add_child(cpic)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 8)
	ch.add_child(cvb)
	coach_text = _wrap_label("", 27, Color.WHITE, 860)
	cvb.add_child(coach_text)
	coach_btns = HBoxContainer.new()
	coach_btns.add_theme_constant_override("separation", 14)
	cvb.add_child(coach_btns)


func _build_dance_box(parent: Control) -> void:
	dance_box = VBoxContainer.new()
	dance_box.add_theme_constant_override("separation", 8)
	dance_box.visible = false
	parent.add_child(dance_box)
	var title := _label("Dance-off!", 34, GOLD, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dance_box.add_child(title)
	var sides := HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 10)
	dance_box.add_child(sides)
	for side in ["a", "d"]:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_theme_constant_override("separation", 4)
		col.custom_minimum_size = Vector2(170, 0)
		sides.add_child(col)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 6)
		col.add_child(top)
		var pic := _icon("icon_critter", 46)
		top.add_child(pic)
		var cnt := _label("", 30, Color.WHITE, 6)
		top.add_child(cnt)
		var who := _label("", 20, SOFT)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(who)
		var dice := HBoxContainer.new()
		dice.alignment = BoxContainer.ALIGNMENT_CENTER
		dice.add_theme_constant_override("separation", 4)
		col.add_child(dice)
		var d1 := DieFace.new()
		dice.add_child(d1)
		var d2 := DieFace.new()
		d2.custom_minimum_size = Vector2(56, 56)
		d2.visible = false
		dice.add_child(d2)
		var bonus := _label("", 22, Color("8be08b"))
		bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(bonus)
		# one critter appears on the side that won each roll
		var tally := HFlowContainer.new()
		tally.add_theme_constant_override("h_separation", 2)
		tally.add_theme_constant_override("v_separation", 2)
		tally.custom_minimum_size = Vector2(170, 44)
		col.add_child(tally)
		dance_refs["tally_" + side] = tally
		dance_refs[side] = {"pic": pic, "cnt": cnt, "who": who, "d1": d1, "d2": d2, "bonus": bonus}
		if side == "a":
			var vs := _label("vs", 30, GOLD)
			vs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			sides.add_child(vs)
	var res := _wrap_label("", 23, Color.WHITE, 380)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dance_box.add_child(res)
	dance_refs["result"] = res
	var stop := _button("Run away!", _stop_dance, 24)
	stop.custom_minimum_size = Vector2(0, 60)
	stop.tooltip_text = "Stop the dance-off. Your critters that are left stay home."
	dance_box.add_child(stop)
	dance_refs["stop"] = stop
	var rules_l := _wrap_label("The dice roll by themselves. Bigger number wins, ties: defender. The loser of each roll loses a critter. Bigger crowd +1, twice as big +2. Homes & nests +1.", 18, Color("a3c3c6"), 380)
	dance_box.add_child(rules_l)


func _refresh() -> void:
	if game_ui == null or s.is_empty():
		return
	var p: int = s["current"]
	var pl := _cur()
	var human := _is_human_turn()

	round_label.text = "Round %d / %d" % [s["round"], s["max_rounds"]]
	rush_label.visible = Rules.star_rush(s)

	_clear(chips_box)
	if s["mode"] == "teams":
		for team in [0, 1]:
			var tbox := PanelContainer.new()
			var tsb := _box(Color("0f2229"), 14, 3)
			tsb.content_margin_top = 4
			tsb.content_margin_bottom = 4
			tsb.content_margin_left = 8
			tsb.content_margin_right = 8
			tbox.add_theme_stylebox_override("panel", tsb)
			chips_box.add_child(tbox)
			var thb := HBoxContainer.new()
			thb.add_theme_constant_override("separation", 8)
			tbox.add_child(thb)
			thb.add_child(_icon_text("planet_0", "%d" % Rules.team_planets(s, team), 24, GOLD))
			for q in s["players"]:
				if q["team"] == team:
					thb.add_child(_chip(q))
	else:
		for q in s["players"]:
			chips_box.add_child(_chip(q))

	_clear(status_box)
	if s["gloom"]:
		var g := Rules.gloom_count(s)
		var lim: int = s["gloom_limit"]
		var gcol := Color("ff9a7a") if g >= lim - 2 else Color("b6d6d0")
		var gl := _icon_text("gloom", "Gloom %d / %d" % [g, lim], 26, gcol)
		gl.tooltip_text = "If the Gloom covers %d planets, everybody loses!" % lim
		status_box.add_child(gl)
	var goal := "Chase out the Gloom!" if s["mode"] == "coop" else "Get every planet!"
	status_box.add_child(_label(goal, 24, SOFT))

	# side header
	turn_portrait.texture = tex["critter_" + pl["species"]]
	var who: String = pl["name"]
	if pl["ai"]:
		who = "Computer " + who
	turn_name.text = "%s' turn" % who
	turn_name.add_theme_color_override("font_color", pl["color"])
	turn_sub.text = "%d planets   %d critters" % [Rules.planets(s, p), Rules.critters(s, p)]

	# steps (hidden while a dance-off fills the panel)
	var phase: String = s["phase"]
	for i in step_rows.size():
		var row: Array = step_rows[i]
		(row[0] as Control).visible = dance.is_empty()
		var active := (i == 0 and phase == "place") or (i == 1 and phase == "go") or (i == 2 and phase == "go")
		var ps := _box(Color("133039") if active and human else PANEL, 14, 4 if active and human else 2)
		ps.border_color = pl["color"] if active and human else Color("25444d")
		ps.content_margin_top = 6
		ps.content_margin_bottom = 8
		row[0].add_theme_stylebox_override("panel", ps)
		(row[1] as Label).add_theme_color_override("font_color", Color.WHITE if active else Color("86a9ad"))
		var dl: Label = row[2]
		match i:
			0:
				var cost := Rules.city_cost(s, p)
				if phase == "place":
					dl.text = "%d new critter%s: click your glowing planets. A city costs %d critters from its planet and makes +%d there every turn." % [
						pl["to_place"], "" if pl["to_place"] == 1 else "s", cost, Rules.CITY_MAKES]
				else:
					dl.text = "All placed. You can still build a city (%d critters)." % cost
			1:
				if phase == "place":
					dl.text = "After placing, send critters next door. Each critter can hop 2 planets."
				else:
					dl.text = "Click your planet, then a neighbour. Green: grab it (1 critter hops) or move. Orange: dance-off or befriend!"
			2:
				dl.text = "Win a planet this turn to find a card." if pl["cards"].is_empty() else "Click a card to use it."
				if pl["lucky"]:
					dl.text = "Lucky Dice on: you roll 2 dice!"
	place_all_btn.disabled = not human or phase != "place"
	var can_any_city := false
	for nd in s["nodes"]:
		if Rules.can_build(s, p, nd["id"]):
			can_any_city = true
	build_btn.disabled = not human or not dance.is_empty() or (not can_any_city and not pending_build)
	build_btn.text = "Pick a planet..." if pending_build else "Build a city"
	build_btn.tooltip_text = "Costs %d critters from the planet you pick (1 must stay). Makes +%d critters there at the start of each of your turns." % [Rules.city_cost(s, p), Rules.CITY_MAKES]
	if cards_box:
		_clear(cards_box)
		for i in pl["cards"].size():
			var c: String = pl["cards"][i]
			var info: Dictionary = Rules.CARDS[c]
			var b := _tinted(_button(info["name"], _card_pressed.bind(i), 19, info["icon"]), Color("4e62c9"))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(170, 48)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = info["tip"]
			b.disabled = not human or not dance.is_empty() or (info["target"] == "" and not Rules.can_play(s, p, i))
			if i == pending_card:
				_selected_style(b)
			cards_box.add_child(b)
	undo_btn.disabled = not human or undo_stack.is_empty() or not dance.is_empty()
	hint_btn.disabled = not human or not dance.is_empty()
	end_btn.disabled = not human or not dance.is_empty()
	end_btn.text = "Done" if phase == "go" else "Done (skip placing)"

	# board highlights
	board.selected_node = selected
	board.targets = {}
	board.place_nodes = {}
	board.card_nodes = {}
	board.city_nodes = {}
	if human and dance.is_empty() and tut_step < 0:
		for n in _city_spots():
			board.city_nodes[n] = true
	if human and dance.is_empty():
		if pending_card >= 0:
			for nd in s["nodes"]:
				if Rules.can_play(s, p, pending_card, nd["id"]):
					board.card_nodes[nd["id"]] = true
		elif pending_build:
			for nd in s["nodes"]:
				if Rules.can_build(s, p, nd["id"]):
					board.card_nodes[nd["id"]] = true
		elif phase == "place":
			for nd in s["nodes"]:
				if nd["owner"] == p:
					board.place_nodes[nd["id"]] = true
		elif selected >= 0:
			board.targets = Rules.targets(s, p, selected)
	_refresh_info()
	_refresh_dance()
	_refresh_tip()
	_tut_update()


func _chip(q: Dictionary) -> Control:
	var c := PanelContainer.new()
	var cur: bool = q["id"] == s["current"]
	var cs := _box(Color("133039") if cur else Color("0e2129"), 14, 4)
	cs.border_color = q["color"] if cur else Color("25444d")
	cs.content_margin_top = 2
	cs.content_margin_bottom = 2
	cs.content_margin_left = 8
	cs.content_margin_right = 10
	c.add_theme_stylebox_override("panel", cs)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	c.add_child(h)
	var pic := _icon("critter_" + q["species"], 56)
	if q["out"]:
		pic.modulate = Color(1, 1, 1, 0.3)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -6)
	h.add_child(v)
	v.add_child(_icon_text("planet_0", str(Rules.planets(s, q["id"])), 22, GOLD))
	var cr := _icon_text("icon_critter", str(Rules.critters(s, q["id"])), 22, Color("d4e6e2"))
	v.add_child(cr)
	if Rules.full_rules(s) and q["cards"].size() > 0:
		h.add_child(_icon_text("icon_card", str(q["cards"].size()), 20, Color("bfe0ff")))
	# friendships: a pink heart with the rounds left, on both friends' chips
	for o in s["players"]:
		if o["id"] != q["id"] and Rules.truce(s, q["id"], o["id"]):
			var left := Rules.friend_rounds(s, q["id"], o["id"])
			var hp := _icon_text("icon_pinky", str(left), 22, Color("8ff5d2"))
			hp.tooltip_text = "Friends with the %s for %d more round%s" % [o["name"], left, "" if left == 1 else "s"]
			h.add_child(hp)
	c.tooltip_text = "%s: %d planets, %d critters" % [q["name"], Rules.planets(s, q["id"]), Rules.critters(s, q["id"])]
	return c


func _refresh_info() -> void:
	_clear(info_box)
	info_box.visible = dance.is_empty()
	if not dance.is_empty():
		return
	if not _is_human_turn():
		info_box.add_child(_wrap_label("Watching the computer play...", 24, SOFT))
		return
	var n := info_node if info_node >= 0 else selected
	if n >= 0:
		var nd: Dictionary = s["nodes"][n]
		info_box.add_child(_label(nd["name"], 30, Color.WHITE))
		info_box.add_child(_wrap_label(_node_text(nd), 21, SOFT))
		if n == selected:
			var tg := Rules.targets(s, s["current"], n)
			var k := tg.size()
			var mv := Rules.movable(s, n)
			var resting: int = maxi(0, Rules.tired(nd) - 1)
			var txt := "Ready to send %d critter%s (1 stays%s). %d place%s to go." % [
				mv, "" if mv == 1 else "s", (", %d resting" % resting) if resting > 0 else "", k, "" if k == 1 else "s"]
			info_box.add_child(_wrap_label(txt, 21, Color("8be08b")))


func _node_text(nd: Dictionary) -> String:
	var parts: Array = []
	var o: int = nd["owner"]
	var who := Rules.owner_name(s, o)
	match nd["kind"]:
		"home":
			parts.append("A home planet. +1 when defending a dance-off.")
		"golden":
			parts.append("Golden planet: its owner gets +1 extra critter every turn.")
		"mystery":
			parts.append("Mystery planet! Whoever wins it first finds a surprise.")
		"nest":
			parts.append("A Gloom nest. Fog critters here get +1 when defending." if o == Rules.GLOOM else "An old Gloom nest.")
	if o == Rules.WILD:
		if nd["n"] == 0:
			parts.append("Nobody lives here. Send critters to grab it!")
		else:
			parts.append("%d wild critter%s live here. Win a dance-off to make it yours." % [nd["n"], "" if nd["n"] == 1 else "s"])
	elif o == Rules.GLOOM:
		parts.append("Covered in Gloom: %d fog critters. Chase them out!" % nd["n"])
	else:
		parts.append("The %s live here: %d critter%s." % [who, nd["n"], "" if nd["n"] == 1 else "s"])
	if nd["city"]:
		parts.append(("It has a CITY: +%d critters here at the start of each of its owner's turns, and +1 when defending. If someone wins this planet, the city is knocked down." % Rules.CITY_MAKES) if o >= 0 else "There's an old city here. Win it back to make it work again!")
	var f := Rules.friend_of(s, nd["id"])
	if f >= 0:
		parts.append("Friends with %s: they defend together (%d critters)." % [s["nodes"][f]["name"], Rules.defenders(s, nd["id"])])
	if Rules.hopped(nd) > 0 and o == s["current"]:
		var tr := Rules.tired(nd)
		var once := Rules.hopped(nd) - tr
		if once > 0:
			parts.append("%d critter%s hopped here this turn and can hop once more." % [once, "" if once == 1 else "s"])
		if tr > 0:
			parts.append("%d critter%s already hopped %d times and %s resting (zz)." % [tr, "" if tr == 1 else "s", Rules.MAX_HOPS, "is" if tr == 1 else "are"])
	if nd["shield"] >= 0:
		parts.append("Force Field! Nobody can dance-off here until the %s' next turn." % Rules.owner_name(s, nd["shield"]))
	return " ".join(parts)


func _refresh_dance() -> void:
	dance_box.visible = not dance.is_empty()
	if dance.is_empty():
		return
	var from: int = dance["from"]
	var to: int = dance["to"]
	var captured: bool = dance_last.get("captured", false)
	var att_n: int = Rules.movable(s, from) if not captured else s["nodes"][to]["n"]
	var def_n: int = 0 if captured else Rules.defenders(s, to)
	_dance_side("a", dance["att_owner"], att_n, dance["att_name"])
	_dance_side("d", dance["def_owner"], def_n, dance["def_name"])
	if dance_last.is_empty():
		var info := Rules.dance_info(s, from, to)
		dance_refs["a"]["bonus"].text = "+%d crowd" % info["ab"] if info["ab"] > 0 else ""
		var db := []
		if info["db"] - (1 if info["home"] else 0) > 0:
			db.append("+%d crowd" % (info["db"] - (1 if info["home"] else 0)))
		if info["home"]:
			db.append("+1 city" if s["nodes"][dance["to"]]["city"] else "+1 home")
		dance_refs["d"]["bonus"].text = "  ".join(db)
		dance_refs["a"]["d2"].visible = info["lucky"]
		var fr := ""
		if info["friend"] >= 0:
			fr = " %s's friend %s helps defend!" % [dance["def_name"], s["nodes"][info["friend"]]["name"]]
		dance_refs["result"].text = "Here we go! %d vs %d.%s" % [info["att"], info["def"], fr]
		(dance_refs["result"] as Label).add_theme_color_override("font_color", Color.WHITE)
	dance_refs["stop"].visible = not dance["ai"] and _is_human_turn()
	dance_refs["stop"].disabled = dance_last.get("captured", false) or dance_last.get("att_left", 1) <= 0


func _dance_side(side: String, o: int, n: int, place_name: String) -> void:
	var r: Dictionary = dance_refs[side]
	var pic: TextureRect = r["pic"]
	if o >= 0:
		pic.texture = tex["critter_" + s["players"][o]["species"]]
		pic.modulate = Color.WHITE
	elif o == Rules.GLOOM:
		pic.texture = tex["gloom"]
		pic.modulate = Color.WHITE
	else:
		pic.texture = tex["icon_critter"]
		pic.modulate = Rules.WILD_COLOR
	r["cnt"].text = str(maxi(n, 0))
	r["who"].text = ("%s\n%s" % [Rules.owner_name(s, o).capitalize(), place_name]) if side == "d" else ("%s\nfrom %s" % [Rules.owner_name(s, o).capitalize(), place_name])
	(r["d1"] as DieFace).col = Rules.owner_color(s, o).lerp(Color.WHITE, 0.55)
	(r["d2"] as DieFace).col = (r["d1"] as DieFace).col
	(r["d1"] as DieFace).queue_redraw()


func _show_roll(r: Dictionary, tumble: bool) -> void:
	_refresh_dance()
	if r.is_empty() or dance.is_empty():
		return
	var ra: Dictionary = dance_refs["a"]
	var rd: Dictionary = dance_refs["d"]
	(ra["d1"] as DieFace).show_value(r["ad"], tumble)
	(ra["d2"] as DieFace).visible = r["ad2"] > 0
	if r["ad2"] > 0:
		(ra["d2"] as DieFace).show_value(r["ad2"], tumble)
		(ra["d1"] as DieFace).dim = r["ad2"] > r["ad"]
		(ra["d2"] as DieFace).dim = r["ad2"] <= r["ad"]
	else:
		(ra["d1"] as DieFace).dim = false
	(rd["d1"] as DieFace).show_value(r["dd"], tumble)
	ra["bonus"].text = "%d +%d = %d" % [maxi(r["ad"], r["ad2"]), r["ab"], r["att_total"]] if r["ab"] > 0 else "= %d" % r["att_total"]
	rd["bonus"].text = "%d +%d = %d" % [r["dd"], r["db"], r["def_total"]] if r["db"] > 0 else "= %d" % r["def_total"]
	var an := Rules.owner_name(s, r["att_owner"]).capitalize()
	var dn := Rules.owner_name(s, r["def_owner"]).capitalize()
	var txt := ""
	if r["captured"]:
		txt = "%s win %s!" % [an, s["nodes"][r["to"]]["name"]]
		if r["friend"] >= 0:
			txt = "%s win %s AND %s!" % [an, s["nodes"][r["to"]]["name"], s["nodes"][r["friend"]]["name"]]
	elif r.get("tie", false):
		txt = "A tie! Nobody loses a critter. Roll again!"
	elif r["att_wins"]:
		txt = "%s win this roll%s! %s lose a critter." % [an, " (a tie goes to the attacker)" if r["att_total"] == r["def_total"] else "", dn]
	else:
		txt = "%s win this roll! %s lose a critter." % [dn, an]
	if not r["captured"] and r["att_left"] <= 0:
		txt += " No dancers left, %s hold on!" % dn
	(dance_refs["result"] as Label).text = txt
	var res: Label = dance_refs["result"]
	res.add_theme_color_override("font_color", GOLD if r["captured"] else Color.WHITE)


func _refresh_tip() -> void:
	if tip_override != "":
		tip_label.text = tip_override
		return
	var lg: Array = s["log"]
	var pl := _cur()
	if _is_human_turn() and pl["cadet"] and dance.is_empty() and pending_card < 0:
		var c := AI.next_command(s, s["current"])
		tip_label.text = "Idea: " + _describe(c)
		match c["cmd"]:
			"place":
				board.hint_node = c["node"]
			"send", "attack":
				board.hint_from = c["from"]
				board.hint_node = c["to"]
		return
	if lg.size() > 0:
		tip_label.text = lg[lg.size() - 1]["text"]
	else:
		tip_label.text = "Welcome to Star Critters!"


# =================================================================== Learn to Play

## Each step: text, highlighted planets, and either a "Next" button or a condition to wait for.
func _tut_steps() -> Array:
	return [
		{"text": "Hi! I'm Coach Blorb. Let's learn Star Critters! You are the pink Blorbs. A pink ring means the planet is yours, and the number shows how many critters live there.",
			"hl": [0], "next": "Next"},
		{"text": "Every turn has 3 steps. Step 1: you get NEW critters. Click your Home planet to put them there, one click each (or press Place all).",
			"hl": [0], "wait": func(): return s["phase"] == "go"},
		{"text": "Now build a CITY! Press 'Build a city', then click Home. It costs 5 critters, but the city makes 2 new critters on Home at the start of EVERY turn. Grow cities, or spend critters grabbing planets: your choice!",
			"hl": [0], "wait": func(): return s["nodes"][0]["city"]},
		{"text": "Step 2: send critters. Click Home, then Pebble next door (green ring). Nobody lives on Pebble, so one critter hops over and claims it!",
			"hl": [0, 1], "wait": func(): return s["nodes"][1]["owner"] == 0},
		{"text": "Pebble is yours! Each critter can hop TWO planets per turn, then it rests (zz). Press Done to end your turn and watch the Zibbits take theirs.",
			"hl": [], "wait": func(): return s["round"] >= 2 and s["current"] == 0},
		{"text": "Your city made 2 new critters on Home! Now put your new critters on Pebble: we're going to need them there.",
			"hl": [1], "wait": func(): return s["phase"] == "go"},
		{"text": "Goldie (the golden planet) has 3 wild critters. Click Pebble, then Goldie (orange ring), and choose Dance-off!",
			"hl": [1, 3], "wait": func(): return dance.get("to", -1) == 3 or s["nodes"][3]["owner"] == 0},
		{"text": "DANCE-OFF! The dice roll by themselves. The bigger number wins (a tie goes to the attacker) and the loser loses one critter. Watch the little critters line up on the side that won each roll!",
			"hl": [3], "wait": func(): return s["nodes"][3]["owner"] == 0 and dance.is_empty()},
		{"text": "You won Goldie! Golden planets give +1 extra critter every turn. See how the lane between your planets turned pink? That's your territory. The ? planet is a Mystery: whoever wins it first finds a surprise!",
			"hl": [3, 4], "next": "Next"},
		{"text": "When you send critters at ANOTHER player's planet (like the Zibbits), you get a choice: Dance-off, or Befriend. Friends can't dance-off each other for 3 rounds, and the two planets defend together. But if someone beats them, they win BOTH!",
			"hl": [6], "next": "Next"},
		{"text": "See the grey fog at the top? That's the GLOOM. It's not a player, it's a fog army that grows every round and grabs planets. If it covers too much of the galaxy (see top right), EVERYBODY loses. So even rivals sometimes team up to push it back!",
			"hl": [7], "next": "Next"},
		{"text": "You won a planet this turn, so you'll find a Lucky Card when your turn ends. Press Done.",
			"hl": [], "wait": func(): return s["round"] >= 3 and s["current"] == 0},
		{"text": "Look at step 3 on the right: a Lucky Card! Click one to use it (Rocket Boost, Lucky Dice, Force Field or Instant City). Cards are a bit of luck that can turn a game around.",
			"hl": [], "next": "Next"},
		{"text": "That's it! Win by owning EVERY planet, or have the most planets when the Star Clock (top left) runs out. Keep playing this practice game, or head back to the menu.",
			"hl": [], "next": "Keep playing", "menu": true},
	]


func _tut_update() -> void:
	if coach == null:
		return
	if tut_step < 0 or s.is_empty() or not s.get("tutorial", false):
		coach.visible = false
		return
	var steps := _tut_steps()
	if tut_step >= steps.size():
		coach.visible = false
		return
	var st: Dictionary = steps[tut_step]
	# help out if the dance-off went badly
	if tut_step in [6, 7] and dance.is_empty() and s["nodes"][1]["owner"] == 0 and Rules.movable(s, 1) < 2 and s["nodes"][3]["owner"] != 0 and s["phase"] == "go":
		s["nodes"][1]["n"] += 4
		board.float_text(s["nodes"][1]["pos"], "+4 from Coach!", GOLD)
		board.set_state(s, false)
	if st.has("wait") and (st["wait"] as Callable).call():
		tut_step += 1
		board.hint_node = -1
		board.hint_from = -1
		_tut_update()
		return
	coach.visible = true
	coach_text.text = st["text"]
	_clear(coach_btns)
	if st.has("next"):
		var b := _green(_button(st["next"], _tut_next, 28))
		b.custom_minimum_size = Vector2(220, 64)
		coach_btns.add_child(b)
	if st.get("menu", false):
		var m := _button("Menu", _show_setup_reset, 28)
		m.custom_minimum_size = Vector2(200, 64)
		coach_btns.add_child(m)
	var hl: Array = st["hl"]
	if hl.size() > 0 and board.hint_node < 0:
		board.hint_node = hl[hl.size() - 1]
		board.hint_from = hl[0] if hl.size() > 1 else -1


func _tut_next() -> void:
	tut_step += 1
	board.hint_node = -1
	board.hint_from = -1
	_refresh()


# =================================================================== overlays

func _overlay(dim := 0.82) -> VBoxContainer:
	_close_overlay()
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.12, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(c)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	c.add_child(v)
	board.input_enabled = false
	return v


func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	if not s.is_empty() and not s["over"]:
		board.input_enabled = _is_human_turn()


func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _show_turn_splash(news: Array) -> void:
	var pl := _cur()
	var v := _overlay(0.88)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(240, 240)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(holder)
	var pic := _icon("critter_" + pl["species"], 240)
	holder.add_child(pic)
	_bounce(pic, 16, 1.0)
	v.add_child(_center(_label("%s, it's your turn!" % pl["name"], 68, pl["color"], 14)))
	var info := "Round %d of %d   -   %d new critters to place" % [s["round"], s["max_rounds"], pl["to_place"]]
	v.add_child(_center(_label(info, 32, SOFT)))
	if Rules.star_rush(s):
		v.add_child(_center(_label("STAR RUSH! Everyone gets +%d critters in the last rounds!" % Rules.RUSH_BONUS, 30, Color("ff9ad1"))))
	if not s["cosmic"].is_empty() and s["cosmic"]["id"] != "calm":
		v.add_child(_center(_label("Space news: %s! %s" % [s["cosmic"]["name"], s["cosmic"]["text"]], 30, GOLD)))
	if news.size() > 0:
		var box := PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(box)
		var nv := VBoxContainer.new()
		box.add_child(nv)
		nv.add_child(_label("While you were away:", 26, GOLD))
		for t in news:
			nv.add_child(_wrap_label("- " + t, 24, Color("e8fff8"), 1100))
	var b := _green(_button("Let's go!", func():
		_close_overlay()
		_offer_city(), 44))
	b.custom_minimum_size = Vector2(360, 96)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


func _show_game_over() -> void:
	var v := _overlay(0.85)
	var pics := HBoxContainer.new()
	pics.alignment = BoxContainer.ALIGNMENT_CENTER
	pics.add_theme_constant_override("separation", 30)
	v.add_child(pics)
	var title := ""
	var sub := ""
	var col := GOLD
	var show: Array = []
	var res: String = s["result"]
	var names: Array = []
	for w in s["winners"]:
		show.append(s["players"][w])
		names.append(s["players"][w]["name"])
	sound.play("loseall" if res == "gloom" or (s["mode"] == "coop" and res != "win") else "win")
	if res == "gloom":
		title = "The Gloom got too big!"
		sub = "Everybody loses this time. Next time, team up against it sooner!"
		col = Color("b6d6d0")
		show = s["players"]
	elif s["mode"] == "coop":
		show = s["players"]
		if res == "win":
			title = "You saved the galaxy!"
			sub = "Every bit of Gloom is gone. Hooray!"
		else:
			title = "The Star Clock ran out..."
			sub = "The Gloom is still hiding out there. Try again!"
			col = Color("b6d6d0")
	else:
		var who := " & ".join(names)
		if show.size() == 0:
			title = "Game over"
		elif s["mode"] != "teams" and show.size() > 1:
			title = "It's a tie: %s!" % who
		else:
			title = "The %s win!" % who
		match res:
			"conquer":
				sub = "They own the WHOLE galaxy!"
			"last":
				sub = "They're the last ones standing!"
			"clock":
				sub = "The Star Clock ran out and they had the most planets."
	for q in show:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(200, 220)
		pics.add_child(holder)
		var pic := _icon("critter_" + q["species"], 200)
		holder.add_child(pic)
		_bounce(pic, 24, 0.6 + randf() * 0.3)
		if res == "gloom" or (s["mode"] == "coop" and res != "win"):
			pic.modulate = Color(0.6, 0.6, 0.75)
	v.add_child(_center(_label(title, 76, col, 16)))
	v.add_child(_center(_label(sub, 32, SOFT)))
	var board_box := VBoxContainer.new()
	board_box.add_theme_constant_override("separation", 6)
	v.add_child(board_box)
	var order: Array = s["players"].duplicate()
	order.sort_custom(func(a, b): return _final_planets(a) > _final_planets(b))
	for q in order:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		row.add_child(_icon("critter_" + q["species"], 52))
		row.add_child(_label(q["name"], 30, q["color"]))
		row.add_child(_icon_text("planet_0", "%d planets" % _final_planets(q), 30, GOLD))
		board_box.add_child(row)
	if s["gloom"]:
		board_box.add_child(_center(_label("Gloom: %d planets" % Rules.gloom_count(s), 26, Color("b6d6d0"))))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 30)
	v.add_child(row2)
	var again := _green(_button("Play again", _play_again, 36))
	again.custom_minimum_size = Vector2(320, 90)
	row2.add_child(again)
	var menu := _button("Main menu", _show_setup_reset, 36)
	menu.custom_minimum_size = Vector2(320, 90)
	row2.add_child(menu)


func _final_planets(q: Dictionary) -> int:
	if q.has("final"):
		return q["final"][0]
	return Rules.planets(s, q["id"])


func _play_again() -> void:
	if last_cfg.get("tutorial", false):
		_start_tutorial()
		return
	var cfg := last_cfg.duplicate(true)
	cfg["seed"] = randi() % 1000000
	start_game(cfg)


func _show_setup_reset() -> void:
	s = {}
	gen += 1
	tut_step = -1
	_show_setup()


func _confirm_menu() -> void:
	var v := _overlay(0.8)
	v.add_child(_center(_label("Leave this game and go back to the menu?", 48, Color.WHITE, 10)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	var stay := _button("Keep playing", _close_overlay, 34)
	stay.custom_minimum_size = Vector2(320, 90)
	row.add_child(stay)
	var leave := _button("Leave game", _show_setup_reset, 34)
	leave.custom_minimum_size = Vector2(320, 90)
	row.add_child(leave)


func _show_how_to() -> void:
	var v := _overlay(0.94)
	v.add_child(_center(_label("How to play", 60, GOLD, 12)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var rows := [
		["icon_critter", "Planets hold critters. The ring colour shows who owns it, the number shows how many live there. Lanes between planets of one owner take their colour."],
		["planet_0", "1  PLACE: each turn you get new critters (more when you own more planets). Click your planets to put them there."],
		["icon_city", "CITIES: a city costs critters from its own planet (5, then 6, 7...). It makes +2 critters there at the start of each of your turns and +1 when defending. If someone wins the planet, the city is knocked down! Grow, or grab planets?"],
		["icon_rocket", "2  SEND: click your planet, then one next door. Each critter can hop up to 2 planets per turn, then it rests (zz). Empty planet? One critter claims it; click it again to send everyone. Your own or a teammate's? They move."],
		["icon_dice", "DANCE-OFF: someone lives there? The dice roll by themselves. Higher die wins, a tie goes to the attacker, the loser loses a critter. Bigger crowd +1 (twice as big +2). Homes, cities and nests +1 when defending."],
		["icon_pinky", "BEFRIEND: instead of dancing with another player, ask to be friends. No dance-offs between you for 3 rounds, and the two planets defend together. Beat them and you win BOTH!"],
		["icon_card", "3  LUCKY CARDS (Full rules): win a planet in your turn to find one. Rocket +3, Lucky Dice, Force Field, Instant City."],
		["lantern", "Golden planets give +1 critter every turn. ? planets hide a surprise. Each round may bring space news like a Meteor Shower or a Lucky Comet."],
		["gloom", "The Gloom is a grey fog army. It grows every round and grabs planets. If it covers too much of the galaxy, EVERYBODY loses!"],
		["icon_clock", "Win by owning every planet, or have the most planets when the Star Clock runs out. The last 3 rounds are a Star Rush: +2 critters. Stuck? Press Hint."],
	]
	for r in rows:
		grid.add_child(_icon(r[0], 60))
		var l := _label(r[1], 24)
		l.custom_minimum_size = Vector2(1400, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(l)
	var b := _button("Got it!", _close_overlay, 36)
	b.custom_minimum_size = Vector2(300, 80)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
