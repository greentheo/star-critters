extends SceneTree
## Real input events through the viewport: setup buttons, board planets, dance-off, end turn.

func _click(main, p: Vector2) -> void:
	main._js_click([p.x, p.y])
	for k in 4:
		await process_frame


func _find_button(node: Node, text: String) -> Button:
	var bt: String = (node as Button).text if node is Button else ""
	if node is Button and (bt == text or (text.ends_with(" ") and bt.begins_with(text))) and (node as Button).is_visible_in_tree():
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


func _collect_seat_buttons(node: Node, out: Array) -> void:
	if node is Button and (node as Button).text in ["Empty seat", "Player", "Cadet (extra help)", "Computer"]:
		out.append(node)
	for c in node.get_children():
		_collect_seat_buttons(c, out)


func _press(main, text: String) -> bool:
	var b := _find_button(main.ui, text)
	if b == null:
		print("  !! no button '", text, "'")
		return false
	await _click(main, b.get_global_rect().get_center())
	return true


func _check_on_screen(main, label: String) -> void:
	var bad: Array = []
	_offscreen(main.game_ui, bad)
	print("layout (", label, "): ", "all buttons on screen" if bad.is_empty() else "OFF SCREEN: " + str(bad))


func _offscreen(node: Node, bad: Array) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		var r := (node as Button).get_global_rect()
		if r.end.y > 1080 or r.end.x > 1920:
			bad.append((node as Button).text)
	for c in node.get_children():
		_offscreen(c, bad)


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.ROLL_EVERY = 0.05
	main.AI_ROLL_EVERY = 0.02
	main.AI_DELAY = 0.02
	await _press(main, "Full")
	await _press(main, "On")
	await _press(main, "Short ")
	await _press(main, "Huge")
	print("options: rules=", main.rules, " gloom=", main.gloom_on, " length=", main.length, " galaxy=", main.galaxy, " (want full true short huge)")
	await _press(main, "Big")
	# Moxies seat (3rd card): Empty -> Player -> Cadet -> Computer
	for i in 3:
		var seat_btns: Array = []
		_collect_seat_buttons(main.ui, seat_btns)
		seat_btns.sort_custom(func(a, b): return a.get_global_rect().position.x < b.get_global_rect().position.x)
		await _click(main, seat_btns[2].get_global_rect().get_center())
	print("seats: ", main.seats, " (want [1,1,3,0])")
	var go := _find_button(main.ui, "Blast off!")
	print("blast off button bottom: ", go.get_global_rect().end.y, " (must be < 1080)")
	await _press(main, "Blast off!")
	print("game started: ", not main.s.is_empty(), " players=", main.s["players"].size(), " nodes=", main.s["nodes"].size(), " board scale=", main.board.scale)
	await _press(main, "Let's go!")
	print("splash closed: ", main.overlay == null)
	var home: int = main.s["players"][0]["home"]
	var before: int = main.s["nodes"][home]["n"]
	await _click(main, main.board.node_screen_pos(home))
	print("placed one: ", before, " -> ", main.s["nodes"][home]["n"])
	await _press(main, "Undo")
	print("undo: back to ", main.s["nodes"][home]["n"])
	await _click(main, main.board.node_screen_pos(home))
	await _press(main, "Place all")
	print("phase after place all: ", main.s["phase"], " home has ", main.s["nodes"][home]["n"])
	# 6 critters at home: the game offers a city there by itself
	var offer = _find_button(main.ui, "City on ")
	print("city offer pop-up: ", offer != null, " (want true)")
	if offer != null:
		await _press(main, "Not now")
	print("offer closed: ", main.overlay == null, ", city sign on home: ", main.board.city_nodes.has(home))
	# build a city on home with the button
	main.s["nodes"][home]["n"] = 12
	main._refresh()
	await _press(main, "Build a city")
	await _click(main, main.board.node_screen_pos(home))
	print("city on home: ", main.s["nodes"][home]["city"], " home now ", main.s["nodes"][home]["n"], " (want true 7)")
	await _click(main, main.board.node_screen_pos(home))
	print("selected home: ", main.selected == home, " targets ", main.board.targets)
	var take := -1
	for n in main.board.targets:
		if main.board.targets[n] == "take":
			take = n
	if take >= 0:
		await _click(main, main.board.node_screen_pos(take))
		print("claimed empty planet: owner ", main.s["nodes"][take]["owner"], " n ", main.s["nodes"][take]["n"], " (want 0, 1); home still selected ", main.selected == home)
		await _click(main, main.board.node_screen_pos(take))
		print("sent everyone: ", main.s["nodes"][take]["n"], " on it, home ", main.s["nodes"][home]["n"], ", hops used ", main.s["nodes"][take]["used"])
		await _click(main, main.board.node_screen_pos(take))
		print("one more hop: planet selectable again ", main.selected == take, " (want true)")
		var on := -1
		for n in main.board.targets:
			if main.board.targets[n] in ["take", "move"]:
				on = n
		if on >= 0:
			await _click(main, main.board.node_screen_pos(on))
			print("second hop to ", main.s["nodes"][on]["name"], ": hops used ", main.s["nodes"][on]["used"], ", movable ", main.Rules.movable(main.s, on))
			main.selected = -1
			await _click(main, main.board.node_screen_pos(on))
			print("selectable only if it still has a fresh critter: ", main.selected == on, " == ", main.Rules.movable(main.s, on) > 0)
	# a dance-off through the pop-up
	main.s["nodes"][home]["n"] = 9
	main.s["nodes"][home]["used"] = [0, 0]
	main._refresh()
	await _click(main, main.board.node_screen_pos(home))
	var target := -1
	for n in main.board.targets:
		if main.board.targets[n] == "dance":
			target = n
	if target < 0:
		# make a neighbour wild so there's someone to dance with
		for n in main.s["adj"][home]:
			if main.s["nodes"][n]["owner"] == -1:
				main.s["nodes"][n]["n"] = 2
				target = n
				break
		main._refresh()
	await _click(main, main.board.node_screen_pos(target))
	print("pop-up open: ", main.overlay != null, " dance button: ", _find_button(main.ui, "Dance-off!") != null)
	await _press(main, "Dance-off!")
	print("dance started: ", not main.dance.is_empty())
	_check_on_screen(main, "dance open")
	var t := 0
	while not main.dance.is_empty() and t < 2000:
		await process_frame
		t += 1
	print("dance finished after ", t, " frames: target owner ", main.s["nodes"][target]["owner"], " tally ", main.dance_tally)
	main.s["players"][0]["cards"] = ["rocket", "dice", "shield"]
	main._refresh()
	await process_frame
	_check_on_screen(main, "3 cards")
	# friends: find two of my planets A, C and two of theirs B, D with A-B and C-D next door,
	# be friends through A-B, then send from C at D: it must ASK before gifting
	var st: Dictionary = main.s
	st["mode"] = "ffa"
	var picked := []
	for a in st["adj"].size():
		for b in st["adj"][a]:
			for c in st["adj"].size():
				if c == a or c == b:
					continue
				for d in st["adj"][c]:
					if d != a and d != b and not picked.size():
						picked = [a, b, c, d]
	var A: int = picked[0]
	var B: int = picked[1]
	var C: int = picked[2]
	var D: int = picked[3]
	for x in [A, C]:
		st["nodes"][x]["owner"] = 0
		st["nodes"][x]["n"] = 5
		st["nodes"][x]["used"] = [0, 0]
	for x in [B, D]:
		st["nodes"][x]["owner"] = 1
		st["nodes"][x]["n"] = 3
	st["phase"] = "go"
	st["truces"] = [{"a": 0, "b": 1, "na": A, "nb": B, "until": st["round"] + 2}]
	main.selected = -1
	main._refresh()
	await _click(main, main.board.node_screen_pos(C))
	print("friend's other planet is a gift target: ", main.board.targets.get(D, ""), " (want gift)")
	var before_d: int = st["nodes"][D]["n"]
	await _click(main, main.board.node_screen_pos(D))
	print("gift asks first: ", _find_button(main.ui, "Send a gift") != null, ", nothing sent yet: ", st["nodes"][D]["n"] == before_d)
	await _press(main, "Never mind")
	print("never mind: still ", st["nodes"][D]["n"], " on their planet")
	await _click(main, main.board.node_screen_pos(C))
	await _click(main, main.board.node_screen_pos(D))
	await _press(main, "Send a gift")
	print("gift sent: their planet now ", st["nodes"][D]["n"], " (was ", before_d, ")")
	# the friend pair changes hands -> friendship gone
	st["nodes"][B]["owner"] = 2
	print("friends after B lost: ", main.Rules.truce(st, 0, 1), " (want false)")
	var db := _find_button(main.ui, "Done")
	print("done button: disabled=", db.disabled if db else null)
	await _press(main, "Done")
	print("end turn -> current player ", main.s["current"])
	quit()
