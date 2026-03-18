
//keep check if checked, hover if not.
	var _button_checked = variable_instance_exists(id, "button_checked") ? variable_instance_get(id, "button_checked") : 0;
	if(_button_checked==0)	{
		image_index = 3; // Return to hover after click
	}
	else if (_button_checked==1)	{
		image_index = 1; // Return to hover after click
	}

//if (button_action != noone) {
var _button_script_index = variable_instance_exists(id, "button_script_index") ? variable_instance_get(id, "button_script_index") : -1;
scr_handle_button_click(_button_script_index, id);
//}