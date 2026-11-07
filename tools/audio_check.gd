extends SceneTree
## Plays a sound in the real game (not headless) and prints the audio bus levels:
## godot --path . -s tools/audio_check.gd
func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	print("driver ", AudioServer.get_driver_name(), " buses ", AudioServer.bus_count, " mix rate ", AudioServer.get_mix_rate())
	for b in AudioServer.bus_count:
		print("  bus ", b, " ", AudioServer.get_bus_name(b), " send=", AudioServer.get_bus_send(b), " mute=", AudioServer.is_bus_mute(b), " vol=", AudioServer.get_bus_volume_db(b))
	print("music_on ", main.sound.music_on, " sfx_on ", main.sound.sfx_on, " drone playing ", main.sound._drone.playing)
	main.sound.play("turn")
	var best := {}
	for i in 90:
		await process_frame
		for b in AudioServer.bus_count:
			var n := AudioServer.get_bus_name(b)
			best[n] = maxf(best.get(n, -200.0), AudioServer.get_bus_peak_volume_left_db(b, 0))
	print("peak dB over 1.5 s: ", best)
	quit()
