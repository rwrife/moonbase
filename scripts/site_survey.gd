class_name SiteSurvey
extends RefCounted

## Hand-authored immovable landmarks inside the surveyed site. Positions are world
## units on the XZ plane; radii are world units. Bulldozers cannot clear these.

const CELL_SIZE := 2.3
const LANDMARK_CRATERS: Array[Vector3] = [
	Vector3(14.2, -13.6, 5.4),
	Vector3(-16.4, 15.4, 4.0),
	Vector3(19.4, 8.6, 3.1),
]
const BOULDERS: Array[Vector3] = [
	Vector3(9.5, 7.2, 1.05),
	Vector3(-11.2, -11.9, 1.3),
	Vector3(4.9, 18.1, 0.95),
	Vector3(20.4, -2.0, 1.15),
	Vector3(-13.6, 4.4, 0.85),
	Vector3(-4.3, -16.4, 1.2),
	Vector3(-21.0, -4.9, 1.0),
]


static func blocked_cells(radius: int) -> Dictionary:
	var result := {}
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var cell := Vector2i(x, y)
			var reason := feature_at(cell)
			if not reason.is_empty():
				result[cell] = reason
	return result


static func feature_at(cell: Vector2i) -> String:
	var center := Vector2(cell.x, cell.y) * CELL_SIZE
	for crater in LANDMARK_CRATERS:
		if center.distance_to(Vector2(crater.x, crater.y)) < crater.z * 1.05:
			return "crater"
	for boulder in BOULDERS:
		if center.distance_to(Vector2(boulder.x, boulder.y)) < boulder.z + CELL_SIZE * 0.45:
			return "boulder"
	return ""
