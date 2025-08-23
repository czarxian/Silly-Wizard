/// @description Insert description here
// You can write your code in this editor
event_inherited();

for (i=0; i<number_of_settings; i+=1;)
{
	instance_destroy(setting_item[i]);
	instance_destroy(setting_item_left_button[i]);
	instance_destroy(setting_item_right_button[i]);
}

//When closed, allow other windows to be opened.
if global.mainmenu_window_exists==true {
	global.mainmenu_window_exists=false;
}