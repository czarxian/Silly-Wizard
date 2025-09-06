width  = 300;
height = 200;
padding = 8;
spacing = 4;

if (!variable_instance_exists(id, "panel_style")) {
    panel_style = "default";
}
background_sprite = get_panel_sprite(panel_style);


clickable = false;
hovered = false;

children = [];
array_push(global.ui_elements, id);