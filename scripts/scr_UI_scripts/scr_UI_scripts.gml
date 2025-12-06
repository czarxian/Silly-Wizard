/// @desc UI Layer Utilities

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