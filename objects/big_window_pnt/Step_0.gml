/// @description Insert description here
// You can write your code in this editor

// In the Step Event 


if (mouse_check_button_pressed(mb_left)) 
{ 
	if (point_in_rectangle(mouse_x, mouse_y, x, y, x + sprite_width, y + sprite_height)) 
	{ 
		dragging = true; 
		dragOffsetX = mouse_x - x; 
		dragOffsetY = mouse_y - y; 
	} 
}

if (mouse_check_button_released(mb_left)) { dragging = false; } 

if (dragging) { 
	x = mouse_x - dragOffsetX; 
	y = mouse_y - dragOffsetY;

	title_x = x + titleOffsetx; 
	title_y = y + titleOffsety; 
	
	if(has_close_button==true)	{
		close_button.x = x + closeOffsetx;
		close_button.y = y + closeOffsety;
	}
	if(has_right_button==true) {
		show_debug_message("dragging right button");
		ok_button.x = x + okOffsetX;
		ok_button.y = y + okOffsetY;
	}

}