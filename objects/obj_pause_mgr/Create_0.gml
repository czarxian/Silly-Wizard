//code to handle the UI Layer "main_menu_layer"
paused = false;
layer_name = "main_menu_layer";
layer_id = layer_get_id("main_menu_layer");


function update_pause(){
	if(paused = true)	{
		instance_deactivate_all(true);
		layer_set_visible(layer_name, true);
	}
	else	{
		instance_activate_all();
		layer_set_visible(layer_name, false);
	}
}
update_pause();
