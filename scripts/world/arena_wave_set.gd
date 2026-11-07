class_name ArenaWaveSet
extends Resource
## Per-wave composition of the courtyard arena as data: enemy scene paths in spawn order, the gap
## between spawns and the rest window before the next wave. `WaveManager.WAVES` mirrors the enemy
## lists (other scripts read its size as a constant); a test fails if the two drift apart.

@export var waves: Array[Dictionary] = []


func wave_count() -> int:
	return waves.size()


func enemies_of(index: int) -> Array:
	if index < 0 or index >= waves.size():
		return []
	return waves[index].get("enemies", [])


func spacing_of(index: int, fallback: float) -> float:
	if index < 0 or index >= waves.size():
		return fallback
	return float(waves[index].get("spacing", fallback))


func rest_of(index: int, fallback: float) -> float:
	if index < 0 or index >= waves.size():
		return fallback
	return float(waves[index].get("rest", fallback))
