class_name SecurityDoor
extends Door
## A Door that needs a credential level (flag `credential_<level>`). Opening it is remembered twice:
## by the Door's own world flag and by a PersistentIds claim, so it stays open after a reload.

@export var credential: StringName = &"admin"


func _ready() -> void:
	locked_by_flag = FacilityIds.credential_flag(credential)
	lock_reason = "Access denied: %s credential required" % String(credential)
	super._ready()
	if PersistentIds.is_claimed(FacilityIds.REGION, claim_id()):
		open(false)


func claim_id() -> StringName:
	return StringName("door_%s" % String(door_id))


func open(animate: bool = true) -> void:
	var was_open := is_open
	super(animate)
	if is_open and not was_open:
		PersistentIds.claim(FacilityIds.REGION, claim_id())
