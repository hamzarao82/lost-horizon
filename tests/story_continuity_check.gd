extends SceneTree
## Read-only story and campaign continuity checks (no resource or script is changed).
## godot --headless --path . -s tests/story_continuity_check.gd
## Producer checks are text heuristics (see tools/campaign_audit_lib.gd): they prove a flag name appears in code or
## matches a confirmed dynamic pattern, not that the code path runs. The campaign bots prove behaviour.

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


func _run() -> void:
	var rows: Array[Dictionary] = CampaignAudit.quests()
	var docs: Array[Dictionary] = CampaignAudit.documents()
	var regions: Array[Dictionary] = CampaignAudit.regions()
	var doc_ids: Array[String] = []
	for d in docs:
		doc_ids.append(String(d["id"]))
	var region_ids: Array[String] = []
	for r in regions:
		region_ids.append(String((r["data"] as RegionData).id))

	_check(rows.size() >= 15, "all quest files are found (%d)" % rows.size())
	var ids: Dictionary = {}
	var objective_total := 0
	var all_flags: Dictionary = {}
	for row in rows:
		var path: String = row["path"]
		var q := row["quest"] as QuestData
		_check(q != null, "%s loads as QuestData" % path.get_file())
		if q == null:
			continue
		var errors := q.validate()
		_check(errors.is_empty(), "%s validates (%s)" % [q.id, "; ".join(errors)])
		_check(not ids.has(q.id), "quest id %s is unique" % q.id)
		ids[q.id] = path
		var objective_ids: Dictionary = {}
		var unique_objectives := true
		for o in q.objectives:
			objective_total += 1
			if objective_ids.has(o.id):
				unique_objectives = false
			objective_ids[o.id] = true
			if o.type == ObjectiveData.Type.FLAG:
				for t in o.targets:
					all_flags[String(t)] = "quest %s" % q.id
			if o.hidden_until != &"":
				all_flags[String(o.hidden_until)] = "quest %s (hidden_until)" % q.id
			if o.type in [ObjectiveData.Type.INTERACT, ObjectiveData.Type.ENTER_AREA, ObjectiveData.Type.DISCOVER]:
				for t in o.targets:
					_check(CampaignAudit.interact_target_known(String(t)), "%s/%s target '%s' is produced by some script" % [q.id, o.id, t])
		_check(unique_objectives, "%s has unique objective ids" % q.id)
		_check(q.objectives.size() > 0, "%s has objectives" % q.id)
		for item_id in q.rewards:
			_check(ResourceLoader.exists("res://resources/items/%s.tres" % item_id), "%s reward '%s' exists" % [q.id, item_id])
	for row in rows:
		var q2 := row["quest"] as QuestData
		if q2 == null:
			continue
		for pre in q2.prerequisites:
			_check(ids.has(StringName(pre)), "%s prerequisite '%s' exists" % [q2.id, pre])
		if q2.next_quest != &"":
			_check(ids.has(q2.next_quest), "%s next quest '%s' exists" % [q2.id, q2.next_quest])
	_check(objective_total >= 90, "objective count is plausible (%d)" % objective_total)

	for r in regions:
		var data := r["data"] as RegionData
		if data.scene_path != "":
			_check(ResourceLoader.exists(data.scene_path), "region %s scene path loads (%s)" % [data.id, data.scene_path])
		if data.unlock_flag != &"":
			all_flags[String(data.unlock_flag)] = "region %s unlock_flag" % data.id
	var chain: Variant = CampaignAudit.script_constant("res://scripts/regions/campaign_flow.gd", "CHAIN")
	_check(chain is Dictionary and (chain as Dictionary).size() >= 3, "the campaign chain table is readable")
	if chain is Dictionary:
		for region in chain:
			var entry: Dictionary = chain[region]
			all_flags[String(entry.get("after", ""))] = "CHAIN %s" % region
			for a in entry.get("aliases", []):
				all_flags[String(a)] = "CHAIN %s alias" % region
			_check(region_ids.has(String(region)), "chain region %s has a RegionData file" % region)

	for flag in all_flags:
		_check(CampaignAudit.flag_name_ok(String(flag)), "flag '%s' obeys [a-z0-9_] and 48 characters" % flag)
		var producer: Dictionary = CampaignAudit.flag_producer(String(flag), doc_ids, region_ids)
		_check(bool(producer["ok"]), "flag '%s' (%s) has a producer: %s" % [flag, all_flags[flag], producer["how"]])

	var seen_docs: Dictionary = {}
	for d in docs:
		_check(String(d["body"]).strip_edges() != "", "document %s has text" % d["id"])
		_check(String(d["title"]).strip_edges() != "", "document %s has a title" % d["id"])
		_check(not seen_docs.has(d["id"]), "document id %s is unique across regions" % d["id"])
		seen_docs[d["id"]] = d["region"]
		_check(CampaignAudit.flag_name_ok("doc_%s_found" % d["id"]), "document %s keeps its found flag within the rule" % d["id"])
	var regions_with_docs: Dictionary = {}
	for d in docs:
		regions_with_docs[d["region"]] = int(regions_with_docs.get(d["region"], 0)) + 1
	_check(regions_with_docs.size() >= 4, "documents exist for four regions (%s)" % str(regions_with_docs))
	print("Iron Fortress in master: ", ResourceLoader.exists("res://scripts/regions/iron_fortress/iron_fortress_region.gd") or DirAccess.dir_exists_absolute("res://scripts/regions/iron_fortress"))
	print("story_continuity_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
