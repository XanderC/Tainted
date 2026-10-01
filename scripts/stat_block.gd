class_name StatBlock
extends RefCounted
## PoE-style stat calculation.
## final = (base + sum(FLAT)) * (1 + sum(INCREASED)) * product(1 + MORE)
## INCREASED mods add together; MORE mods multiply. Build all gear/skill/passive
## bonuses on top of this so balance stays predictable.

enum ModType { FLAT, INCREASED, MORE }

var base: Dictionary = {}
var _mods: Dictionary = {}  # stat name -> Array of {type, value, source}


func set_base(stat: String, value: float) -> void:
	base[stat] = value


func add_mod(stat: String, type: int, value: float, source: Variant) -> void:
	if not _mods.has(stat):
		_mods[stat] = []
	_mods[stat].append({"type": type, "value": value, "source": source})


## Remove every modifier that came from one source (e.g. an unequipped item).
func remove_source(source: Variant) -> void:
	for stat in _mods.keys():
		_mods[stat] = _mods[stat].filter(func(m): return not is_same(m.source, source))


func get_stat(stat: String) -> float:
	var flat := float(base.get(stat, 0.0))
	var inc := 0.0
	var more := 1.0
	for m in _mods.get(stat, []):
		match m.type:
			ModType.FLAT:
				flat += m.value
			ModType.INCREASED:
				inc += m.value
			ModType.MORE:
				more *= (1.0 + m.value)
	return flat * (1.0 + inc) * more
