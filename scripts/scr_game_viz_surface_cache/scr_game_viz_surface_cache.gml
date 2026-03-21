// Surface cache for player notebeam rendering - reduces per-frame GML draw overhead
// Strategy: render all visible player spans to off-screen surface, blit each frame
// Cache invalidates when playhead moves significantly or spans change

function gv_invalidate_player_surface_cache() {
    if (variable_global_exists("player_surface_cache") && surface_exists(global.player_surface_cache)) {
        surface_free(global.player_surface_cache);
    }
    global.player_surface_cache = noone;
    global.player_surface_cache_valid = false;
}

function gv_ensure_player_surface_cache(_width, _height) {
    // Safely create or recreate surface if size changed
    if (surface_exists(global.player_surface_cache)) {
        var surf_w = surface_get_width(global.player_surface_cache);
        var surf_h = surface_get_height(global.player_surface_cache);
        if (surf_w == _width && surf_h == _height) {
            return global.player_surface_cache;
        }
        surface_free(global.player_surface_cache);
    }
    
    global.player_surface_cache = surface_create(_width, _height);
    return global.player_surface_cache;
}

function gv_draw_player_row_to_surface(_surface, _surf_width, _surf_height, _rx1, _ry1, _rx2, _ry2, _playhead_ms) {
    // Render all player spans to cached surface (replaces gv_draw_player_row inner loop logic)
    if (!surface_exists(_surface)) return;
    
    surface_set_target(_surface);
    draw_clear_alpha(c_black, 0);
    
    if (!variable_global_exists("timeline_state") || !is_struct(global.timeline_state)) {
        surface_reset_target();
        return;
    }
    
    var cfg = gv_ensure_timeline_cfg_defaults();
    var t_min = _playhead_ms - global.timeline_state.ms_behind;
    var t_max = _playhead_ms + global.timeline_state.ms_ahead;
    
    var now_ratio = variable_struct_exists(cfg, "now_ratio") ? real(cfg.now_ratio) : 0.33;
    now_ratio = clamp(now_ratio, 0.05, 0.95);
    var ms_behind = global.timeline_state.ms_behind;
    var ms_ahead = global.timeline_state.ms_ahead;
    var player_offset_ms = variable_struct_exists(global.timeline_cfg, "player_time_offset_ms")
        ? real(global.timeline_cfg.player_time_offset_ms)
        : 0;
    var player_bar_color = variable_struct_exists(global.timeline_cfg, "player_bar_color")
        ? global.timeline_cfg.player_bar_color
        : make_color_rgb(78, 78, 84);
    var player_pending_bar_color = variable_struct_exists(global.timeline_cfg, "player_pending_bar_color")
        ? global.timeline_cfg.player_pending_bar_color
        : make_color_rgb(92, 92, 98);
    var player_bar_alpha = variable_struct_exists(global.timeline_cfg, "player_bar_alpha")
        ? clamp(real(global.timeline_cfg.player_bar_alpha), 0, 1)
        : 0.84;
    var note_text_scale = variable_struct_exists(global.timeline_cfg, "player_note_text_scale")
        ? max(0.5, real(global.timeline_cfg.player_note_text_scale))
        : 1.10;
    var label_min_px = variable_struct_exists(global.timeline_cfg, "player_label_min_px")
        ? max(1, real(global.timeline_cfg.player_label_min_px))
        : 12;
    var core_min_ms = variable_struct_exists(global.timeline_cfg, "core_min_ms")
        ? max(0, real(global.timeline_cfg.core_min_ms))
        : 100;
    var player_melody_text_color = variable_struct_exists(global.timeline_cfg, "player_melody_text_color")
        ? global.timeline_cfg.player_melody_text_color
        : c_white;
    var player_short_text_color = variable_struct_exists(global.timeline_cfg, "player_short_text_color")
        ? global.timeline_cfg.player_short_text_color
        : c_green;
    
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    
    // Draw completed player spans
    var spans = variable_struct_exists(global.timeline_state, "player_in") ? global.timeline_state.player_in : [];
    if (is_array(spans)) {
        var n = array_length(spans);
        for (var i = 0; i < n; i++) {
            var s = spans[i];
            if (!is_struct(s)) continue;
            if (!gv_player_channel_matches(real(s.channel ?? 0))) continue;
            
            var s_start = real(s.start_ms ?? 0) + player_offset_ms;
            var s_end = real(s.end_ms ?? s_start) + player_offset_ms;
            
            if (s_end < t_min) continue;
            if (s_start > t_max) continue;
            
            var x1 = gv_time_to_x(s_start, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            var x2 = gv_time_to_x(s_end, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            if (x2 < _rx1 || x1 > _rx2) continue;
            
            var lx = clamp(min(x1, x2), _rx1, _rx2);
            var rx = clamp(max(x1, x2), _rx1, _rx2);
            
            draw_set_alpha(player_bar_alpha);
            draw_set_color(player_bar_color);
            draw_rectangle(lx, _ry1, max(lx + 2, rx), _ry2, false);
            draw_set_alpha(1);
            
            if (rx - lx >= label_min_px) {
                var label = variable_struct_exists(s, "note_letter")
                    ? string(s.note_letter)
                    : "";
                if ((label == "?" || string_length(label) <= 0) && variable_struct_exists(s, "note_canonical")) {
                    label = chanter_canonical_to_display(string(s.note_canonical));
                }
                if (label == "?" || string_length(label) <= 0) {
                    label = midi_to_letter(real(s.note_midi ?? 0), real(s.channel ?? -1));
                }
                if (label == "?" || string_length(label) <= 0) {
                    label = gv_note_label_from_midi(real(s.note_midi ?? 0));
                }
                var span_duration_ms = variable_struct_exists(s, "dur_ms")
                    ? real(s.dur_ms)
                    : max(0, s_end - s_start);
                var is_short = (span_duration_ms < core_min_ms);
                var text_h = string_height(label) * note_text_scale;
                var row_mid = (_ry1 + _ry2) * 0.5;
                var text_y = is_short ? (row_mid + 1) : (_ry1 + 1);
                text_y = clamp(text_y, _ry1 + 1, max(_ry1 + 1, _ry2 - text_h - 1));
                
                draw_set_color(is_short ? player_short_text_color : player_melody_text_color);
                draw_text_transformed(lx + 2, text_y, label, note_text_scale, note_text_scale, 0);
            }
        }
    }
    
    // Draw pending (currently-held) spans
    if (variable_struct_exists(global.timeline_state, "pending_player") && is_struct(global.timeline_state.pending_player)) {
        var names = variable_struct_get_names(global.timeline_state.pending_player);
        for (var ni = 0; ni < array_length(names); ni++) {
            var key = names[ni];
            var p = global.timeline_state.pending_player[$ key];
            if (is_undefined(p) || !is_struct(p)) continue;
            if (!gv_player_channel_matches(real(p.channel ?? 0))) continue;
            
            var start_ms = real(p.start_ms ?? _playhead_ms) + player_offset_ms;
            var end_ms = max(start_ms, _playhead_ms + player_offset_ms);
            if (end_ms < t_min || start_ms > t_max) continue;
            
            var px1 = gv_time_to_x(start_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            var px2 = gv_time_to_x(end_ms, _playhead_ms, _rx1, _rx2, now_ratio, ms_behind, ms_ahead);
            if (px2 < _rx1 || px1 > _rx2) continue;
            
            var plx = clamp(min(px1, px2), _rx1, _rx2);
            var prx = clamp(max(px1, px2), _rx1, _rx2);
            
            draw_set_alpha(player_bar_alpha);
            draw_set_color(player_pending_bar_color);
            draw_rectangle(plx, _ry1, max(plx + 2, prx), _ry2, false);
            draw_set_alpha(1);
            
            if (prx - plx >= label_min_px) {
                var p_label = variable_struct_exists(p, "note_letter")
                    ? string(p.note_letter)
                    : "";
                if ((p_label == "?" || string_length(p_label) <= 0) && variable_struct_exists(p, "note_canonical")) {
                    p_label = chanter_canonical_to_display(string(p.note_canonical));
                }
                if (p_label == "?" || string_length(p_label) <= 0) {
                    p_label = midi_to_letter(real(p.note_midi ?? 0), real(p.channel ?? -1));
                }
                if (p_label == "?" || string_length(p_label) <= 0) {
                    p_label = gv_note_label_from_midi(real(p.note_midi ?? 0));
                }
                var pending_duration_ms = max(0, end_ms - start_ms);
                var is_pending_short = (pending_duration_ms < core_min_ms);
                var p_text_h = string_height(p_label) * note_text_scale;
                var p_row_mid = (_ry1 + _ry2) * 0.5;
                var p_text_y = is_pending_short ? (p_row_mid + 1) : (_ry1 + 1);
                p_text_y = clamp(p_text_y, _ry1 + 1, max(_ry1 + 1, _ry2 - p_text_h - 1));
                
                draw_set_color(is_pending_short ? player_short_text_color : player_melody_text_color);
                draw_text_transformed(plx + 2, p_text_y, p_label, note_text_scale, note_text_scale, 0);
            }
        }
    }
    
    surface_reset_target();
}

function gv_blit_player_surface_cache(_surface, _screen_x1, _screen_y1) {
    // Fast blit cached player spans from surface to screen
    if (!surface_exists(_surface)) return false;
    
    draw_set_color(c_white);
    draw_set_alpha(1);
    draw_surface(_surface, _screen_x1, _screen_y1);
    
    return true;
}
