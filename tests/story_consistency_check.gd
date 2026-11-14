extends SceneTree
## The story fixes from docs/CAMPAIGN_AUDIT.md section 5 and the opening canon (headless):
##   godot --headless --path . -s tests/story_consistency_check.gd

const DOC_DIR: String = "res://resources/story/documents/"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _body(key: String) -> String:
	var doc := load("%s%s.tres" % [DOC_DIR, key]) as DocumentData
	return "" if doc == null else doc.body


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _run() -> void:
	print("-- the opening stays spoiler-free")
	for path in ["res://scripts/story/opening_cinematic.gd", "res://scripts/story/opening_beach.gd", "res://scripts/story/opening_timeline.gd"]:
		var text := _source(path).to_lower()
		_check(text != "", "%s is readable" % path.get_file())
		for banned in ["outpost 17", "the director", "project black site", "warden"]:
			_check(not text.contains(banned), "%s does not mention '%s'" % [path.get_file(), banned])

	print("-- ending (audit: the transport witness no longer fits the thief canon)")
	var beats := ""
	for beat in CampaignEnding.BEATS:
		beats += String(beat["text"]).to_lower() + "\n"
	_check(not beats.contains("transport") and not beats.contains("witness"), "no beat mentions a transport or a witness")
	_check(beats.contains("gold") and beats.contains("storm"), "a beat ties the ending to the stolen gold and the storm")

	print("-- radio (audit 4: the early voice is a looping compound beacon)")
	var radio := " ".join(WorldFlow.RADIO_LINES).to_lower()
	_check(radio.contains("beacon"), "the first-mission radio lines are marked as a beacon")
	_check(WorldFlow.RADIO_LINES.size() == 3, "there are still three lines")

	print("-- Outpost 17 terminals (audit 2 and 3)")
	var mil := _body("o17_military_terminal")
	_check(mil.contains("Dead Coast") and not mil.contains("Research Complex"), "the military terminal points at the Dead Coast, not the Research Complex")
	var cmd := _body("o17_command_terminal_d")
	_check(not cmd.contains("no longer a secret"), "the command terminal no longer spoils the reveal")
	_check(cmd.contains("outside"), "the command terminal still says the signal reached the outside")
	var o17 := _source("res://scripts/world/outpost17.gd")
	_check(not o17.contains("Coordinates uploaded: Research Complex") and not o17.contains("no longer a secret"), "the world script matches the document text")

	print("-- documents (audit 5 to 9)")
	_check(_body("bw_bw_log_experiment_1").contains("first-generation annex"), "Subject 14 starts at the Blackwood first-generation annex")
	var med := _body("rc_rc_medical_evidence")
	_check(med.contains("Blackwood annex") and med.contains("R. Hale"), "the medical notes place Subject 14 in the Blackwood annex and sign it R. Hale")
	_check(_body("dc_dead_coast_data_device").contains("R. HALE, MEDICAL OFFICER"), "the shipping ledger is signed by the same R. Hale, the medical officer")
	_check(_body("rc_rc_incident_report").contains("lockdown that followed was ordered from below"), "the incident report orders release first, lockdown after")
	_check(not _body("dc_dead_coast_log_checkpo_1016").contains("Commander's office"), "the checkpoint order no longer comes from a 'Commander's office'")
	_check(_body("dc_dead_coast_log_checkpo_1016").contains("Administration office"), "...it comes from the administration office")
	_check(_body("dc_dead_coast_wreck_hull").contains("not yours"), "the CALLOWAY wreck is stated to be an earlier ship")

	print("-- audit 1: the old arena chain no longer fires the campaign ending")
	var qm := _source("res://scripts/quests/quest_manager.gd").replace("", "")
	_check(qm.contains("func _begin_ending(_quest: QuestData) -> void:\n\tending_started.emit()"), "completing final_transmission only signals; it does not show the ending")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
