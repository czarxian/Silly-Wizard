/// @description Begin Step - poll MIDI as early as possible each frame

timing_sample_begin_step_now_ms();
var _midi_t0_us = get_timer();
MIDI_process_messages();
if (!variable_instance_exists(id, "_cal_step_idx")) {
	_cal_step_idx = asset_get_index("timing_calibration_step_midi_loopback");
	_cal_step_has = script_exists(_cal_step_idx);
	_cal_ext_step_idx = asset_get_index("timing_calibration_step_external_audio_loopback");
	_cal_ext_step_has = script_exists(_cal_ext_step_idx);
	_cal_preview_step_idx = asset_get_index("timing_calibration_step_preview_click");
	_cal_preview_step_has = script_exists(_cal_preview_step_idx);
}

if (_cal_step_has) {
	script_execute(_cal_step_idx);
}
if (_cal_ext_step_has) {
	script_execute(_cal_ext_step_idx);
}
if (_cal_preview_step_has) {
	script_execute(_cal_preview_step_idx);
}
tune_rt_budget_diag_record_midi_step_ms((get_timer() - _midi_t0_us) / 1000);
