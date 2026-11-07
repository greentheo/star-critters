extends SceneTree
## Headless balance sim: godot --headless --path . -s tools/sim.gd [-- quick]

const Rules = preload("res://scripts/rules.gd")
const AI = preload("res://scripts/ai.gd")


func _init() -> void:
	var setups := [
		# mode, players, gloom, rules, length, galaxy
		["ffa", 2, false, "simple", "medium", "normal"],
		["ffa", 2, false, "full", "medium", "big"],
		["ffa", 3, false, "full", "medium", "big"],
		["ffa", 4, false, "full", "medium", "big"],
		["ffa", 4, false, "full", "long", "huge"],
		["ffa", 2, true, "full", "medium", "big"],
		["ffa", 4, true, "simple", "medium", "big"],
		["teams", 4, false, "full", "medium", "big"],
		["teams", 4, true, "full", "medium", "big"],
		["coop", 1, true, "simple", "medium", "big"],
		["coop", 2, true, "full", "medium", "big"],
		["coop", 3, true, "full", "medium", "big"],
		["coop", 4, true, "full", "medium", "big"],
		["ffa", 3, false, "full", "epic", "huge"],
	]
	var games := 60
	var args := OS.get_cmdline_user_args()
	# generic overrides: -- set ties att set need 1 set pen 0.1 set home 1 ...
	for i in args.size():
		if args[i] == "set" and i + 2 < args.size():
			var v: String = args[i + 2]
			match args[i + 1]:
				"ties": Rules.TIES = v
				"need": AI.NEED = int(v)
				"pen": AI.DEF_PENALTY = float(v)
				"home": Rules.HOME_BONUS = int(v)
				"hops": Rules.MAX_HOPS = int(v)
				"citymakes": Rules.CITY_MAKES = int(v)
				"citycost": Rules.CITY_COST = int(v)
				"citywant": AI.CITY_WANT = float(v)
				"falls": Rules.CITY_FALLS = v == "1"
				"cdef": Rules.CITY_DEFENDS = v == "1"
				"tbg":  # team start bonus with the Gloom on, e.g. 0,1,1,2
					var arr: Array = []
					for x in v.split(","):
						arr.append(int(x))
					Rules.TEAM_BONUS[true] = arr
	if args.has("quick"):
		games = 20
	if args.has("maps"):
		for g in ["normal", "big", "huge"]:
			for n in [2, 3, 4]:
				var t0 := Time.get_ticks_msec()
				var fails := 0
				var sizes := []
				for k in 20:
					var m := Rules.MapGen.generate(n, "coop", 500 + k, g)
					if m.is_empty():
						fails += 1
					else:
						sizes.append(m["nodes"].size())
				print("map %s %dp: nodes %s fails %d (%d ms)" % [g, n, str(sizes.slice(0, 3)), fails, Time.get_ticks_msec() - t0])
		quit()
		return
	if args.has("snap"):
		for cfg in [[false, true, 1.0], [false, false, 1.0], [false, false, 0.0], [false, true, 0.0]]:
			Rules.FINAL_SNAPSHOT = cfg[0]
			AI.FRIENDLY = cfg[1]
			AI.CITY_WANT = cfg[2]
			print("snapshot/friends/city ", cfg)
			Rules.START_BONUS[3] = [0, 0, 0]
			Rules.START_BONUS[4] = [0, 0, 0, 0]
			_run("ffa", 3, false, "full", "medium", "big", 60)
			_run("ffa", 4, false, "full", "medium", "big", 60)
		quit()
		return
	if args.has("cities"):
		# builders vs expanders: seat 0 uses CITY_WANT=w, the others the default
		for w in [0.0, 0.5, 1.0, 2.0]:
			_run("ffa", 2, false, "full", "medium", "big", 80, w)
			_run("ffa", 4, false, "full", "medium", "big", 80, w)
		quit()
		return
	if args.has("cooptune"):
		for t in [[2, 2, 3, 1.5, 0.34, 6, 3], [2, 2, 3, 1.34, 0.34, 6, 3], [2, 3, 3, 1.5, 0.34, 6, 3]]:
			var n: int = t[0]
			Rules.GLOOM_TUNE["coop"][n] = {"base": t[1], "div": t[2], "attacks": t[3], "limit": t[4], "nest": t[5]}
			Rules.COOP_EXTRA = t[6]
			print("coop %s" % str(t))
			_run("coop", n, true, "full", "medium", "big", 50)
		quit()
		return
	if args.has("seats3"):
		for b in [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 2]]:
			Rules.START_BONUS[3] = b
			print("3p bonus ", b)
			_run("ffa", 3, false, "full", "medium", "big", 120)
		quit()
		return
	if args.has("seats"):
		for b in [[0, 0, 0], [0, 0, 1], [0, 0, 2], [0, 1, 2]]:
			Rules.START_BONUS[3] = b
			print("3p bonus ", b)
			_run("ffa", 3, false, "full", "medium", "big", 100)
		for b in [[0, 0, 0, 0], [0, 0, 0, 1], [1, 0, 0, 1], [0, 1, 1, 2]]:
			Rules.START_BONUS[4] = b
			print("4p bonus ", b)
			_run("ffa", 4, false, "full", "medium", "big", 100)
		for b in [[0, 0], [0, 1], [0, 2]]:
			Rules.START_BONUS[2] = b
			print("2p bonus ", b)
			_run("ffa", 2, false, "full", "medium", "big", 100)
		quit()
		return
	if args.has("conq"):
		# one variant per process: conq hops ties need pen home
		var i := args.find("conq")
		Rules.MAX_HOPS = int(args[i + 1])
		Rules.TIES = args[i + 2]
		AI.NEED = int(args[i + 3])
		AI.DEF_PENALTY = float(args[i + 4])
		Rules.HOME_BONUS = int(args[i + 5])
		var out := "hops %s ties %s need %s pen %s home %s |" % [args[i + 1], args[i + 2], args[i + 3], args[i + 4], args[i + 5]]
		for st in [[2, "big", 15], [2, "big", 22], [3, "big", 22], [4, "big", 22], [4, "big", 30], [4, "huge", 30]]:
			out += _conq_run(st[0], st[1], st[2], 30)
		print(out)
		quit()
		return
	if args.has("bonus"):
		# -- bonus <players> <b0> <b1> [b2] [b3]: seat wins with these start bonuses
		var i := args.find("bonus")
		var n := int(args[i + 1])
		var b: Array = []
		for k in n:
			b.append(int(args[i + 2 + k]))
		if args.size() > i + 2 + n:
			Rules.SLOW_ROUNDS = int(args[i + 2 + n])
		print("slow rounds ", Rules.SLOW_ROUNDS, " bonus ", b)
		Rules.START_BONUS[n] = b
		_run("ffa", n, false, "full", "medium", "big", 120)
		quit()
		return
	if args.has("gtune"):
		# -- gtune <players> <base> <div> <attacks> <limit> <nest>
		var i := args.find("gtune")
		var n := int(args[i + 1])
		Rules.GLOOM_TUNE["coop"][n] = {"base": int(args[i + 2]), "div": int(args[i + 3]), "attacks": float(args[i + 4]),
			"limit": float(args[i + 5]), "nest": int(args[i + 6])}
		print("gloom ", Rules.GLOOM_TUNE["coop"][n])
		_run("coop", n, true, "simple" if n == 1 else "full", "medium", "big", 60)
		quit()
		return
	if args.has("table"):
		# when do games end? table <galaxy> <players> [pen]: end-round percentiles with a 40-round clock
		var i := args.find("table")
		if args.size() > i + 3:
			AI.DEF_PENALTY = float(args[i + 3])
		_table_run(int(args[i + 2]), args[i + 1], 40)
		quit()
		return
	if args.has("finish"):
		# no clock: when do games end by someone winning? (for setting the Star Clock)
		var variants := [[1, "def"], [2, "def"], [2, "none"], [2, "att"]]
		if args.has("now"):
			variants = [[Rules.MAX_HOPS, Rules.TIES]]
		for v in variants:
			Rules.MAX_HOPS = v[0]
			Rules.TIES = v[1]
			print("hops %d ties %s" % v)
			for st in [[2, "normal"], [2, "big"], [3, "big"], [4, "big"], [4, "huge"]]:
				_finish_run(st[0], st[1], 40 if args.has("now") else 24)
		quit()
		return
	if args.has("coop"):
		for n in [1, 2, 3, 4]:
			_run("coop", n, true, "full", "medium", "big", 60)
		for n in [2, 3, 4]:
			_run("ffa", n, true, "full", "medium", "big", 60)
		_run("teams", 4, true, "full", "medium", "big", 60)
		quit()
		return
	if args.has("one"):
		# one setup per process so they can run side by side: -- one <index>
		var st: Array = setups[int(args[args.find("one") + 1])]
		_run(st[0], st[1], st[2], st[3], st[4], st[5], games)
		quit()
		return
	for st in setups:
		_run(st[0], st[1], st[2], st[3], st[4], st[5], games)
	_tutorial_check()
	quit()


func _run(mode: String, n: int, gloom: bool, rules: String, length: String, galaxy: String, games: int, seat0_city := -1.0) -> void:
	var rounds_total := 0
	var turns_total := 0
	var rolls_total := 0
	var cities_total := 0
	var friends_total := 0
	var results := {}
	var seat_wins: Array = [0, 0, 0, 0]
	var t0 := Time.get_ticks_msec()
	var default_want: float = AI.CITY_WANT
	for g in games:
		var players: Array = []
		for i in n:
			players.append({"species": i, "ai": true})
		var s := Rules.new_game({"mode": mode, "players": players, "seed": 1000 + g,
			"gloom": gloom, "rules": rules, "length": length, "galaxy": galaxy})
		var guard := 0
		while not s["over"] and guard < 40000:
			guard += 1
			AI.CITY_WANT = seat0_city if seat0_city >= 0.0 and s["current"] == 0 else default_want
			var c := AI.next_command(s, s["current"])
			if c["cmd"] == "end":
				turns_total += 1
			var ok := AI.apply(s, c)
			if not ok:
				print("  !! command failed: ", c)
				Rules.end_turn(s)
			for e in s["events"]:
				if e["t"] == "roll":
					rolls_total += 1
				elif e["t"] == "city":
					cities_total += 1
				elif e["t"] == "friends":
					friends_total += 1
			s["events"].clear()
		if guard >= 40000:
			print("  !! game stuck")
		rounds_total += s["round"]
		results[s["result"]] = results.get(s["result"], 0) + 1
		if s["winners"].size() == 1 or (mode == "teams" and s["winners"].size() == 2):
			for w in s["winners"]:
				seat_wins[w] += 1
	AI.CITY_WANT = default_want
	var ms := Time.get_ticks_msec() - t0
	var tag := "" if seat0_city < 0.0 else " seat0 city=%.1f" % seat0_city
	print("%-5s %dp gloom=%-5s %-6s %-6s %-6s rounds %4.1f  rolls/turn %4.1f  cities/game %4.1f  friends/game %3.1f  results %s  seat wins %s  (%d ms)%s" % [
		mode, n, str(gloom), rules, length, galaxy, float(rounds_total) / games,
		float(rolls_total) / maxi(turns_total, 1), float(cities_total) / games, float(friends_total) / games,
		str(results), str(seat_wins), ms, tag])


func _finish_run(n: int, galaxy: String, games: int) -> void:
	var ends: Array = []
	var rolls := 0
	var turns := 0
	for g in games:
		var players: Array = []
		for i in n:
			players.append({"species": i, "ai": true})
		var s := Rules.new_game({"mode": "ffa", "players": players, "seed": 2000 + g,
			"gloom": false, "rules": "full", "length": "medium", "galaxy": galaxy})
		s["max_rounds"] = 80
		var guard := 0
		while not s["over"] and guard < 80000:
			guard += 1
			var c := AI.next_command(s, s["current"])
			if c["cmd"] == "end":
				turns += 1
			if not AI.apply(s, c):
				Rules.end_turn(s)
			for e in s["events"]:
				if e["t"] == "roll":
					rolls += 1
			s["events"].clear()
		ends.append(s["round"] if s["result"] != "clock" else 999)
	ends.sort()
	var q := func(f: float) -> int: return ends[mini(ends.size() - 1, int(f * ends.size()))]
	print("  %dp %-6s nodes %d  end round p50 %d  p80 %d  p90 %d  max %d   rolls/turn %.1f" % [n, galaxy,
		Rules.MapGen.generate(n, "ffa", 2000, galaxy)["nodes"].size(), q.call(0.5), q.call(0.8), q.call(0.9), ends[ends.size() - 1],
		float(rolls) / maxi(turns, 1)])


func _conq_run(n: int, galaxy: String, rounds: int, games: int) -> String:
	var wins := 0
	var end_sum := 0
	var rolls := 0
	var turns := 0
	for g in games:
		var players: Array = []
		for i in n:
			players.append({"species": i, "ai": true})
		var s := Rules.new_game({"mode": "ffa", "players": players, "seed": 3000 + g,
			"gloom": false, "rules": "full", "length": "medium", "galaxy": galaxy})
		s["max_rounds"] = rounds
		var guard := 0
		while not s["over"] and guard < 80000:
			guard += 1
			var c := AI.next_command(s, s["current"])
			if c["cmd"] == "end":
				turns += 1
			if not AI.apply(s, c):
				Rules.end_turn(s)
			for e in s["events"]:
				if e["t"] == "roll":
					rolls += 1
			s["events"].clear()
		if s["result"] != "clock":
			wins += 1
			end_sum += s["round"]
	return " %dp%s/%d: %d%% r%.0f roll%.0f |" % [n, galaxy.left(1), rounds, 100 * wins / games, float(end_sum) / maxi(wins, 1), float(rolls) / maxi(turns, 1)]


func _table_run(n: int, galaxy: String, games: int) -> void:
	var ends: Array = []
	var secs := 0.0
	for g in games:
		var players: Array = []
		for i in n:
			players.append({"species": i, "ai": true})
		var s := Rules.new_game({"mode": "ffa", "players": players, "seed": 4000 + g,
			"gloom": false, "rules": "full", "length": "medium", "galaxy": galaxy})
		s["max_rounds"] = 40
		var guard := 0
		while not s["over"] and guard < 80000:
			guard += 1
			var c := AI.next_command(s, s["current"])
			if not AI.apply(s, c):
				Rules.end_turn(s)
			s["events"].clear()
		ends.append(s["round"] if s["result"] != "clock" else 999)
	ends.sort()
	var q := func(f: float) -> int: return ends[mini(ends.size() - 1, int(f * ends.size()))]
	print("%-6s %dp pen %.2f: end round p25 %d  p50 %d  p70 %d  p80 %d  p90 %d" % [galaxy, n, AI.DEF_PENALTY, q.call(0.25), q.call(0.5), q.call(0.7), q.call(0.8), q.call(0.9)])


func _tutorial_check() -> void:
	var s := Rules.new_tutorial()
	var guard := 0
	while not s["over"] and guard < 5000:
		guard += 1
		var c := AI.next_command(s, s["current"])
		if not AI.apply(s, c):
			Rules.end_turn(s)
		s["events"].clear()
	print("tutorial galaxy played out by AI: result %s in %d rounds" % [s["result"], s["round"]])
