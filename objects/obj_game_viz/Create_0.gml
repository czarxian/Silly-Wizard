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
    planned_bar_alpha: 0.82,
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
    notebeam_enabled: true,
    notebeam_draw_from_timeline: true,
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
    notebeam_planned_alpha: 0.75,
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
    notebeam_debug_log: true,
    notebeam_show_debug_outline: false,
    notebeam_debug_outline_color: make_color_rgb(80, 80, 88),
    notebeam_debug_outline_alpha: 0.65,
    debug_planned_sequence: false,
    debug_sequence_max_notes: 24
};

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
    anchor_id: noone
};