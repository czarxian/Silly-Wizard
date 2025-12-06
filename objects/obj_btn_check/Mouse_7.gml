
//keep check if checked, hover if not.
	if(button_checked==0)	{
		image_index = 3; // Return to hover after click
	}
	else if (button_checked==1)	{
		image_index = 1; // Return to hover after click
	}

//if (button_action != noone) {
scr_handle_button_click(button_script_index);
//}