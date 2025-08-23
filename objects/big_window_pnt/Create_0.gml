/// @description Insert description here
// You can write your code in this editor

image_xscale = window_xscale;
image_yscale = window_yscale;

// In the Create Event 
dragging = false; 
dragOffsetX = 0; 
dragOffsetY = 0;
closeOffsetx = sprite_width - 10;
closeOffsety = 10;
rightOffsetx = sprite_width - 10;
rightOffsety =  sprite_height;
okOffsetX = ((sprite_width )  - (sprite_get_width(spr_button_round) *.65 )  );
okOffsetY = ((sprite_height ) - (sprite_get_height(spr_button_round)*.75 )  );

titleOffsetx = ((sprite_width/2) - (string_width(window_title_text)/3) -15); 
titleOffsety = 32; 
title_x = x + titleOffsetx; 
title_y = y + titleOffsety; 

//Create close button
//
	if(has_close_button==true) {
		close_button = instance_create_depth(x + closeOffsetx, y+closeOffsety, depth-13, Obj_button_windows_close);
		close_button.window_parent = id;
		
		close_button_script = function() {
			//Add code to open whatever MIDI input and outpur devices are selected.
			instance_destroy(close_button.window_parent);
			instance_destroy(self);
			global.next_window_depth-=10;
		}
		close_button.button_script = close_button_script;
	}

//Create OK button
//Default action is close window
	if(has_right_button==true) {
		ok_button = instance_create_depth(x + okOffsetX, y +okOffsetY, depth-5, obj_OK_button);
		ok_button.image_yscale = 1.0;
		ok_button.image_xscale = 1.0;
		ok_button.window_parent = id;

		ok_button_script = function() {
			instance_destroy(close_button.window_parent);
			instance_destroy(self);
			global.next_window_depth-=10;
		}
		
		ok_button.button_script = ok_button_script;

	}

//Window with title dimensions:
///Title is 62 pixels high, from 4 to 66
///Contents starts at 72
///Ninesliced in contents so the dimensions can be varied