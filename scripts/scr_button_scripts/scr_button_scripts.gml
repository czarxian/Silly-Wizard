
//Button base behavior
	function scr_init_button(){
	button_label  = "Button";
	button_action = noone;
	sprite_index  = spr_btn_mainmenu;
	image_index   = 0;
	image_speed   = 0;
	}

//Main menu buttons
	//Play
	function scr_goto_playroom(){
		room_goto(rm_gameplay);
	}
	//Settings
	function scr_open_settings(){
		layer_set_visible("layer_ui_settings", true);
	}
	//Tune
	function scr_script_not_set(){
		show_debug_message("Script Not Set");
	}
	//End
	function scr_exit_game(){
		game_end();
	}

