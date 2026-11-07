extends SceneTree
## Read-only campaign audit: prints markdown tables of every quest, every region, every story document and a list of
## broken dependencies. Writes nothing.  godot --headless --path . -s tools/campaign_audit.gd

var _problems: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var quest_rows: Array[Dictionary] = CampaignAudit.quests()
	var docs: Array[Dictionary] = CampaignAudit.documents()
	var regions: Array[Dictionary] = CampaignAudit.regions()
	var doc_ids: Array[String] = []
	for d in docs:
		doc_ids.append(String(d["id"]))
	var region_ids: Array[String] = []
	for r in regions:
		region_ids.append(String((r["data"] as RegionData).id))

	print("## Quests (%d files)" % quest_rows.size())
	print("| region | quest id | title | category | required | optional | rewards | prerequisites | next | flag objectives |")
	print("|---|---|---|---|---:|---:|---|---|---|---|")
	var seen: Dictionary = {}
	var flags_used: Dictionary = {}
	var total_objectives := 0
	for row in quest_rows:
		var path := String(row["path"])
		var q := row["quest"] as QuestData
		if q == null:
			_problems.append("quest file does not load as QuestData: %s" % path)
			continue
		if seen.has(q.id):
			_problems.append("duplicate quest id %s in %s and %s" % [q.id, seen[q.id], path])
		seen[q.id] = path
		var req := 0
		var opt := 0
		var flag_targets: Array[String] = []
		var obj_ids: Dictionary = {}
		for o in q.objectives:
			total_objectives += 1
			if o.optional:
				opt += 1
			else:
				req += 1
			if obj_ids.has(o.id):
				_problems.append("quest %s repeats objective id %s" % [q.id, o.id])
			obj_ids[o.id] = true
			if o.type == ObjectiveData.Type.FLAG:
				for t in o.targets:
					flag_targets.append(String(t))
					flags_used[String(t)] = "quest %s objective %s" % [q.id, o.id]
			if o.hidden_until != &"":
				flags_used[String(o.hidden_until)] = "quest %s objective %s (hidden_until)" % [q.id, o.id]
			if o.type in [ObjectiveData.Type.INTERACT, ObjectiveData.Type.ENTER_AREA, ObjectiveData.Type.DISCOVER]:
				for t in o.targets:
					if not CampaignAudit.interact_target_known(String(t)):
						_problems.append("quest %s objective %s targets '%s' which no script mentions" % [q.id, o.id, t])
		for item_id in q.rewards:
			if not ResourceLoader.exists("res://resources/items/%s.tres" % item_id):
				_problems.append("quest %s rewards unknown item '%s'" % [q.id, item_id])
		for pre in q.prerequisites:
			var found := false
			for r2 in quest_rows:
				if r2["quest"] != null and String((r2["quest"] as QuestData).id) == String(pre):
					found = true
			if not found:
				_problems.append("quest %s needs prerequisite '%s' that does not exist" % [q.id, pre])
		if q.next_quest != &"":
			var found_next := false
			for r3 in quest_rows:
				if r3["quest"] != null and (r3["quest"] as QuestData).id == q.next_quest:
					found_next = true
			if not found_next:
				_problems.append("quest %s points at missing next quest '%s'" % [q.id, q.next_quest])
		print("| %s | %s | %s | %s | %d | %d | %s | %s | %s | %s |" % [CampaignAudit.region_of_quest_path(path), q.id,
				q.title, QuestData.Category.keys()[q.category], req, opt, ", ".join(PackedStringArray(q.rewards)),
				", ".join(PackedStringArray(q.prerequisites)), q.next_quest, ", ".join(PackedStringArray(flag_targets))])
	print("\nTotal objectives: %d" % total_objectives)

	print("\n## Regions (%d)" % regions.size())
	print("| region | name | scene | scene loads | unlock flag | flag producer |")
	print("|---|---|---|---|---|---|")
	for r in regions:
		var data := r["data"] as RegionData
		var loads := data.scene_path != "" and ResourceLoader.exists(data.scene_path)
		var producer := {"ok": true, "how": "none needed"}
		if data.unlock_flag != &"":
			producer = CampaignAudit.flag_producer(String(data.unlock_flag), doc_ids, region_ids)
			flags_used[String(data.unlock_flag)] = "region %s unlock_flag" % data.id
		print("| %s | %s | %s | %s | %s | %s |" % [data.id, data.display_name, data.scene_path, loads, data.unlock_flag, producer["how"]])
		if data.scene_path != "" and not loads:
			_problems.append("region %s scene path does not exist: %s" % [data.id, data.scene_path])

	var chain: Variant = CampaignAudit.script_constant("res://scripts/regions/campaign_flow.gd", "CHAIN")
	if chain is Dictionary:
		print("\n## Campaign chain (CampaignFlow.CHAIN)")
		for region in chain:
			var entry: Dictionary = chain[region]
			print("- %s unlocks after `%s` (aliases: %s)" % [region, entry.get("after", ""), entry.get("aliases", [])])
			flags_used[String(entry.get("after", ""))] = "CHAIN %s after" % region
			for a in entry.get("aliases", []):
				flags_used[String(a)] = "CHAIN %s alias" % region

	print("\n## Flags referenced by quests, regions and the chain (%d)" % flags_used.size())
	print("| flag | referenced by | rule ok | producer |")
	print("|---|---|---|---|")
	var names: Array = flags_used.keys()
	names.sort()
	for f in names:
		var prod := CampaignAudit.flag_producer(String(f), doc_ids, region_ids)
		var ok := CampaignAudit.flag_name_ok(String(f))
		print("| %s | %s | %s | %s |" % [f, flags_used[f], ok, prod["how"]])
		if not ok:
			_problems.append("flag '%s' breaks the [a-z0-9_] / 48 character rule" % f)
		if not bool(prod["ok"]):
			_problems.append("flag '%s' (%s): %s" % [f, flags_used[f], prod["how"]])

	print("\n## Story documents (%d)" % docs.size())
	print("| region | id | title | words |")
	print("|---|---|---|---:|")
	var by_id: Dictionary = {}
	for d in docs:
		var text := String(d["body"])
		print("| %s | %s | %s | %d |" % [d["region"], d["id"], d["title"], text.split(" ", false).size()])
		if text.strip_edges() == "":
			_problems.append("document %s has no text" % d["id"])
		if by_id.has(d["id"]):
			_problems.append("document id %s appears twice (%s and %s)" % [d["id"], by_id[d["id"]], d["region"]])
		by_id[d["id"]] = d["region"]
	print("\n## Near-duplicate documents (word overlap >= 0.45)")
	for i in docs.size():
		for j in range(i + 1, docs.size()):
			var sim := CampaignAudit.similarity(String(docs[i]["body"]), String(docs[j]["body"]))
			if sim >= 0.45:
				print("- %s vs %s: %.2f" % [docs[i]["id"], docs[j]["id"], sim])

	print("\n## Broken dependencies and warnings (%d)" % _problems.size())
	for p in _problems:
		print("- " + p)
	quit()
