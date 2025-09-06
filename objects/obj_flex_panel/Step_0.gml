/// @desc Update children (so their Step events run)
for (var i = 0; i < array_length(children); i++) {
    var child = children[i];
    if (instance_exists(child)) {
        with (child) event_perform(ev_step, ev_step_normal);
    }
}