extends Node
## Music and sound effects (mood lab picks: "Deep space" music in A, soft in-key effects).
## The music is layered, not one track: a seamless drone, slow starry-wind swells and single
## low bells at random times, so it never exactly repeats. Its tone and volume breathe with
## the pulse. Sounds come from tools/make_audio.py.

const SFX := ["click", "popup", "invalid", "turn", "news", "rush", "done", "tick", "placeall", "offer",
	"city", "harvest", "citylost", "select", "hop", "claim", "gift", "dance", "dice_0", "dice_1", "dice_2",
	"lose", "capture", "defend", "runaway", "ask", "friends", "nothanks", "friendend", "card", "rocket",
	"luckydice", "shield", "mystery", "meteor", "comet", "bloom", "glow", "gloomgrow", "gloomtake",
	"gloomchase", "storm", "win", "loseall", "out", "bounce"]
const MUSIC_VOL := 0.55   # mood lab levels (the 100% marks on the Settings sliders)
const SFX_VOL := 0.53
const SETTINGS := "user://settings.cfg"
const FADE_IN := 2.0     # seconds for the music to rise when it starts

var music_on := true
var sfx_on := true
var pulse_on := true
var music_volume := 1.0   # Settings sliders, 0..1
var sfx_volume := 0.75    # effects sit a little under the music
var _save_in := -1.0      # slider drags save once they settle
var streams := {}
var _pool: Array = []
var _next := 0
var _music_pool: Array = []
var _drone: AudioStreamPlayer
var _lowpass: AudioEffectLowPassFilter
var _music_bus := -1
var _sfx_bus := -1
var _next_wind := 4.0
var _next_bell := 9.0
var _place_i := 0
var _place_t := -10.0
var _win_streak := 0
var _clock := 0.0
var _fade := 0.0         # music fade-in, 0..1
var _started := false    # music waits for the browser to allow sound


func _ready() -> void:
	_load_settings()
	# the Music and SFX buses come from default_bus_layout.tres, so they exist from the start.
	# (Buses added from code at runtime are not wired to the speakers on the web.)
	_music_bus = AudioServer.get_bus_index("Music")
	_sfx_bus = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(_music_bus, -80.0)  # silent until the fade-in begins
	if AudioServer.get_bus_effect_count(_music_bus) > 0:
		_lowpass = AudioServer.get_bus_effect(_music_bus, 0) as AudioEffectLowPassFilter
	for n in SFX:
		streams[n] = load("res://assets/audio/%s.ogg" % n)
	for i in range(4, 15):
		streams["note_%d" % i] = load("res://assets/audio/note_%d.ogg" % i)
	for i in 4:
		streams["wind_%d" % i] = load("res://assets/audio/wind_%d.ogg" % i)
	for i in range(3, 9):
		streams["mbell_%d" % i] = load("res://assets/audio/mbell_%d.ogg" % i)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music_pool.append(p)
	var drone: AudioStreamOggVorbis = load("res://assets/audio/drone.ogg")
	drone.loop = true
	_drone = AudioStreamPlayer.new()
	_drone.stream = drone
	_drone.bus = "Music"
	add_child(_drone)
	_apply()
	# Desktop plays from the opening screen. Browsers keep a page silent until the first
	# click, tap or key, so on the web the music starts (and fades in) on that first touch.
	if not OS.has_feature("web"):
		_start()


func _input(event: InputEvent) -> void:
	if _started:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) \
			and event.pressed:
		_start()


func _start() -> void:
	_started = true
	_fade = 0.0
	_next_wind = 4.0
	_next_bell = 9.0
	_apply()


func _apply() -> void:
	AudioServer.set_bus_mute(_music_bus, not music_on)
	AudioServer.set_bus_mute(_sfx_bus, not sfx_on)
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(SFX_VOL * sfx_volume, 0.0001)))
	if music_on and _started and not _drone.playing:
		_fade = 0.0
		_drone.play()
	elif not music_on:
		_drone.stop()


func set_music(on: bool) -> void:
	music_on = on
	_apply()
	_save_settings()


func set_sfx(on: bool) -> void:
	sfx_on = on
	_apply()
	_save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_save_in = 0.6


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply()
	_save_in = 0.6


func set_pulse_on(on: bool) -> void:
	pulse_on = on
	_save_settings()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		music_on = cf.get_value("sound", "music", true)
		sfx_on = cf.get_value("sound", "effects", true)
		pulse_on = cf.get_value("look", "pulse", true)
		music_volume = cf.get_value("sound", "music_volume", music_volume)
		sfx_volume = cf.get_value("sound", "effects_volume", sfx_volume)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("sound", "music", music_on)
	cf.set_value("sound", "effects", sfx_on)
	cf.set_value("look", "pulse", pulse_on)
	cf.set_value("sound", "music_volume", music_volume)
	cf.set_value("sound", "effects_volume", sfx_volume)
	cf.save(SETTINGS)


# ---------------------------------------------------------------- effects

func play(name: String, delay := 0.0) -> void:
	if not sfx_on or not streams.has(name):
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(play.bind(name))
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[name]
	p.play()


## Placing critters one by one climbs the scale; a pause starts it over.
func place_note() -> void:
	if _clock - _place_t > 1.5:
		_place_i = 0
	_place_t = _clock
	play("note_%d" % (5 + _place_i % 10))
	_place_i += 1


func dice() -> void:
	play("dice_%d" % randi_range(0, 2))


## One dance-off roll: dice, then a note that climbs while the attacker keeps winning.
func roll(att_wins: bool) -> void:
	dice()
	if att_wins:
		play("note_%d" % mini(7 + _win_streak, 14), 0.3)
		_win_streak += 1
	else:
		_win_streak = 0
		play("lose", 0.3)


func reset_streak() -> void:
	_win_streak = 0


# ---------------------------------------------------------------- music

func _process(delta: float) -> void:
	_clock += delta
	if _save_in > 0.0:
		_save_in -= delta
		if _save_in <= 0.0:
			_save_settings()
	if not music_on or not _started:
		return
	_fade = minf(1.0, _fade + delta / FADE_IN)
	_next_wind -= delta
	if _next_wind <= 0.0:
		_music("wind_%d" % randi_range(0, 3))
		_next_wind = randf_range(8.0, 12.0)
	_next_bell -= delta
	if _next_bell <= 0.0:
		_music("mbell_%d" % randi_range(3, 8))
		_next_bell = randf_range(7.0, 15.0)


func _music(name: String) -> void:
	for p: AudioStreamPlayer in _music_pool:
		if not p.playing:
			p.stream = streams[name]
			p.play()
			return


## The pulse: the music gets a little brighter and louder on each in-breath.
func set_pulse(p: float, depth: float) -> void:
	if _music_bus < 0:
		return
	var on := pulse_on and depth > 0.0
	if _lowpass:  # (bus effects only run on desktop; the web plays sounds as samples)
		_lowpass.cutoff_hz = 650.0 + 900.0 * p if on else 1000.0
	var g := 1.0 - minf(0.5, depth * 5.0) * (1.0 - p) if on else 1.0
	g *= smoothstep(0.0, 1.0, _fade) * music_volume
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(MUSIC_VOL * g, 0.0001)))
