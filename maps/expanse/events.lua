local Event = require 'utils.event'

-- Event IDs belong to this control-stage registration, not the saved world.
-- A changed mod list or registration order can give an old ID a different handler.
-- All senders and receivers share this module; never restore these IDs from storage.
return {
    gui_update = Event.generate_event_name('expanse_gui_update'),
    mission_gui_update = Event.generate_event_name('expanse_missions_gui_update'),
    invasion_warn = Event.generate_event_name('invasion_warn'),
    invasion_detonate = Event.generate_event_name('invasion_detonate'),
    invasion_trigger = Event.generate_event_name('invasion_trigger'),
    victory = Event.generate_event_name('victory'),
    map_reset = Event.generate_event_name('expanse_map_reset')
}
