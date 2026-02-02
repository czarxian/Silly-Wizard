// scr_UI_scripts — UI layer utilities & field sync
// Purpose: Helpers for mapping layer names/indices, refreshing UI assets, and updating fields from global arrays.
// Key functions: GetLayerNameFromIndex, GetLayerIndexFromName, scr_update_fields, scr_ui_refresh

/// @desc UI Layer Utilities
//test//
/// @function GetLayerNameFromIndex(_index)
	// @desc Returns the layer name string for a given index, or "unknown layer" if invalid.
	function GetLayerNameFromIndex(_index) {
	    if (_index >= 0 && _index < array_length(global.ui_layer_names)) {
	        return global.ui_layer_names[_index];
	    }
	    return "unknown layer";
	}

/// @function GetLayerIndexFromName(_name)
	// @desc Returns the numeric index for a given layer name, or -1 if not found.
	function GetLayerIndexFromName(_name) {
	    var len = array_length(global.ui_layer_names);
	    for (var i = 0; i < len; i++) {
	        if (global.ui_layer_names[i] == _name) {
	            return i;
	        }
	    }
	    return -1;
	}
	
	/// @function scr_hide_window(_target, _inst)
	// @desc Safely hide a UI layer based on a button's label, a layer name, or a layer index. Returns true if a layer was hidden.
	function scr_hide_window(_target, _inst) {
	    var hid = false;
	
	    // Direct string target (likely a layer name)
	    if (!is_undefined(_target) && is_string(_target)) {
	        var lid = layer_get_id(_target);
	        if (lid != -1) {
	            layer_set_visible(lid, false);
	            return true;
	        }
	        // Try mapping via our layer name array
	        var idx = GetLayerIndexFromName(_target);
	        if (idx >= 0) {
	            var lname = GetLayerNameFromIndex(idx);
	            var lid2 = layer_get_id(lname);
	            if (lid2 != -1) {
	                layer_set_visible(lid2, false);
	                return true;
	            }
	        }
	    }
	
	    // Numeric target (layer index)
	    if (!is_undefined(_target) && (is_real(_target) || is_integer(_target))) {
	        var lname2 = GetLayerNameFromIndex(_target);
	        var lid3 = layer_get_id(lname2);
	        if (lid3 != -1) {
	            layer_set_visible(lid3, false);
	            return true;
	        }
	    }
	
	    // Fallback to the instance's ui_layer_num if provided
	    if (!is_undefined(_inst) && variable_instance_exists(_inst, "ui_layer_num")) {
	        var lname3 = GetLayerNameFromIndex(_inst.ui_layer_num);
	        var lid4 = layer_get_id(lname3);
	        if (lid4 != -1) {
	            layer_set_visible(lid4, false);
	            return true;
	        }
	    }
	
	    return false;
	}
	
		function scr_update_fields(_ui_layer_num) {
	    var assets = global.ui_assets[_ui_layer_num];
	
	    for (var i = 0; i < array_length(assets); i++) {
	        var entry = assets[i];
	        var inst  = entry[1];
	
	        if (instance_exists(inst) && inst.ui_type == "field") {
	            with (inst) {
	                var target_array;
	
	                if (is_string(field_target)) {
	                    // resolve the global variable by name
	                    target_array = variable_global_get(field_target);
	                } else {
	                    target_array = field_target; // already a reference
	                }
	
	                if (is_array(target_array)) {
	                    var len = array_length(target_array);
	                    if (field_value >= 0 && field_value < len) {
	                        field_contents = target_array[field_value];
	                    }
	                }
	            }
	        }
	    }
	}
	
	function scr_ui_refresh(_layer_num) {
	    if (!is_array(global.ui_assets) || !is_array(global.ui_assets[_layer_num])) return;
	
	    for (var i = 0; i < array_length(global.ui_assets[_layer_num]); i++) {
	        var entry = global.ui_assets[_layer_num][i];
	        var num   = entry[0];
	        var oldID = entry[1];
	
	        if (!instance_exists(oldID)) {
	            with (obj_UI_parent) {
	                if (ui_num == num && ui_layer_num == _layer_num) {
	                    global.ui_assets[_layer_num][i][1] = id;
	                }
	            }
	        }
	    }
	}