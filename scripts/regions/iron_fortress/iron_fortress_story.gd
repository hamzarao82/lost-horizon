class_name IronFortressStory
extends RefCounted
## Original story text for the Iron Fortress (Milestone 9). Each entry: id -> {title, pages}. Ids are
## underscore-only and short (the saved flag `doc_<id>_found` must stay within 48 characters).
## Continuity with the earlier regions: Project Black Site was named at Outpost 17 and again in the Research
## Complex; the Director was referred to by title only; the containment failure was ordered from below, not an
## accident; the Warden was an earlier experiment; the recovered route table ends here, at the command inland.
## Answers delivered here: who controlled the operation (the Director, Brigadier R. Kessel), why the
## experiments ran (a unit that does not tire, break or refuse), what the containment failure really was
## (a live field test ordered by the command), what the organization intended (to ship the program off the
## island), why the player is involved (the signal that drew them in was bait and a recruitment test), and what
## happens to the operation (stood down). Open threads for optional future content: manifest 9 and its buyer.

const DOCS: Dictionary = {
	"if_patrol_log_1": {
		"title": "Patrol log, Team Ash",
		"pages": [
			"TEAM ASH, last radio log. Four of us, sweep of the north road.",
			"We found the gate closed from the inside and a note taped to it: no patrols past this point, return to quarters. Nobody here would open it.",
			"Whoever ordered it did not want us to see what drove in at night.",
		],
	},
	"if_patrol_log_2": {
		"title": "Patrol log, Team Ash (last page)",
		"pages": [
			"We were told to wait in the yard. That was three days ago. Nobody has come out.",
			"The cook says the barracks lights go out at the same hour every night, and the sentries are changed without a roster.",
			"If anyone reads this: they are not holding us. They are measuring us.",
		],
	},
	"if_checkpoint_log": {
		"title": "Gate checkpoint log",
		"pages": [
			"APPROACH CHECKPOINT. Inbound: supply trucks, covered. Outbound: none in nineteen days.",
			"Gate credentials are issued from the booth panel after the log is signed off. The sergeant signed it off and then left without his cap.",
			"A standing order is pinned inside: the iron gate opens for the Director's convoy, and for no one else.",
		],
	},
	"if_security_control": {
		"title": "Perimeter security control",
		"pages": [
			"PERIMETER CONTROL. Gate actuators: ARMED. Tower feeds: 9 of 12. Barracks gate: LOCKED.",
			"The gate activation sequence is complete. Barracks access now answers to the control panel in this room.",
			"Operator note: the lockdown was written to cascade inward. Each door that opens tells the next one.",
		],
	},
	"if_barracks_roster": {
		"title": "Barracks duty roster",
		"pages": [
			"ROSTER. Two hundred and six names. Column three is headed FITNESS FOR PROGRAM.",
			"A hundred and eleven are marked yes. A hundred and eleven are also marked transferred.",
			"The transfers all end at the same address: Control, below the command.",
		],
	},
	"if_armory_terminal": {
		"title": "Armory manifest",
		"pages": [
			"ARMORY. Issue records: rifles 140, heavy weapons 12, plate 60, command seals 3.",
			"The last signed issue is a heavy weapon to a man called Dunn, who is listed as deceased the same day.",
			"The manifest ends with a line that has been struck out and written again: nothing leaves the armory without the Director's mark.",
		],
	},
	"if_lockdown_relay": {
		"title": "Lockdown relay",
		"pages": [
			"INNER LOCKDOWN, stage one of three. Relay in the barracks block.",
			"Stage one released: the barracks doors no longer hold the command door shut. The remaining stages are inside the walls.",
			"The relay was meant to be turned off by hand, here, by someone who still believed in the drill.",
		],
	},
	"if_orders_1": {
		"title": "Classified order 11",
		"pages": [
			"ORDER 11. Detain any civilian aircraft or boat that enters the island exclusion zone. Do not report.",
			"Cargo of the second transport is to be moved to the Research Complex under seal.",
			"Authorized: the Director.",
		],
	},
	"if_orders_2": {
		"title": "Classified order 23",
		"pages": [
			"ORDER 23. The containment sector is to be tested under field conditions. Cell locks are to be released on signal.",
			"Staff in the sector are to be informed that it is a drill.",
			"Authorized: the Director. Witness: none.",
		],
	},
	"if_orders_3": {
		"title": "Classified order 31",
		"pages": [
			"ORDER 31. Prepare Manifest 9 for removal from the island. Contents not to be itemised.",
			"Buyers are to be met at sea, not in port. No electronic record of the meeting is permitted.",
			"Authorized: the Director.",
		],
	},
	"if_intel_archive": {
		"title": "Intelligence archive",
		"pages": [
			"INTELLIGENCE ARCHIVE, command level. Power: standby.",
			"Index: A, shipments. B, personnel. C, the Dead Coast losses. D, the Blackwood relay. E, Project Black Site. F, the Director's file.",
			"Files E and F need the communications network. Restore it from the operations room.",
		],
	},
	"if_comms_notes": {
		"title": "Communications duty notes",
		"pages": [
			"Comms desk reminder: the relay racks must be set to the pattern on the wall display before the main switch is thrown.",
			"A wrong switch trips the racks off again. Nothing is lost, just do it slowly.",
		],
	},
	"if_ops_files": {
		"title": "Operational files",
		"pages": [
			"OPERATIONS. Network restored. Retrieving files E.",
			"PROJECT BLACK SITE: a program to make soldiers that do not tire, do not break and do not refuse. Phase one on volunteers. Phase two on everyone else.",
			"Outpost 17 was the listening post. The signal you answered went out from here, on purpose, to see who would come.",
		],
	},
	"if_director_dossier": {
		"title": "The Director",
		"pages": [
			"FILE F. Codename: the Director. Brigadier R. Kessel, commanding officer, island garrison.",
			"Kessel authorized every phase, ordered the containment locks released in the research sector, and wrote the report that called it an accident.",
			"Objective, in the Director's own words: an island garrison that cannot be turned, and a program to sell to anyone who wants one.",
			"Kessel is at Control, below the inner fortress. Inner access is issued from the panel in this room.",
		],
	},
	"if_control_records": {
		"title": "Control: final records",
		"pages": [
			"CONTROL. Project Black Site, final record. Subjects: 212. Survivors: 31. Units fielded: 4.",
			"The Warden was Unit 1. The subjects in the research sector were what remained when the field test was allowed to run to its end.",
			"The signal was a test of the last variable: whether an outsider with no orders would follow evidence all the way in.",
		],
	},
	"if_project_archive": {
		"title": "Project archive",
		"pages": [
			"ARCHIVE. Compound formula and trial data, sealed. A note: destroy on completion of Manifest 9.",
			"Manifest 9 left the island by sea two weeks ago. The destination is not recorded here.",
			"Whoever reads this is the only witness not under the Director's orders.",
		],
	},
	"if_end_console": {
		"title": "Final transmission",
		"pages": [
			"STAND DOWN. Command of the island garrison has been transferred to the recovery channel. All units: cease operations, stay in position.",
			"The Director is down. The control network is unlocked and the compound stocks are sealed. The cells are open.",
			"Report sent. Manifest 9 is still out there. That is a different mission.",
		],
	},
}


static func title(id: String) -> String:
	return String((DOCS.get(id, {}) as Dictionary).get("title", "Record"))


static func pages(id: String) -> Array:
	return (DOCS.get(id, {}) as Dictionary).get("pages", ["(no data)"])


## One body text for a LoreDocument (pages joined).
static func body(id: String) -> String:
	return "\n".join(PackedStringArray(pages(id)))
