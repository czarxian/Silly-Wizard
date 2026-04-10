/// @description Insert description here
// You can write your code in this editor

show_debug_message("[TIMELINE] obj_game_viz Create initialized");
global.timeline_cfg_debug_gui = false;

// Timeline config
global.timeline_cfg = {
    enabled: true,
    now_ratio: 0.33,            // 1/3 from left
    measures_ahead: 2.0,        // planned
    measures_behind: 1.0,       // played
    show_countin: true,
    tune_channel: 2,
    tune_show_other_parts_ghost: true,
    tune_other_parts_alpha: 0.18,
    // Player MIDI input channels to visualize in tune canvas + notebeam.
    // Keep as array so channel 1 can be enabled later with [0, 1].
    player_channels: [0],
    player_channel: -1,         // -1 = accept all incoming channels
    playhead_audio_lag_ms: 0,  // Delay visual playhead to better match audible MIDI output latency
    player_time_offset_ms: 0,
    filter_noise_ms: 15,
    core_min_ms: 100,
    padding_px: 8,
    row_gap_px: 26,
    canvas_bg_color: make_color_rgb(16, 16, 16),
    canvas_bg_alpha: 0.97,
    row_bg_tune_color: make_color_rgb(34, 34, 34),
    row_bg_player_color: make_color_rgb(30, 30, 30),
    row_bg_structure_color: make_color_rgb(26, 26, 26),
    row_bg_alpha: 1.0,
    show_beat_guides: true,
    beat_guide_major_color: make_color_rgb(92, 92, 92),
    beat_guide_minor_color: make_color_rgb(58, 58, 58),
    beat_guide_major_alpha: 0.28,
    beat_guide_minor_alpha: 0.16,
    beat_guide_major_width: 1,
    beat_guide_minor_width: 1,
    show_structure_row: true,
    structure_row_height_px: 18,
    structure_major_color: c_ltgray,
    structure_minor_color: c_gray,
    structure_text_color: c_white,
    structure_label_every_beat: true,
    structure_label_spacing_px: 26,
    planned_bar_color: make_color_rgb(86, 86, 92),
    planned_bar_alpha: 0.94,
    planned_melody_text_color: c_white,
    planned_embellishment_text_color: c_green,
    planned_note_text_scale: 1.15,
    planned_label_min_px: 4,
    planned_label_full_px: 12,
    player_bar_color: make_color_rgb(78, 78, 84),
    player_pending_bar_color: make_color_rgb(92, 92, 98),
    player_bar_alpha: 0.84,
    player_melody_text_color: c_white,
    player_short_text_color: c_green,
    player_note_text_scale: 1.10,
    player_label_min_px: 12,
    tune_structure_current_base_color: make_color_rgb(104, 100, 76),
    tune_structure_current_base_alpha: 0.55,
    tune_structure_current_overlay_color: make_color_rgb(224, 206, 92),
    tune_structure_current_overlay_alpha: 0.35,
    tune_structure_played_fill_color: make_color_rgb(112, 112, 112),
    tune_structure_played_fill_alpha: 0.82,
    tune_structure_border_color: make_color_rgb(84, 121, 112),
    tune_structure_border_alpha: 0.88,
    tune_structure_current_border_color: make_color_rgb(255, 230, 96),
    tune_structure_current_border_alpha: 1.00,
    tune_structure_part_separator_color: make_color_rgb(200, 202, 220),
    tune_structure_part_separator_alpha: 0.50,
    tune_structure_auto_follow_interval_ms: 90,
    tune_structure_auto_follow_max_rows_per_step: 1,
    notebeam_enabled: true,
    notebeam_draw_from_timeline: false,
    notebeam_show_now_line: true,
    notebeam_now_ratio: -1,
    notebeam_now_x_offset_px: 0,
    notebeam_now_line_color: c_yellow,
    notebeam_now_line_width: 2,
    notebeam_line_width: 42,
    notebeam_use_lane_anchors: true,
    notebeam_use_label_layout: true,
    notebeam_match_label_width: true,
    notebeam_match_label_width_scale: 0.8,
    notebeam_lane_flip: false,
    notebeam_lane_top_spacer_ratio: 0.10,
    notebeam_lane_top_spacer_px: 0,
    notebeam_lane_row_height_px: 42,
    notebeam_lane_row_gap_px: 20,
    notebeam_lane_y_offset_px: 0,
    notebeam_planned_color: make_color_rgb(132, 168, 196),
    notebeam_planned_alpha: 0.94,
    notebeam_player_color: make_color_rgb(190, 190, 196),
    notebeam_compare_version: 2,
    notebeam_player_overlap_colorize: true,
    notebeam_player_match_color: make_color_rgb(138, 118, 44),
    notebeam_player_emb_match_color: make_color_rgb(60, 155, 70),
    notebeam_player_segment_match_color: make_color_rgb(60, 155, 70),
    notebeam_player_emb_overlay_alpha: 0.55,
    notebeam_player_miss_color: make_color_rgb(112, 46, 46),
    notebeam_player_timing_slack_ms: 50,
    notebeam_player_bleed_alpha: 0.38,
    notebeam_player_alpha: 0.88,
    notebeam_review_split_beams: false,
    notebeam_history_enabled: true,
    notebeam_history_use_gap_band: true,
    notebeam_history_run_count: 10,
    notebeam_history_require_same_bpm: true,
    notebeam_history_require_same_swing: true,
    notebeam_history_start_color: make_color_rgb(255, 248, 153),
    notebeam_history_end_color: make_color_rgb(255, 248, 153),
    notebeam_history_band_color: make_color_rgb(220, 220, 220),
    notebeam_history_band_alpha: 0.20,
    notebeam_history_start_alpha: 1.0,
    notebeam_history_end_alpha: 1.0,
        notebeam_postplay_overlay_mode: 0,
        notebeam_debug_log: false,
    notebeam_show_debug_outline: false,
    notebeam_debug_outline_color: make_color_rgb(80, 80, 88),
    notebeam_debug_outline_alpha: 0.65,
    notebeam_beat_box_even_color: make_color_rgb(245, 245, 245),
    notebeam_beat_box_odd_color: make_color_rgb(35, 35, 35),
    notebeam_beat_box_even_alpha: 0.06,
    notebeam_beat_box_odd_alpha: 0.14,
    notebeam_emb_box_enabled: true,
    notebeam_emb_box_review_only: true,
    notebeam_emb_box_fill_color: make_color_rgb(60, 155, 70),
    notebeam_emb_box_fill_alpha: 0.24,
    notebeam_emb_box_border_color: make_color_rgb(60, 155, 70),
    notebeam_emb_box_border_alpha: 1.0,
    notebeam_emb_box_lane_padding_px: 3,
    notebeam_emb_box_time_padding_ms: 0,
    notebeam_planned_min_visible_px: 1.0,
    notebeam_planned_view_pad_px: 0.5,
    notebeam_visual_throttle_enabled: true,
    notebeam_visual_target_hz: 90,
    notebeam_underlay_cache_enabled: true,
    notebeam_underlay_invalidation_ms: 33,
    // Temporary notebeam jitter diagnostics (all off by default)
    notebeam_diag_enabled: true,
    notebeam_diag_log_interval_frames: 45,
    notebeam_diag_disable_planned: false,
    notebeam_diag_disable_player: false,
    notebeam_diag_disable_pending: false,
    notebeam_diag_disable_history: false,
    notebeam_diag_disable_beat_boxes: false,
    notebeam_diag_disable_emb_boxes: false,
    notebeam_diag_disable_popup_hitboxes: false,
    notebeam_diag_disable_popup_draw: false,
    notebeam_diag_disable_overlap_compare: false,
    debug_planned_sequence: false,
    debug_sequence_max_notes: 24
};

// MIDI timing diagnostics (consumed by scr_MIDI)
global.MIDI_TIMING_DIAG_ENABLED = true;
global.MIDI_TIMING_DIAG_LOG_INTERVAL_MS = 1000;

// Realtime timing budget diagnostics (scheduler + visual alignment)
global.RT_BUDGET_DIAG_ENABLED = true;
global.RT_BUDGET_DIAG_LOG_INTERVAL_MS = 1000;
global.RT_BUDGET_SCHED_WARMUP_MS = 1000;
global.RT_BUDGET_DIAG_INCLUDE_VISUAL_ALIGN = true;
global.RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME = true;
global.RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL = true;
global.PLAYBACK_DEBUG_GROUP_TIMING = true;
if (!variable_global_exists("DIAG_DISABLE_TIMELINE_DRAW")) {
    global.DIAG_DISABLE_TIMELINE_DRAW = false;
}
if (!variable_global_exists("DIAG_DISABLE_TIMELINE_ANCHOR")) {
    // Diagnostic toggle: disable only timeline anchor rendering to isolate
    // its impact on scheduler/step jitter without disabling notebeam/panels.
    global.DIAG_DISABLE_TIMELINE_ANCHOR = false;
}
if (!variable_global_exists("TIMELINE_HIDE_DURING_PLAY")) {
    // Production mode: hide timeline placeholder while live playback is running,
    // and restore it automatically in review mode.
    global.TIMELINE_HIDE_DURING_PLAY = true;
}
if (!variable_global_exists("GV_VISUAL_CACHE_ENABLED")) {
    global.GV_VISUAL_CACHE_ENABLED = true;
}
if (!variable_global_exists("GV_VISUAL_CACHE_REFRESH_MS")) {
    global.GV_VISUAL_CACHE_REFRESH_MS = 11;
}
if (!variable_global_exists("GV_TUNESTRUCTURE_PLAY_REFRESH_MS")) {
    global.GV_TUNESTRUCTURE_PLAY_REFRESH_MS = 48;
}
if (!variable_global_exists("GV_ANCHOR_RENDER_ONLY")) {
    global.GV_ANCHOR_RENDER_ONLY = true;
}
if (!variable_global_exists("NOTEBEAM_OVERLAY_NOWLINE_ENABLED")) {
    global.NOTEBEAM_OVERLAY_NOWLINE_ENABLED = true;
}

// Compact diagnostics mode: keep scheduler-focused telemetry only.
if (!variable_global_exists("DIAG_SCHEDULER_FOCUS_MODE")) {
    global.DIAG_SCHEDULER_FOCUS_MODE = true;
}
if (global.DIAG_SCHEDULER_FOCUS_MODE) {
    global.timeline_cfg.notebeam_diag_enabled = false;
    global.MIDI_TIMING_DIAG_ENABLED = false;
    global.RT_BUDGET_DIAG_INCLUDE_VISUAL_ALIGN = false;
    global.RT_BUDGET_DIAG_INCLUDE_STEP_RUNTIME = false;
    global.RT_BUDGET_DIAG_INCLUDE_STEP_INTERVAL = true;
    global.PLAYBACK_DEBUG_GROUP_TIMING = false;
}

if (!variable_global_exists("timeline_anchor_surface_cache") || !is_struct(global.timeline_anchor_surface_cache)) {
    global.timeline_anchor_surface_cache = {};
}

// Surface cache for player notebeam rendering
// Invalidate cache when playhead moves or spans change; blit cached surface each frame
global.player_surface_cache = noone;
global.player_surface_cache_valid = false;
global.player_surface_cache_last_playhead_ms = -9999;
global.player_surface_cache_invalidation_threshold_ms = 200;  // Invalidate if playhead moves >200ms

// Live notebeam player beam cache (heavy draw path in scr_game_viz)
global.notebeam_live_player_surface = noone;
global.notebeam_live_player_surface_valid = false;
global.notebeam_live_player_surface_last_playhead_ms = -9999;
global.notebeam_live_player_surface_last_span_count = -1;
global.notebeam_live_player_surface_invalidation_threshold_ms = 16;

global.notebeam_underlay_surface = noone;
global.notebeam_underlay_surface_valid = false;
global.notebeam_underlay_surface_last_playhead_ms = -9999;
global.notebeam_underlay_surface_signature = "";

if (!variable_global_exists("selected_player_tune_channel")) {
    global.selected_player_tune_channel = global.timeline_cfg.tune_channel;
}

global.enable_current_note_layer = false;

// Timeline runtime state
global.timeline_state = {
    active: false,
    playhead_ms: 0,
    start_clock_ms: current_time,
    bpm: 0,
    meter_num: 4,
    meter_den: 4,
    measure_ms: 0,
    ms_ahead: 0,
    ms_behind: 0,

    // Source + overlays
    planned_events: [],         // reference to preprocessed tune events
    planned_spans: [],          // precomputed note spans for draw
    tune_played: [],            // append-only during playback
    player_in: [],              // append-only during playback

    // Optional pending for note_on/off pairing
    pending_tune: {},
    pending_player: {},

    // Cached visible ranges (indexes)
    planned_i0: 0,
    planned_i1: -1,
    planned_span_i0: 0,
    planned_span_i1: -1,

    // Tune-structure panel state
    measure_nav_entries: [],
    measure_nav_parts: [],
    measure_nav_pickup_by_part: [],
    measure_nav_tile_hitboxes: [],
    measure_nav_scroll_row: 0,
    measure_nav_total_rows: 0,
    measure_nav_view_rows: 0,
    measure_nav_controls: {},

    anchor_id: noone
};