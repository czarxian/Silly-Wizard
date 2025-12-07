
// obj_UI_parent Create Event
self.ui_num = global.next_ui_number;
global.next_ui_number++;

//Set the UI_layer_num 
var	_ui_layer = layer_get_name(layer);
var	_ui_layer_num = GetLayerIndexFromName(_ui_layer);
self.ui_layer = _ui_layer;
self.ui_layer_num  = _ui_layer_num;

sprite_index = ui_sprite;

//BACKUP
//// Initialize global array if needed
if (!variable_global_exists("ui_assets")) {
    global.ui_assets = [];
}
if (!is_array(global.ui_assets[self.ui_layer_num])) {
    global.ui_assets[self.ui_layer_num] = [];
}

//REGISTER
// Register this instance in the array
// Store a pair [ui_num, id] this allows us to refresh the id by using the ui_num.
////this is because the id may change in some circumstances. 
array_push(global.ui_assets[self.ui_layer_num], [self.ui_num, id]);

// Debug message		   
show_debug_message("Created: " + object_get_name(object_index) + 
                   " | ID: " + string(id) + 
                   " | Name: " + string(self.ui_name) + 
				   " | Layer: " + string(self.ui_layer_num) + 
                   " | UI Number: " + string(self.ui_num) +
                   " | UI Group: " + string(self.ui_group)
				   );

				   
