/// @description Async Audio Recording handler for external loopback calibration.

var _handler_idx = asset_get_index("timing_calibration_on_audio_recording_async");
if (script_exists(_handler_idx)) {
    script_execute(_handler_idx, async_load);
}
