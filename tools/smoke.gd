extends SceneTree
## Drives the real UI headless: godot --headless --path . -s tools/smoke.gd

func _wait_dance(main) -> void:
	var t := 0
	while not main.dance.is_empty() and t < 3000:
		await process_frame
		t += 1


var offers := 0
var accepted := 0
var gifts := 0


## The city offer and the gift question are pop-ups: answer them like a person would.
func _popups(main) -> void:
	if main.overlay == null:
		return
	var b = _find_button(main.overlay, "City on ")
	if b != null:
		offers += 1
		if offers % 2 == 1:
			b.pressed.emit()
			accepted += 1
		else:
			_find_button(main.overlay, "Not now").pressed.emit()
		return
	b = _find_button(main.overlay, "Send a gift")
	if b != null:
		gifts += 1
		b.pressed.emit()


func _find_button(n: Node, prefix: String):
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var f = _find_button(c, prefix)
		if f != null:
			return f
	return null


func _follow_hints(main, steps: int) -> void:
	for k in steps:
		if main.s["over"] or main.s["players"][main.s["current"]]["ai"]:
			return
		main._hint()
		var c = main.AI.next_command(main.s, main.s["current"])
		match c["cmd"]:
			"end":
				return
			"place":
				main._on_node_clicked(c["node"])
				_popups(main)
				main._place_all()
				_popups(main)
			"build":
				main._build_pressed()
				main._on_node_clicked(c["node"])
			"send":
				main._on_node_clicked(c["from"])
				main._on_node_clicked(c["to"])
				_popups(main)
			"attack":
				main._on_node_clicked(c["from"])
				main._on_node_clicked(c["to"])
				if main.overlay == null:
					print("  !! no dance-off pop-up")
				main._choose_dance()
				await _wait_dance(main)
			"befriend":
				main._on_node_clicked(c["from"])
				main._on_node_clicked(c["to"])
				main._choose_friend()
				if main.overlay:
					main._friend_answer(c["from"], c["to"], true, false)
				print("  befriend -> truces ", main.s["truces"].size())
			"card":
				main._card_pressed(c["idx"])
				if c.has("node"):
					main._on_node_clicked(c["node"])
		_popups(main)
		await process_frame


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.ROLL_EVERY = 0.02
	main.AI_ROLL_EVERY = 0.02
	main.AI_DELAY = 0.02
	for setup in [["ffa", "full", true, "big"], ["ffa", "simple", false, "huge"], ["teams", "full", true, "big"], ["coop", "simple", true, "normal"]]:
		var players := [{"species": 0, "ai": false, "cadet": true}]
		for i in range(1, 4):
			players.append({"species": i, "ai": true})
		main.start_game({"mode": setup[0], "players": players, "seed": 42, "rules": setup[1], "gloom": setup[2], "length": "short", "galaxy": setup[3]})
		await process_frame
		main._close_overlay()
		_popups(main)
		main._close_overlay()
		main._on_node_clicked(main.s["players"][0]["home"])  # place one
		main._undo()
		for turn in 3:
			await _follow_hints(main, 40)
			main._show_how_to()
			main._close_overlay()
			main._end_turn_pressed()
			var t := 0
			while not main.s["over"] and (main.s["current"] != 0 or main.overlay != null and main.ai_waiting) and t < 20000:
				if main.ai_waiting:
					main._friend_answer(main.choice.get("from", 0), main.choice.get("to", 0), false, true)
				await process_frame
				t += 1
			main._close_overlay()
			_popups(main)
		print("  city offers %d (built %d), gift pop-ups %d" % [offers, accepted, gifts])
		print(setup, ": back to human at round ", main.s["round"], " nodes ", main.s["nodes"].size(), " cities ", main.Rules.cities(main.s, 0), "; log: ", main.s["log"].back()["text"])
		# fast-forward to the end and show the result screen
		main._test_fast_forward(40)
		await process_frame
		print("   finished: over=", main.s["over"], " result=", main.s["result"], " winners=", main.s["winners"])
		if main.s["over"]:
			main._show_game_over()
			await process_frame
	main._play_again()
	await process_frame
	main._show_setup_reset()
	await process_frame
	# Learn to Play: follow the coach
	main._start_tutorial()
	await process_frame
	print("tutorial step ", main.tut_step, ": ", main.coach_text.text.substr(0, 40))
	main._tut_next()
	main._place_all()
	await process_frame
	print("tutorial step ", main.tut_step, " (want 2)")
	main._build_pressed()
	main._on_node_clicked(0)
	await process_frame
	print("tutorial step ", main.tut_step, " (want 3), city ", main.s["nodes"][0]["city"])
	main._on_node_clicked(0)
	main._on_node_clicked(1)
	await process_frame
	print("tutorial step ", main.tut_step, " (want 4), pebble owner ", main.s["nodes"][1]["owner"])
	main._end_turn_pressed()
	var t2 := 0
	var t1 := Time.get_ticks_msec()
	while main.s["current"] != 0 and Time.get_ticks_msec() - t1 < 60000:
		await process_frame
		t2 += 1
	main._refresh()
	print("tutorial step ", main.tut_step, " (want 5), home ", main.s["nodes"][0]["n"])
	main._on_node_clicked(1)
	main._place_all()
	await process_frame
	print("tutorial step ", main.tut_step, " (want 6), pebble ", main.s["nodes"][1]["n"])
	var guard := 0
	while main.s["nodes"][3]["owner"] != 0 and guard < 10:
		guard += 1
		main._on_node_clicked(1)
		main._on_node_clicked(3)
		main._choose_dance()
		await _wait_dance(main)
		for f in 120:
			await process_frame
		main._refresh()
	print("tutorial step ", main.tut_step, " (want 8), Goldie owner ", main.s["nodes"][3]["owner"], " tries ", guard)
	main._tut_next()
	main._tut_next()
	main._tut_next()
	main._end_turn_pressed()
	var t3 := 0
	var t0 := Time.get_ticks_msec()
	while main.s["current"] != 0 and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		t3 += 1
	if main.s["current"] != 0:
		var texts: Array = []
		for l in main.overlay.find_children("*", "Label", true, false):
			texts.append(l.text.left(50))
		print("  overlay texts ", texts)
		print("  stuck: overlay ", main.overlay != null, " dance ", main.dance, " log ", main.s["log"].back()["text"])
	main._close_overlay()
	main._refresh()
	print("tutorial step ", main.tut_step, " (want 12), cards: ", main.s["players"][0]["cards"], " round ", main.s["round"], " current ", main.s["current"], " waiting ", main.ai_waiting, " over ", main.s["over"], " t3 ", t3)
	main._tut_next()
	main._tut_next()
	print("tutorial coach visible after finish: ", main.coach.visible)
	main._show_setup_reset()
	await process_frame
	print("smoke ok")
	quit()
