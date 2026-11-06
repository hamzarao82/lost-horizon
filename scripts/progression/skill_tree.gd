class_name SkillTree
extends RefCounted
## Skill rules over a set of SkillData: prerequisites, level gates, costs and node states.

enum State { LOCKED, AVAILABLE, OWNED, MAXED }

const SKILL_DIR: String = "res://resources/progression/skills/"

var skills: Dictionary = {}  # id -> SkillData


static func load_default() -> SkillTree:
	var tree := SkillTree.new()
	for file in DirAccess.get_files_at(SKILL_DIR):
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var skill := load(SKILL_DIR + file_name) as SkillData
			if skill:
				tree.skills[skill.id] = skill
	return tree


func get_skill(id: StringName) -> SkillData:
	return skills.get(id) as SkillData


func all() -> Array:
	var list := skills.values()
	list.sort_custom(func(a: SkillData, b: SkillData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.tree_position.y < b.tree_position.y or (a.tree_position.y == b.tree_position.y and a.tree_position.x < b.tree_position.x))
	return list


## Empty string means the next rank can be bought; otherwise the reason it cannot.
func block_reason(progress: PlayerProgress, id: StringName) -> String:
	var skill := get_skill(id)
	if skill == null:
		return "Unknown skill"
	if progress.skill_rank(id) >= skill.max_rank:
		return "Already at maximum rank"
	if progress.level() < skill.min_level:
		return "Requires level %d" % skill.min_level
	for pre in skill.prerequisites:
		if progress.skill_rank(StringName(pre)) < 1:
			var pre_skill := get_skill(StringName(pre))
			return "Requires %s" % (pre_skill.display_name if pre_skill else String(pre))
	if progress.skill_points < skill.cost:
		return "Needs %d skill point%s" % [skill.cost, "" if skill.cost == 1 else "s"]
	return ""


func can_buy(progress: PlayerProgress, id: StringName) -> bool:
	return block_reason(progress, id) == ""


## Spends the points and raises the rank by one. Returns false (and changes nothing) when blocked.
func buy(progress: PlayerProgress, id: StringName) -> bool:
	if not can_buy(progress, id):
		return false
	progress.skill_points -= get_skill(id).cost
	progress.skills[id] = progress.skill_rank(id) + 1
	return true


func state(progress: PlayerProgress, id: StringName) -> State:
	var skill := get_skill(id)
	if skill == null:
		return State.LOCKED
	var rank := progress.skill_rank(id)
	if rank >= skill.max_rank:
		return State.MAXED
	if rank > 0:
		return State.OWNED
	for pre in skill.prerequisites:
		if progress.skill_rank(StringName(pre)) < 1:
			return State.LOCKED
	return State.AVAILABLE if progress.level() >= skill.min_level else State.LOCKED


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for id in skills:
		var skill: SkillData = skills[id]
		errors.append_array(skill.validate())
		for pre in skill.prerequisites:
			if not skills.has(StringName(pre)):
				errors.append("%s: missing prerequisite %s" % [id, pre])
		if _has_cycle(id, {}):
			errors.append("%s: prerequisite cycle" % id)
	return errors


func _has_cycle(id: StringName, seen: Dictionary) -> bool:
	if seen.has(id):
		return true
	seen[id] = true
	var skill := get_skill(id)
	if skill:
		for pre in skill.prerequisites:
			if _has_cycle(StringName(pre), seen.duplicate()):
				return true
	return false
