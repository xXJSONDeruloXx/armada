extends RefCounted

const DEFAULT_CALL := "/usr/libexec/armada/armada-overlay-call"

var last_error := ""


func call_action(action: String, fields: Dictionary = {}) -> Dictionary:
    var executable := OS.get_environment("ARMADA_OVERLAY_CALL")
    if executable.is_empty():
        executable = DEFAULT_CALL

    var output: Array = []
    var exit_code := OS.execute(executable, [action, JSON.stringify(fields)], output, true)
    if exit_code != OK:
        last_error = "Armada service is unavailable"
        return {"ok": false, "error": last_error}
    if output.is_empty():
        last_error = "Armada service returned no response"
        return {"ok": false, "error": last_error}

    var response = JSON.parse_string(String(output[0]))
    if not response is Dictionary:
        last_error = "Invalid Armada service response"
        return {"ok": false, "error": last_error}
    if not response.get("ok", false):
        last_error = String(response.get("error", "Armada service request failed"))
    return response
