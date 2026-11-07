class_name ResearchComplexStory
extends RefCounted
## Original story text for the Research Complex (Milestone 8). Each entry: id -> {title, pages}.
## Ids are underscore-only and short (the saved flag `doc_<id>_found` must stay within 48 characters).
## Continuity: Project Black Site was already named in Outpost 17; the Director is referred to by title
## only; the Warden is an earlier experiment; the data points on to the command at the Iron Fortress.

const DOCS: Dictionary = {
	"rc_checkpoint_log": {
		"title": "Checkpoint logbook",
		"pages": [
			"GATE LOG, perimeter checkpoint.",
			"Last six entries: three transports in, none out. Sealed crates, no manifests. The driver of the third refused to sign.",
			"Standing order pinned to the desk: no guard may enter the main building. Keycards are issued at the desk and returned at the desk.",
			"A hand has added in pencil: they stopped coming out three weeks ago.",
		],
	},
	"rc_visitor_log": {
		"title": "Reception visitor log",
		"pages": [
			"Visitors are logged by badge number only. Names are not recorded.",
			"Eleven badges signed in on the last day. One signed out.",
			"A note clipped to the page: do not let the medical staff leave through the front. Use the lower corridor.",
		],
	},
	"rc_staff_memo": {
		"title": "Staff memo",
		"pages": [
			"TO ALL STAFF: Compartment 7 is not discussed outside Compartment 7.",
			"Any request for 'volunteers' is to be filed under logistics, not personnel.",
			"The Director has approved the next phase. Questions go to your section head, not to the Director.",
		],
	},
	"rc_security_console": {
		"title": "Security network",
		"pages": [
			"Network status: OFFLINE. Door controllers: standby. Camera feeds: 14 of 22 dark.",
			"Rebooting the control mesh. Archive power and the medical corridor release now answer to the security console.",
			"The last operator left a line in the log: lockdown was ordered from below. Not from here.",
		],
	},
	"rc_archive_breaker": {
		"title": "Archive power panel",
		"pages": [
			"Breaker bank 3: archive and records. Restoring the feed to the archive terminal.",
		],
	},
	"rc_archive_terminal": {
		"title": "Research archive",
		"pages": [
			"CLASSIFIED: SECTION INDEX. A to C: logistics and transfers. D: medical trials. E: containment protocols. F: Project Black Site.",
			"Trial summaries list 'subjects' by number, 1 to 31. Column four reads: consent, none recorded.",
			"Every transfer slip ends with the same line: to be completed at the command, not here. This facility was never the whole of it.",
		],
	},
	"rc_medical_evidence": {
		"title": "Trial notes, Dr. Hale",
		"pages": [
			"Subject 11 no longer answers to name or order. Subject 14 did, for four days.",
			"The compound does what we hoped. It does not stop. We keep adjusting the dose; the subjects keep adjusting to it.",
			"If the review board reads this, I want it recorded that I asked to stop at subject nineteen.",
		],
	},
	"rc_subject_roster": {
		"title": "Subject roster",
		"pages": [
			"Thirty-one numbers, thirty-one origins. Twenty-two of them are military: soldiers reported missing in the field.",
			"The rest are marked simply: found.",
		],
	},
	"rc_ward_notice": {
		"title": "Ward notice",
		"pages": [
			"Visiting hours do not exist. Do not speak to the patients through the glass.",
			"If a patient speaks to you, report it. If it speaks in your voice, report it twice.",
		],
	},
	"rc_exam_note": {
		"title": "Examination note",
		"pages": [
			"Scar tissue consistent with restraint, repeated. Blood work shows the compound at levels no clinic would sign for.",
			"Recommend immediate transfer to containment. Recommend, in writing, that someone ask why.",
		],
	},
	"rc_incident_report": {
		"title": "Containment incident report",
		"pages": [
			"INCIDENT 0214. The cell locks were not broken. They were released from the control level at 02:14, in sequence, one block at a time.",
			"Security recorded no attack. It recorded an order. The release was authorised with a command key, not forced with a tool.",
			"Official finding to be entered: equipment failure. The Director's office has asked that this page not be copied.",
		],
	},
	"rc_override_notes": {
		"title": "Technician notes",
		"pages": [
			"Emergency override: three consoles, any order, forty-five seconds from the first. If the window closes, start again. Nothing you finished is undone.",
			"Then the lever. Pull it before the third console and it only complains.",
		],
	},
	"rc_lab_notes": {
		"title": "Laboratory notes",
		"pages": [
			"The compound is stable only in the second generation. The first generation was a test of what the body can be made to endure.",
			"Phase two cannot be run here. Equipment is being moved to the command. We were the proof of concept.",
		],
	},
	"rc_director_order": {
		"title": "Order, Director's office",
		"pages": [
			"The containment failure is to be reported as an accident. No inquiry. No survivors' statements.",
			"All research data is to be copied to the command and the originals sealed. The island's command has what it needs.",
			"Signed with a title, not a name.",
		],
	},
	"rc_black_site_data": {
		"title": "PROJECT BLACK SITE: recovered data",
		"pages": [
			"Transfer complete. 4.2 GB of trial records, containment logs and a route table.",
			"The route table has one destination. It is not on any chart of the coast: the command, inland, behind the iron gate.",
			"The order of authority is written in one line: Black Site answers to the Director. The Director answers to no one on this island.",
			"The way out is below. Take the data and go.",
		],
	},
	"rc_exit_notice": {
		"title": "Underground exit",
		"pages": [
			"Service tunnel: leads to the supply road. The gate at the far end is sealed from the other side.",
			"Access to the Iron Fortress road is sealed. For now.",
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
