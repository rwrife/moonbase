class_name BuildingCatalog
extends RefCounted

const ORDER: Array[String] = [
	"link", "habitat", "solar", "reactor", "ice", "oxygen", "lab", "mine"
]

const DATA: Dictionary = {
	"link": {
		"name": "Utility link", "cost": 20, "upkeep": 0,
		"color": Color(0.28, 0.58, 0.65),
		"description": "Connect adjacent modules. Carries all four utilities."
	},
	"habitat": {
		"name": "Habitat", "cost": 250, "upkeep": 2, "power_use": 3,
		"water_use": 2, "oxygen_use": 2, "heat_use": 2,
		"color": Color(0.78, 0.82, 0.88),
		"description": "8 crew. Uses 3 power, 2 water, 2 oxygen and 2 heat."
	},
	"solar": {
		"name": "Solar array", "cost": 160, "upkeep": 1, "power": 12,
		"color": Color(0.13, 0.32, 0.64),
		"description": "12 power in sunlight; zero during lunar night."
	},
	"reactor": {
		"name": "Fission reactor", "cost": 600, "upkeep": 6, "power": 24, "heat": 12,
		"color": Color(0.91, 0.58, 0.24),
		"description": "24 power and 12 heat, including at night. No fuel model yet."
	},
	"ice": {
		"name": "Ice extractor", "cost": 200, "upkeep": 2, "power_use": 3, "water": 10,
		"color": Color(0.32, 0.76, 0.85),
		"description": "10 water using 3 power. Requires a blue ice tile."
	},
	"oxygen": {
		"name": "Life support", "cost": 220, "upkeep": 2,
		"power_use": 3, "water_use": 2, "oxygen": 12, "heat": 4,
		"color": Color(0.38, 0.78, 0.56),
		"description": "12 oxygen and 4 heat using 3 power and 2 water."
	},
	"lab": {
		"name": "Science lab", "cost": 300, "upkeep": 3, "power_use": 4,
		"color": Color(0.68, 0.52, 0.89),
		"description": "1 science/day when powered and all crew are supplied."
	},
	"mine": {
		"name": "Regolith refinery", "cost": 280, "upkeep": 3, "power_use": 5,
		"color": Color(0.72, 0.61, 0.44),
		"description": "2 exports/day at 12 credits each, with power and safe crew."
	}
}


static func definition(kind: String) -> Dictionary:
	return DATA[kind]
