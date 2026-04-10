/// @description Begin Step - poll MIDI as early as possible each frame

timing_sample_begin_step_now_ms();
var _midi_t0_us = get_timer();
MIDI_process_messages();
tune_rt_budget_diag_record_midi_step_ms((get_timer() - _midi_t0_us) / 1000);
