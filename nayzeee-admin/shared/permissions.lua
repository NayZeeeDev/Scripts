-- Every permission the panel understands. Groups store a list of these ids, or '*' for all.
-- Add your own under Addon and check them with exports['nayzeee-admin']:HasPermission(src, 'your.id')
NZ = NZ or {}
NZ.Permissions = {
    { cat = 'Self', list = {
        { 'self.panel', 'Open the panel' }, { 'self.quickmenu', 'Open the quick menu' },
        { 'self.noclip', 'Noclip' }, { 'self.godmode', 'God mode' }, { 'self.invisibility', 'Invisibility' },
        { 'self.super_jump', 'Super jump' }, { 'self.fast_run', 'Fast run' }, { 'self.infinite_ammo', 'Infinite ammo' },
        { 'self.night_vision', 'Night vision' }, { 'self.thermal_vision', 'Thermal vision' }, { 'self.head_light', 'Head light' },
        { 'self.player_names', 'Player names' }, { 'self.player_ids', 'Player IDs' }, { 'self.show_coords', 'Show coords' },
        { 'self.freeze', 'Freeze self' }, { 'self.revive', 'Revive self' }, { 'self.kill', 'Kill self' },
        { 'self.teleport', 'Teleport (waypoint, coords, locations)' }, { 'self.entity_inspector', 'Entity inspector' },
        { 'self.clothing_menu', 'Own clothing menu' }, { 'self.give_weapon', 'Give self weapons' },
        { 'self.manage_time', 'Local time and weather' }, { 'self.blackout', 'Local blackout' },
    } },
    { cat = 'Players', list = {
        { 'player.spectate', 'Spectate' }, { 'player.teleport', 'Goto / bring / send' }, { 'player.kick', 'Kick' },
        { 'player.ban', 'Ban' }, { 'player.unban', 'Unban' }, { 'player.warn', 'Warn' }, { 'player.warn_remove', 'Remove warnings' },
        { 'player.jail', 'Jail' }, { 'player.jail_remove', 'Release from jail' }, { 'player.freeze', 'Freeze' },
        { 'player.revive', 'Revive' }, { 'player.heal', 'Heal' }, { 'player.give_armor', 'Give armour' },
        { 'player.give_food_and_water', 'Food and water' }, { 'player.kill', 'Kill' }, { 'player.slap', 'Slap' },
        { 'player.ragdoll', 'Ragdoll' }, { 'player.burn', 'Set on fire' }, { 'player.explode', 'Explode' },
        { 'player.handcuff', 'Handcuff' }, { 'player.unarm', 'Remove weapons' }, { 'player.give_weapon', 'Give weapons' },
        { 'player.notify', 'Send message' }, { 'player.change_ped', 'Change ped' }, { 'player.clothing_menu', 'Open their clothing menu' },
        { 'player.routing_bucket', 'Change routing bucket' }, { 'player.update_job', 'Set job' }, { 'player.set_group', 'Set framework group' },
        { 'player.manage_accounts', 'Edit money' }, { 'player.view_money_accounts', 'View money' },
        { 'player.view_identifiers', 'View identifiers' }, { 'player.view_ip', 'View IP' },
        { 'player.view_notes', 'View notes' }, { 'player.create_notes', 'Write notes' }, { 'player.delete_notes', 'Delete notes' },
        { 'player.flags', 'Manage flags' }, { 'player.screenshot', 'Screenshot' }, { 'player.staff_call', 'Pull into staff call' },
        { 'player.delete_character', 'Delete character' },
    } },
    { cat = 'Inventory', list = {
        { 'inventory.view', 'View inventories' }, { 'inventory.give', 'Give items' }, { 'inventory.remove', 'Remove items' },
        { 'items_database.view', 'Item lookup' },
    } },
    { cat = 'Vehicles', list = {
        { 'vehicles.spawn', 'Spawn vehicles' }, { 'vehicles.give', 'Give owned vehicles' }, { 'vehicles.view', 'World vehicle list' },
        { 'vehicles.despawn', 'Despawn world vehicles' }, { 'vehicles.repair', 'Repair' }, { 'vehicles.unlock_doors', 'Unlock doors' },
        { 'vehicles.set_mods', 'Tune (max mods, colours)' }, { 'vehicles.set_plate', 'Change plates' }, { 'vehicles.give_key', 'Give keys' },
        { 'vehicles.force_wipe', 'Vehicle wipe' }, { 'vehicles_database.view', 'Owned vehicle database' },
        { 'vehicles.set_owner', 'Transfer owner' }, { 'vehicles.send_to_garage', 'Send to garage' }, { 'vehicles.remove', 'Delete owned vehicles' },
    } },
    { cat = 'Offline players', list = {
        { 'offline_player.search', 'Search characters' }, { 'offline_player.update_name', 'Rename' },
        { 'offline_player.change_job', 'Change job' }, { 'offline_player.change_money', 'Change money' },
        { 'offline_player.ban', 'Ban offline' }, { 'offline_player.delete', 'Delete character' },
    } },
    { cat = 'Moderation', list = {
        { 'moderation.view.warnings', 'Warnings list' }, { 'moderation.view.bans', 'Bans list' }, { 'moderation.view.jail', 'Jail list' },
        { 'reports.view', 'See reports' }, { 'reports.close', 'Close reports' },
        { 'chats.view', 'Staff chats' }, { 'chats.create', 'Create rooms' }, { 'chats.update', 'Edit rooms' }, { 'chats.delete', 'Delete rooms' },
        { 'announcements.create', 'Announcements' }, { 'logs.view', 'Logs' },
    } },
    { cat = 'Server', list = {
        { 'statistics.view', 'Dashboard' }, { 'map.view', 'Live map' }, { 'weather.change', 'Weather and time' },
        { 'resources.read', 'Resources list' }, { 'resources.manage', 'Start / stop resources' },
        { 'console.read', 'Read console' }, { 'console.execute', 'Run console commands' }, { 'developer.execute', 'Run Lua code' },
        { 'props.view', 'Props list' }, { 'props.create', 'Place props' }, { 'props.delete', 'Delete props' },
        { 'zones.view', 'Zones list' }, { 'zones.create', 'Create zones' }, { 'zones.delete', 'Delete zones' },
        { 'blips.create', 'Create blips' }, { 'blips.delete', 'Delete blips' },
        { 'events.view', 'Events calendar' }, { 'events.create', 'Create events' }, { 'events.delete', 'Delete events' },
    } },
    { cat = 'Staff', list = {
        { 'staff.view', 'Staff list and duty' }, { 'staff.manage', 'Manage groups and members' },
    } },
    { cat = 'Addon', list = {
        -- { 'my.custom_permission', 'My custom permission' },
    } },
}

NZ.PermissionSet = {}
for _, c in ipairs(NZ.Permissions) do
    for _, p in ipairs(c.list) do NZ.PermissionSet[p[1]] = true end
end
