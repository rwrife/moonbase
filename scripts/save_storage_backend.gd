class_name SaveStorageBackend
extends RefCounted

## Pluggable persistence backend for desktop files, Web localStorage, and tests.


static func create_default() -> SaveStorageBackend:
	if OS.has_feature("web"):
		return WebBackend.new()
	return FileBackend.new()


func backend_name() -> String:
	return "base"


func is_available() -> Dictionary:
	return {"ok": false, "error_code": "storage_unavailable", "error": "No storage backend configured."}


func key_exists(_key: String) -> bool:
	return false


func describe_location(key: String) -> String:
	return key


func read_text(_key: String) -> Dictionary:
	return {
		"ok": false,
		"exists": false,
		"text": "",
		"error_code": "storage_unavailable",
		"error": "No storage backend configured.",
		"location": "",
	}


func write_text_atomic(_key: String, _text: String, _backup_key: String,
		_rotate_backup: bool) -> Dictionary:
	return {
		"ok": false,
		"error_code": "storage_unavailable",
		"error": "No storage backend configured.",
		"location": "",
	}


## Desktop filesystem backend using atomic temporary writes and backup rotation.
class FileBackend extends SaveStorageBackend:
	var base_dir: String
	## Test fault hook: "", "storage_unavailable", "quota_exceeded",
	## "partial_tmp_write", "after_tmp_write", "before_rename".
	var simulate_fault := ""

	func _init(directory: String = "user://saves") -> void:
		base_dir = directory

	func backend_name() -> String:
		return "desktop_file"

	func _resolved_dir() -> String:
		if base_dir.begins_with("user://") or base_dir.begins_with("res://"):
			return ProjectSettings.globalize_path(base_dir)
		return base_dir

	func _path_for(key: String) -> String:
		return _resolved_dir().path_join(key)

	func describe_location(key: String) -> String:
		return _path_for(key)

	func is_available() -> Dictionary:
		if simulate_fault == "storage_unavailable":
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Save directory '%s' is unavailable or permission was denied." % _resolved_dir(),
			}
		var dir_path := _resolved_dir()
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Cannot access save directory '%s' (error %d)." % [dir_path, mk_err],
			}
		var probe_path := dir_path.path_join(".write_probe.tmp")
		var f := FileAccess.open(probe_path, FileAccess.WRITE)
		if f == null:
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Save directory '%s' is not writable (error %d)." % [
					dir_path, FileAccess.get_open_error()
				],
			}
		f.store_string("ok")
		f.flush()
		f.close()
		DirAccess.remove_absolute(probe_path)
		return {"ok": true, "error_code": "", "error": ""}

	func key_exists(key: String) -> bool:
		return FileAccess.file_exists(_path_for(key))

	func read_text(key: String) -> Dictionary:
		var path := _path_for(key)
		if simulate_fault == "storage_unavailable":
			return {
				"ok": false,
				"exists": false,
				"text": "",
				"error_code": "storage_unavailable",
				"error": "Storage access denied while reading '%s'." % path,
				"location": path,
			}
		if not FileAccess.file_exists(path):
			return {
				"ok": true,
				"exists": false,
				"text": "",
				"error_code": "",
				"error": "",
				"location": path,
			}
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {
				"ok": false,
				"exists": true,
				"text": "",
				"error_code": "storage_unavailable",
				"error": "Unable to open save file '%s' (error %d). File was preserved." % [
					path, FileAccess.get_open_error()
				],
				"location": path,
			}
		var text := f.get_as_text()
		var err := f.get_error()
		f.close()
		if err != OK and err != ERR_FILE_EOF:
			return {
				"ok": false,
				"exists": true,
				"text": "",
				"error_code": "io_error",
				"error": "Failed reading save file '%s' (error %d). File was preserved." % [path, err],
				"location": path,
			}
		return {
			"ok": true,
			"exists": true,
			"text": text,
			"error_code": "",
			"error": "",
			"location": path,
		}

	func write_text_atomic(key: String, text: String, backup_key: String,
			rotate_backup: bool) -> Dictionary:
		var dir_path := _resolved_dir()
		var primary_path := _path_for(key)
		var tmp_path := primary_path + ".tmp"
		var backup_path := _path_for(backup_key) if not backup_key.is_empty() else ""

		if simulate_fault == "storage_unavailable":
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Save directory '%s' is unavailable or read-only. Previous save was preserved." % dir_path,
				"location": primary_path,
			}
		if simulate_fault == "quota_exceeded":
			return {
				"ok": false,
				"error_code": "quota_exceeded",
				"error": "Disk space or storage quota exceeded while saving '%s'. Previous save was preserved." % primary_path,
				"location": primary_path,
			}

		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Could not create save directory '%s' (error %d)." % [dir_path, mk_err],
				"location": primary_path,
			}

		# Step 1: write full payload to temporary sibling file and flush.
		var expected_bytes := text.to_utf8_buffer()
		var f := FileAccess.open(tmp_path, FileAccess.WRITE)
		if f == null:
			var open_err := FileAccess.get_open_error()
			var code := "quota_exceeded" if open_err == ERR_OUT_OF_MEMORY else "storage_unavailable"
			return {
				"ok": false,
				"error_code": code,
				"error": "Could not open temporary save file '%s' (error %d). Previous save preserved." % [
					tmp_path, open_err
				],
				"location": primary_path,
			}

		if simulate_fault == "partial_tmp_write":
			# Simulate crash/power loss mid-write: truncated temp file, primary untouched.
			var partial := expected_bytes.slice(0, maxi(1, expected_bytes.size() / 4))
			f.store_buffer(partial)
			f.flush()
			f.close()
			return {
				"ok": false,
				"error_code": "interrupted_write",
				"error": "Save write was interrupted before completion. Previous save was preserved.",
				"location": primary_path,
			}

		f.store_buffer(expected_bytes)
		f.flush()
		var write_err := f.get_error()
		f.close()
		if write_err != OK:
			DirAccess.remove_absolute(tmp_path)
			return {
				"ok": false,
				"error_code": "io_error",
				"error": "Write failed for '%s' (error %d). Previous save was preserved." % [
					tmp_path, write_err
				],
				"location": primary_path,
			}

		# Verify temp file byte length before touching primary or backup.
		var verify := FileAccess.open(tmp_path, FileAccess.READ)
		var verified_len := verify.get_length() if verify != null else -1
		if verify != null:
			verify.close()
		if verified_len != expected_bytes.size():
			DirAccess.remove_absolute(tmp_path)
			return {
				"ok": false,
				"error_code": "interrupted_write",
				"error": "Temporary save verification failed (expected %d bytes, got %d). Previous save preserved." % [
					expected_bytes.size(), verified_len
				],
				"location": primary_path,
			}

		if simulate_fault == "after_tmp_write":
			# Temp file is complete on disk, but commit never happened; primary untouched.
			return {
				"ok": false,
				"error_code": "interrupted_write",
				"error": "Save was interrupted before committing temp file. Previous save was preserved.",
				"location": primary_path,
			}

		# Step 2: atomically rotate valid existing primary -> backup before replacing primary.
		if rotate_backup and not backup_path.is_empty() and FileAccess.file_exists(primary_path):
			var existing := FileAccess.open(primary_path, FileAccess.READ)
			if existing != null:
				var prev_bytes := existing.get_buffer(existing.get_length())
				existing.close()
				var bak_tmp := backup_path + ".tmp"
				var bf := FileAccess.open(bak_tmp, FileAccess.WRITE)
				if bf != null:
					bf.store_buffer(prev_bytes)
					bf.flush()
					var b_err := bf.get_error()
					bf.close()
					if b_err == OK:
						var bak_rename := _replace_file(bak_tmp, backup_path)
						if bak_rename != OK:
							DirAccess.remove_absolute(bak_tmp)
					else:
						DirAccess.remove_absolute(bak_tmp)

		if simulate_fault == "before_rename":
			# Backup rotated, temp written, interrupted immediately before final rename.
			return {
				"ok": false,
				"error_code": "interrupted_write",
				"error": "Save was interrupted immediately before commit. Previous save was preserved.",
				"location": primary_path,
			}

		# Step 3: atomically promote temp file -> primary.
		var rename_err := _replace_file(tmp_path, primary_path)
		if rename_err != OK:
			return {
				"ok": false,
				"error_code": "io_error",
				"error": "Failed to commit save file '%s' (error %d). Previous save or backup preserved." % [
					primary_path, rename_err
				],
				"location": primary_path,
			}
		return {"ok": true, "error_code": "", "error": "", "location": primary_path}

	static func _replace_file(src_path: String, dst_path: String) -> Error:
		var err := DirAccess.rename_absolute(src_path, dst_path)
		if err == OK:
			return OK
		# Windows fallback if destination already exists (backup was already written above).
		if FileAccess.file_exists(dst_path):
			var rm_err := DirAccess.remove_absolute(dst_path)
			if rm_err != OK:
				return rm_err
			return DirAccess.rename_absolute(src_path, dst_path)
		return err


## Web localStorage backend via JavaScriptBridge with explicit quota/availability handling.
class WebBackend extends SaveStorageBackend:
	const KEY_PREFIX := "selene_frontier_save:"
	var _bridge_ready := false

	func backend_name() -> String:
		return "web_local_storage"

	func describe_location(key: String) -> String:
		return "localStorage[%s%s]" % [KEY_PREFIX, key]

	func _ensure_bridge() -> bool:
		if not OS.has_feature("web"):
			return false
		if _bridge_ready:
			return true
		var install_js := """
		(function() {
			if (window.__seleneStorage) return true;
			function classifyError(err) {
				var name = err && err.name ? String(err.name) : "";
				var code = err && typeof err.code === "number" ? err.code : 0;
				if (name === "QuotaExceededError" || name === "NS_ERROR_DOM_QUOTA_REACHED" || code === 22 || code === 1014) {
					return "quota_exceeded";
				}
				return "storage_unavailable";
			}
			window.__seleneStorage = {
				probe: function() {
					try {
						var s = window.localStorage;
						if (!s) return JSON.stringify({ok: false, error_code: "storage_unavailable", error: "Browser localStorage is unavailable."});
						var k = "__selene_frontier_probe__";
						s.setItem(k, "1");
						s.removeItem(k);
						return JSON.stringify({ok: true, error_code: "", error: ""});
					} catch (e) {
						var c = classifyError(e);
						return JSON.stringify({
							ok: false,
							error_code: c,
							error: c === "quota_exceeded"
								? "Browser storage quota is full. Free site data or clear old saves."
								: "Browser storage is disabled or blocked (private browsing or site settings)."
						});
					}
				},
				exists: function(key) {
					try {
						return window.localStorage && window.localStorage.getItem(key) !== null;
					} catch (e) {
						return false;
					}
				},
				read: function(key) {
					try {
						var s = window.localStorage;
						if (!s) return JSON.stringify({ok: false, exists: false, text: "", error_code: "storage_unavailable", error: "Browser localStorage is unavailable."});
						var val = s.getItem(key);
						if (val === null) return JSON.stringify({ok: true, exists: false, text: "", error_code: "", error: ""});
						return JSON.stringify({ok: true, exists: true, text: String(val), error_code: "", error: ""});
					} catch (e) {
						return JSON.stringify({
							ok: false, exists: false, text: "",
							error_code: "storage_unavailable",
							error: "Browser denied read access to persistent storage."
						});
					}
				},
				writeAtomic: function(key, text, backupKey, rotateBackup) {
					try {
						var s = window.localStorage;
						if (!s) return JSON.stringify({ok: false, error_code: "storage_unavailable", error: "Browser localStorage is unavailable."});
						if (rotateBackup && backupKey) {
							var prev = s.getItem(key);
							if (prev !== null) {
								s.setItem(backupKey, prev);
							}
						}
						s.setItem(key, text);
						return JSON.stringify({ok: true, error_code: "", error: ""});
					} catch (e) {
						var c = classifyError(e);
						return JSON.stringify({
							ok: false,
							error_code: c,
							error: c === "quota_exceeded"
								? "Browser storage quota exceeded. Previous save was preserved."
								: "Browser storage is unavailable or blocked. Previous save was preserved."
						});
					}
				}
			};
			return true;
		})();
		"""
		JavaScriptBridge.eval(install_js, true)
		_bridge_ready = true
		return true

	func _parse_bridge_dict(raw: Variant) -> Dictionary:
		if not (raw is String):
			return {"ok": false, "error_code": "storage_unavailable", "error": "Web storage bridge returned invalid result."}
		var parsed: Variant = JSON.parse_string(str(raw))
		if parsed is Dictionary:
			return parsed
		return {"ok": false, "error_code": "storage_unavailable", "error": "Web storage bridge JSON parse failed."}

	func is_available() -> Dictionary:
		if not _ensure_bridge():
			return {"ok": false, "error_code": "storage_unavailable", "error": "Web storage is only available in browser builds."}
		return _parse_bridge_dict(JavaScriptBridge.eval("window.__seleneStorage.probe()", true))

	func key_exists(key: String) -> bool:
		if not _ensure_bridge():
			return false
		var full_key := KEY_PREFIX + key
		var res: Variant = JavaScriptBridge.eval(
			"window.__seleneStorage.exists(%s)" % JSON.stringify(full_key), true
		)
		return bool(res)

	func read_text(key: String) -> Dictionary:
		var loc := describe_location(key)
		if not _ensure_bridge():
			return {
				"ok": false, "exists": false, "text": "",
				"error_code": "storage_unavailable",
				"error": "Web storage is only available in browser builds.",
				"location": loc,
			}
		var full_key := KEY_PREFIX + key
		var res := _parse_bridge_dict(JavaScriptBridge.eval(
			"window.__seleneStorage.read(%s)" % JSON.stringify(full_key), true
		))
		res["location"] = loc
		return res

	func write_text_atomic(key: String, text: String, backup_key: String,
			rotate_backup: bool) -> Dictionary:
		var loc := describe_location(key)
		if not _ensure_bridge():
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Web storage is only available in browser builds.",
				"location": loc,
			}
		var full_key := KEY_PREFIX + key
		var full_bak := (KEY_PREFIX + backup_key) if not backup_key.is_empty() else ""
		var expr := "window.__seleneStorage.writeAtomic(%s, %s, %s, %s)" % [
			JSON.stringify(full_key),
			JSON.stringify(text),
			JSON.stringify(full_bak),
			"true" if rotate_backup else "false",
		]
		var res := _parse_bridge_dict(JavaScriptBridge.eval(expr, true))
		res["location"] = loc
		return res


## Deterministic in-memory backend with configurable fault injection for headless tests.
class MemoryBackend extends SaveStorageBackend:
	var store: Dictionary = {}
	var available := true
	var quota_bytes := -1
	var fail_next_write_code := ""
	var write_count := 0

	func backend_name() -> String:
		return "memory_test"

	func is_available() -> Dictionary:
		if not available:
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Persistent storage is unavailable or blocked.",
			}
		return {"ok": true, "error_code": "", "error": ""}

	func key_exists(key: String) -> bool:
		return available and store.has(key)

	func describe_location(key: String) -> String:
		return "memory://" + key

	func read_text(key: String) -> Dictionary:
		var loc := describe_location(key)
		if not available:
			return {
				"ok": false, "exists": false, "text": "",
				"error_code": "storage_unavailable",
				"error": "Persistent storage is unavailable or blocked.",
				"location": loc,
			}
		if not store.has(key):
			return {
				"ok": true, "exists": false, "text": "",
				"error_code": "", "error": "",
				"location": loc,
			}
		return {
			"ok": true, "exists": true, "text": str(store[key]),
			"error_code": "", "error": "",
			"location": loc,
		}

	func _total_bytes(pending_store: Dictionary) -> int:
		var total := 0
		for k in pending_store:
			total += str(pending_store[k]).to_utf8_buffer().size()
		return total

	func write_text_atomic(key: String, text: String, backup_key: String,
			rotate_backup: bool) -> Dictionary:
		var loc := describe_location(key)
		if not available:
			return {
				"ok": false,
				"error_code": "storage_unavailable",
				"error": "Persistent storage is unavailable or blocked. Previous save was preserved.",
				"location": loc,
			}
		if not fail_next_write_code.is_empty():
			var code := fail_next_write_code
			fail_next_write_code = ""
			return {
				"ok": false,
				"error_code": code,
				"error": "Simulated '%s' failure during write. Previous save was preserved." % code,
				"location": loc,
			}
		var candidate := store.duplicate()
		if rotate_backup and not backup_key.is_empty() and store.has(key):
			candidate[backup_key] = store[key]
		candidate[key] = text
		if quota_bytes >= 0 and _total_bytes(candidate) > quota_bytes:
			return {
				"ok": false,
				"error_code": "quota_exceeded",
				"error": "Storage quota (%d bytes) exceeded. Previous save was preserved." % quota_bytes,
				"location": loc,
			}
		store = candidate
		write_count += 1
		return {"ok": true, "error_code": "", "error": "", "location": loc}
