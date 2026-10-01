extends Node
## Autoload "GameAudio". Every sound has its own audio bus (default_bus_layout.tres), so
## each can be mixed in the Audio tab at the bottom of the editor:
##   Voice   the question read out at the start of each trial (river/audio/voice, made by tools/generate_voice.py)
##   Throw   spear throw
##   UI      menu button press
##   Reward  the right object was speared
##   Wrong   a wrong object was speared
## Play with GameAudio.play(&"throw"); add a sound by adding a line to SOUNDS and a bus.

const SOUNDS := {
	&"throw": [preload("res://river/audio/sfx/throw.wav"), &"Throw"],
	&"ui_button": [preload("res://river/audio/sfx/ui_button.wav"), &"UI"],
	&"reward": [preload("res://river/audio/sfx/reward.wav"), &"Reward"],
	&"wrong": [preload("res://river/audio/sfx/wrong.wav"), &"Reward"],
}
const VOICE_BUS := &"Voice"

var _players := {} # sound name -> AudioStreamPlayer
var _voice: AudioStreamPlayer


func _ready() -> void:
	for sound: StringName in SOUNDS:
		_players[sound] = _make_player(SOUNDS[sound][0], SOUNDS[sound][1])
	_voice = _make_player(null, VOICE_BUS)


## Plays a sound from SOUNDS. Playing it again restarts it.
func play(sound: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(sound)
	if player:
		player.play()
	else:
		push_warning("GameAudio|WARN: unknown sound '%s'" % sound)


## Speaks `stream` on the Voice bus, replacing whatever was being said. Null = stop.
func speak(stream: AudioStream) -> void:
	if stream == null:
		_voice.stop()
		return
	_voice.stream = stream
	_voice.play()


func stop_voice() -> void:
	_voice.stop()


func _make_player(stream: AudioStream, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	add_child(player)
	return player
