/// @description Insert description here
// You can write your code in this editor

// Inherit the parent event
event_inherited();


//Update values and draw setting items in correct place


for (i=0; i<number_of_settings; i++;)
{
	//Update field text based on buttons
	if (setting_item[i].field_updated=true) {
		setting_item[i].field_text = setting_item[i].field_text;
		setting_item[i].field_updated=false;
	}

	//Draw in right place
	setting_item[i].x = x + 10 + sprite_get_width(spr_arrow_left)+15;
	setting_item[i].y = y + setting_window_content_origin+((i+1)*(setting_item_height+setting_item_space));
	setting_item_left_button[i].x = x + 10;
	setting_item_left_button[i].y = y+setting_window_content_origin+((i+1)*(setting_item_height+setting_item_space))+((sprite_get_height(spr_setting_item)-sprite_get_height(spr_arrow_left))/2);
	setting_item_right_button[i].x = (x + setting_item_width + 70);
	setting_item_right_button[i].y = y+setting_window_content_origin+((i+1)*(setting_item_height+setting_item_space))+((sprite_get_height(spr_setting_item)-sprite_get_height(spr_arrow_left))/2);
	
}

