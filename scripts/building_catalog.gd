class_name BuildingCatalog
extends RefCounted

const DIR_N := Vector2i(0, -1)
const DIR_E := Vector2i(1, 0)
const DIR_S := Vector2i(0, 1)
const DIR_W := Vector2i(-1, 0)

const ALL_DIRS: Array[Vector2i] = [DIR_N, DIR_E, DIR_S, DIR_W]

const BIT_N := 1
const BIT_E := 2
const BIT_S := 4
const BIT_W := 8

const ORDER: Array[String] = [
	"support_hub", "tunnel", "power_line",
	"habitat", "solar", "reactor", "ice", "oxygen", "lab", "mine", "landing_pad"
]

## Standardized connectors in local unrotated space (facing 0: front = +Z / DIR_S):
## - service_ports: centerline docking corridor carrying humans, water, oxygen, heat and resources.
##   Most modules have 2 opposite ports (DIR_S, DIR_N) to chain linearly; terminal modules have 1 (DIR_S).
## - power_ports: HV electrical bus connections (also passed through mated service connectors).
const DATA: Dictionary = {
	"support_hub": {
		"name": "4-Way adapter", "cost": 90, "upkeep": 1,
		"color": Color(0.32, 0.72, 0.82),
		"service_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"power_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"is_hub": true,
		"description": "4-way pressurized hub and utility adapter. Connects humans, resources and power in all 4 directions."
	},
	"tunnel": {
		"name": "Connection tunnel", "cost": 20, "upkeep": 0,
		"color": Color(0.28, 0.58, 0.65),
		"service_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"power_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"is_line": true,
		"description": "Pressurized service corridor (drag to route). Carries humans, water, oxygen, heat and power."
	},
	"power_line": {
		"name": "Power line", "cost": 6, "upkeep": 0,
		"color": Color(0.95, 0.72, 0.22),
		"service_ports": [],
		"power_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"is_line": true,
		"power_only": true,
		"description": "Elevated HV power line (drag to route). Carries electricity only; crosses cleanly over tunnels."
	},
	"habitat": {
		"name": "Habitat", "cost": 250, "upkeep": 2, "power_use": 3,
		"water_use": 2, "oxygen_use": 2, "heat_use": 2,
		"color": Color(0.78, 0.82, 0.88),
		"service_ports": [DIR_S, DIR_N],
		"power_ports": [DIR_S, DIR_N, DIR_E, DIR_W],
		"description": "8 crew (2-port chainable). Uses 3 power, 2 water, 2 oxygen and 2 heat."
	},
	"solar": {
		"name": "Solar array", "cost": 160, "upkeep": 1, "power": 12,
		"color": Color(0.13, 0.32, 0.64),
		"service_ports": [DIR_S],
		"power_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"description": "12 power in sunlight; zero at night (1-port terminal; wire remotely via power lines)."
	},
	"reactor": {
		"name": "Fission reactor", "cost": 600, "upkeep": 6, "power": 24, "heat": 12,
		"color": Color(0.91, 0.58, 0.24),
		"service_ports": [DIR_S],
		"power_ports": [DIR_N, DIR_E, DIR_S, DIR_W],
		"description": "24 power and 12 heat, including at night (1-port terminal; wire remotely via power lines)."
	},
	"ice": {
		"name": "Ice extractor", "cost": 200, "upkeep": 2, "power_use": 3, "water": 10,
		"color": Color(0.32, 0.76, 0.85),
		"service_ports": [DIR_S],
		"power_ports": [DIR_S, DIR_E, DIR_W],
		"description": "10 water using 3 power (1-port terminal). Requires a frosted ice tile."
	},
	"oxygen": {
		"name": "Life support", "cost": 220, "upkeep": 2,
		"power_use": 3, "water_use": 2, "oxygen": 12, "heat": 4,
		"color": Color(0.38, 0.78, 0.56),
		"service_ports": [DIR_S, DIR_N],
		"power_ports": [DIR_S, DIR_N, DIR_E, DIR_W],
		"description": "12 oxygen and 4 heat using 3 power and 2 water (2-port chainable)."
	},
	"lab": {
		"name": "Science lab", "cost": 300, "upkeep": 3, "power_use": 4,
		"color": Color(0.68, 0.52, 0.89),
		"service_ports": [DIR_S, DIR_N],
		"power_ports": [DIR_S, DIR_N, DIR_E, DIR_W],
		"requires_crew_access": true,
		"description": "1 science/day (2-port chainable). Requires power and service-corridor crew access."
	},
	"mine": {
		"name": "Regolith refinery", "cost": 280, "upkeep": 3, "power_use": 5,
		"color": Color(0.72, 0.61, 0.44),
		"service_ports": [DIR_S, DIR_N],
		"power_ports": [DIR_S, DIR_N, DIR_E, DIR_W],
		"requires_crew_access": true,
		"description": "2 exports/day at 12 cr each (2-port chainable). Requires power and service-corridor crew access."
	},
	"landing_pad": {
		"name": "Landing pad", "cost": 240, "upkeep": 0,
		"color": Color(0.86, 0.68, 0.28),
		"service_ports": [DIR_S],
		"power_ports": [DIR_S, DIR_E, DIR_W],
		"description": "Receives +4 t supplies every 6 days per operational pad (1-port terminal; self-powered)."
	}
}


static func canonical_kind(kind: String) -> String:
	return "tunnel" if kind == "link" else kind


static func has_kind(kind: String) -> bool:
	return DATA.has(canonical_kind(kind))


static func definition(kind: String) -> Dictionary:
	return DATA[canonical_kind(kind)]


static func is_power_only(kind: String) -> bool:
	return bool(definition(kind).get("power_only", false))


static func is_line_tool(kind: String) -> bool:
	return bool(definition(kind).get("is_line", false))


static func normalize_facing(facing: int) -> int:
	return ((facing % 4) + 4) % 4


## Rotates a local cardinal direction by facing * 90 deg around +Y (matching Node3D.rotation_degrees.y).
static func rotate_dir(local_dir: Vector2i, facing: int) -> Vector2i:
	match normalize_facing(facing):
		1:
			return Vector2i(local_dir.y, -local_dir.x)
		2:
			return Vector2i(-local_dir.x, -local_dir.y)
		3:
			return Vector2i(-local_dir.y, local_dir.x)
	return local_dir


## Converts a world cardinal direction into the module's local unrotated frame.
static func unrotate_dir(world_dir: Vector2i, facing: int) -> Vector2i:
	return rotate_dir(world_dir, -facing)


static func dir_bit(direction: Vector2i) -> int:
	if direction == DIR_N:
		return BIT_N
	if direction == DIR_E:
		return BIT_E
	if direction == DIR_S:
		return BIT_S
	if direction == DIR_W:
		return BIT_W
	return 0


static func world_service_ports(kind: String, facing: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for local_dir: Vector2i in definition(kind).get("service_ports", []):
		result.append(rotate_dir(local_dir, facing))
	return result


static func world_power_ports(kind: String, facing: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for local_dir: Vector2i in definition(kind).get("power_ports", []):
		result.append(rotate_dir(local_dir, facing))
	return result


static func facing_label(facing: int) -> String:
	match normalize_facing(facing):
		0:
			return "South (+Z)"
		1:
			return "East (+X)"
		2:
			return "North (-Z)"
		3:
			return "West (-X)"
	return "South (+Z)"
