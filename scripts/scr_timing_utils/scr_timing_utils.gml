// scr_timing_utils — Shared timing helpers

/// @function timing_sample_begin_step_now_ms()
/// @description Capture one authoritative engine timestamp for this frame in Begin Step.
/// @returns Real timestamp in milliseconds
function timing_sample_begin_step_now_ms() {
    var now_ms = current_time;
    global.ENGINE_STEP_NOW_MS = now_ms;
    return now_ms;
}

/// @function timing_get_engine_now_ms()
/// @description Read the shared engine timestamp captured in Begin Step.
/// Falls back to current_time when Begin Step sampling is not available.
/// @returns Real timestamp in milliseconds
function timing_get_engine_now_ms() {
    if (variable_global_exists("ENGINE_STEP_NOW_MS")) {
        return real(global.ENGINE_STEP_NOW_MS);
    }
    return current_time;
}

function timing_normalize_time_sig(_time_sig) {
    var ts = string(_time_sig ?? "");
    ts = string_trim(ts);
    if (ts == "") return "4/4";
    if (ts == "C") return "4/4";
    if (ts == "C|") return "2/2";
    if (string_pos("/", ts) == 0) return "4/4";
    return ts;
}

function timing_get_effective_quarter_bpm(_bpm, _time_sig) {
    var bpm = real(_bpm);
    if (bpm <= 0) bpm = 120;

    var ts = timing_normalize_time_sig(_time_sig);

    // Cut time: displayed BPM is commonly half-note BPM.
    if (ts == "2/2") return bpm * 2;

    // Compound meters (x/8, x/16 where x is multiple of 3 and > 3):
    // interpret displayed BPM as dotted-beat BPM by default.
    // Convert to quarter-note BPM using:
    // quarter_per_beat = (3/denom) / (1/4) = 12/denom
    // effective_quarter_bpm = bpm * (12 / denom)
    var parts = string_split(ts, "/");
    if (array_length(parts) >= 2) {
        var num = real(parts[0]);
        var den = real(parts[1]);
        if (num > 3 && (num mod 3) == 0 && (den == 8 || den == 16)) {
            return bpm * (12 / den);
        }
    }

    return bpm;
}