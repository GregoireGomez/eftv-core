extends "res://eftv-core/scripts/menus/ScriptMenu.gd"

var SaveSystem

func _ready():
	SaveSystem = get_node("/root/SaveSystem")
	
	$Title.text = SaveSystem.runInfos.name
	var durationMs = SaveSystem.runDurationMs
	var minutes = durationMs / 60000
	var seconds = (durationMs / 1000) - (60*minutes)
	$Time.text = "%02d:%02d" % [minutes, seconds]
