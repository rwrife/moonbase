class_name ColonySaveStore
extends RefCounted

## Authoritative save/load coordinator managing slots, overwrite policies,
## atomic writes, backups, schema validation/migration, and explicit error recovery.

const SLOT_MANUAL := "manual"
const SLOT_AUTOSAVE := "autosave"

enum OverwritePolicy {
	## Permit saving only if the slot is empty or belongs to the same colony_id.
	SAME_COLONY_ONLY,
	## Permit overwriting another valid colony's save (with backup rotation),
	## while still protecting corrupt or unsupported newer files.
	ALLOW_DIFFERENT_COLONY,
	## Explicit user-forced overwrite of any existing slot content without
	## replacing a healthy backup with corrupt bytes.
	ALLOW_ANY,
}

var backend: SaveStorageBackend


func _init(storage_backend: SaveStorageBackend = null) -> void:
	backend = storage_backend if storage_backend != null else SaveStorageBackend.create_default()


static func primary_key(slot_id: String) -> String:
	return "%s.json" % _sanitize_slot(slot_id)


static func backup_key(slot_id: String) -> String:
	return "%s.json.bak" % _sanitize_slot(slot_id)


static func _sanitize_slot(slot_id: String) -> String:
	var cleaned := slot_id.strip_edges().to_lower()
	if cleaned.is_empty():
		return SLOT_MANUAL
	var out := ""
	for i in range(cleaned.length()):
		var ch := cleaned.unicode_at(i)
		var is_alnum := (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 95 or ch == 45
		if is_alnum:
			out += char(ch)
	return out if not out.is_empty() else SLOT_MANUAL


func check_storage() -> Dictionary:
	return backend.is_available()


func inspect_slot(slot_id: String, inspect_backup: bool = false,
		blocked_map: Dictionary = {}) -> Dictionary:
	var key := backup_key(slot_id) if inspect_backup else primary_key(slot_id)
	var read_res := backend.read_text(key)
	if not read_res["ok"]:
		return {
			"ok": false,
			"exists": bool(read_res.get("exists", false)),
			"error_code": str(read_res["error_code"]),
			"error": str(read_res["error"]),
			"location": str(read_res.get("location", "")),
			"colony_id": "",
			"summary": {},
			"migrated_from": 0,
			"saved_at_unix": 0,
		}
	if not bool(read_res["exists"]):
		return {
			"ok": false,
			"exists": false,
			"error_code": "missing",
			"error": "No saved colony found in '%s'." % slot_id,
			"location": str(read_res.get("location", "")),
			"colony_id": "",
			"summary": {},
			"migrated_from": 0,
			"saved_at_unix": 0,
		}
	var text := str(read_res["text"])
	if text.strip_edges().is_empty():
		return {
			"ok": false,
			"exists": true,
			"error_code": "corrupt_json",
			"error": "Save file '%s' is empty or truncated. The file was preserved untouched." % key,
			"location": str(read_res.get("location", "")),
			"colony_id": "",
			"summary": {},
			"migrated_from": 0,
			"saved_at_unix": 0,
		}
	var parser := JSON.new()
	var parse_err := parser.parse(text)
	if parse_err != OK:
		return {
			"ok": false,
			"exists": true,
			"error_code": "corrupt_json",
			"error": "Save file '%s' is corrupted (JSON parse error at line %d: %s). The file was preserved untouched." % [
				key, parser.get_error_line(), parser.get_error_message()
			],
			"location": str(read_res.get("location", "")),
			"colony_id": "",
			"summary": {},
			"migrated_from": 0,
			"saved_at_unix": 0,
		}
	var validated := SaveSchema.unwrap_and_validate(parser.data, blocked_map)
	if not validated["ok"]:
		return {
			"ok": false,
			"exists": true,
			"error_code": str(validated["error_code"]),
			"error": str(validated["error"]),
			"location": str(read_res.get("location", "")),
			"colony_id": "",
			"summary": {},
			"migrated_from": 0,
			"saved_at_unix": 0,
		}
	return {
		"ok": true,
		"exists": true,
		"error_code": "",
		"error": "",
		"location": str(read_res.get("location", "")),
		"colony_id": str(validated["colony_id"]),
		"summary": validated["summary"],
		"state": validated["state"],
		"migrated_from": int(validated["migrated_from"]),
		"saved_at_unix": int(validated["saved_at_unix"]),
	}


func save_simulation(slot_id: String, simulation: ColonySimulation,
		policy: OverwritePolicy = OverwritePolicy.SAME_COLONY_ONLY) -> Dictionary:
	var avail := backend.is_available()
	if not avail["ok"]:
		return {
			"ok": false,
			"slot_id": slot_id,
			"error_code": str(avail["error_code"]),
			"error": str(avail["error"]),
			"preserved": true,
		}

	var existing := inspect_slot(slot_id, false, simulation.blocked)
	var rotate_backup := false

	if bool(existing["exists"]):
		if existing["ok"]:
			var existing_colony := str(existing["colony_id"])
			if existing_colony != simulation.colony_id and policy == OverwritePolicy.SAME_COLONY_ONLY:
				var existing_day := int((existing["summary"] as Dictionary).get("day", 1))
				return {
					"ok": false,
					"slot_id": slot_id,
					"error_code": "colony_conflict",
					"error": "Slot '%s' holds another colony (Day %d). Confirm overwrite to replace it, or load it instead." % [
						slot_id, existing_day
					],
					"existing_colony_id": existing_colony,
					"existing_summary": existing["summary"],
					"preserved": true,
					"recommended_policy": OverwritePolicy.ALLOW_DIFFERENT_COLONY,
				}
			# Existing primary is valid: safe to rotate into .bak before replacing.
			rotate_backup = true
		else:
			var existing_code := str(existing["error_code"])
			if existing_code == "storage_unavailable" or existing_code == "io_error":
				return {
					"ok": false,
					"slot_id": slot_id,
					"error_code": existing_code,
					"error": str(existing["error"]),
					"preserved": true,
				}
			if policy != OverwritePolicy.ALLOW_ANY:
				var protected_code := (
					"unsupported_version_protected"
					if existing_code == "unsupported_version"
					else "corrupt_file_protected"
				)
				var bak := inspect_slot(slot_id, true, simulation.blocked)
				return {
					"ok": false,
					"slot_id": slot_id,
					"error_code": protected_code,
					"error": "Slot '%s' contains an unreadable or incompatible save (%s). Preserved untouched; confirm overwrite to replace it." % [
						slot_id, existing["error"]
					],
					"preserved": true,
					"backup_available": bool(bak["ok"]),
					"backup_summary": bak["summary"] if bak["ok"] else {},
					"recommended_policy": OverwritePolicy.ALLOW_ANY,
				}
			# Never overwrite a healthy backup with corrupt/unsupported bytes.
			rotate_backup = false

	var sim_state := simulation.export_state()
	var validated_out := SaveSchema.migrate_and_validate(sim_state, simulation.blocked)
	if not validated_out["ok"]:
		return {
			"ok": false,
			"slot_id": slot_id,
			"error_code": "invalid_schema",
			"error": "Refused to write invalid simulation state: %s" % validated_out["error"],
			"preserved": true,
		}

	var envelope := SaveSchema.wrap_envelope(sim_state, slot_id)
	var json_text := JSON.stringify(envelope, "\t")
	var write_res := backend.write_text_atomic(
		primary_key(slot_id), json_text, backup_key(slot_id), rotate_backup
	)
	if not write_res["ok"]:
		return {
			"ok": false,
			"slot_id": slot_id,
			"error_code": str(write_res["error_code"]),
			"error": str(write_res["error"]),
			"location": str(write_res.get("location", "")),
			"preserved": true,
		}
	return {
		"ok": true,
		"slot_id": slot_id,
		"colony_id": simulation.colony_id,
		"day": simulation.day,
		"location": str(write_res.get("location", "")),
		"error_code": "",
		"error": "",
	}


func load_into_simulation(slot_id: String, simulation: ColonySimulation,
		from_backup: bool = false) -> Dictionary:
	var inspected := inspect_slot(slot_id, from_backup, simulation.blocked)
	if not inspected["ok"]:
		var backup_available := false
		var backup_summary: Dictionary = {}
		if not from_backup:
			var bak := inspect_slot(slot_id, true, simulation.blocked)
			if bak["ok"]:
				backup_available = true
				backup_summary = bak["summary"]
		var err_msg := str(inspected["error"])
		if backup_available:
			err_msg += " A valid backup from Day %d is available to restore." % int(
				backup_summary.get("day", 1)
			)
		return {
			"ok": false,
			"slot_id": slot_id,
			"from_backup": from_backup,
			"error_code": str(inspected["error_code"]),
			"error": err_msg,
			"location": str(inspected.get("location", "")),
			"preserved": bool(inspected.get("exists", false)),
			"backup_available": backup_available,
			"backup_summary": backup_summary,
		}

	var apply_res := simulation.import_state_detailed(inspected["state"])
	if not apply_res["ok"]:
		return {
			"ok": false,
			"slot_id": slot_id,
			"from_backup": from_backup,
			"error_code": str(apply_res["error_code"]),
			"error": str(apply_res["error"]),
			"location": str(inspected.get("location", "")),
			"preserved": true,
			"backup_available": false,
			"backup_summary": {},
		}
	return {
		"ok": true,
		"slot_id": slot_id,
		"from_backup": from_backup,
		"colony_id": simulation.colony_id,
		"day": simulation.day,
		"migrated_from": int(inspected["migrated_from"]),
		"location": str(inspected.get("location", "")),
		"error_code": "",
		"error": "",
	}


func status_summary(blocked_map: Dictionary = {}) -> Dictionary:
	var avail := backend.is_available()
	var manual := inspect_slot(SLOT_MANUAL, false, blocked_map)
	var manual_bak := inspect_slot(SLOT_MANUAL, true, blocked_map)
	var auto_slot := inspect_slot(SLOT_AUTOSAVE, false, blocked_map)
	var auto_bak := inspect_slot(SLOT_AUTOSAVE, true, blocked_map)
	return {
		"backend": backend.backend_name(),
		"available": bool(avail["ok"]),
		"storage_error_code": str(avail["error_code"]),
		"storage_error": str(avail["error"]),
		"manual": manual,
		"manual_backup": manual_bak,
		"autosave": auto_slot,
		"autosave_backup": auto_bak,
	}
