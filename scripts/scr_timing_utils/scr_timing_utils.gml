// scr_timing_utils — Shared timing helpers

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
    if (ts == "2/2") return bpm * 2;

    return bpm;
}