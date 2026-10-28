---@diagnostic disable

local prepare_view = require("fixtures").view
local gui = require("helpers").gui

return {
    formatting = {check=function(context)
        local player, player_table = prepare_view(context)
        local prefs = player_table.preferences
        prefs.timescale = 1
        item_views.rebuild_data(player)
        local data = player_table.ui_state.views_data
        -- Supply a prepared capacity to exercise formatting even in the base-only test world.
        data.views.rockets_per_timescale.lift_capacity = 1000
        local item = {type="item", stack_size=50, weight=10}
        local cases = {
            {"items_per_timescale", 1, "item"},
            {"throughput", 1 / data.views.throughput.multiplier, prefs.belts_or_lanes:sub(1, -2)},
            {"items_per_second_per_machine", 2, "item", 2},
            {"stacks_per_timescale", 50, "stack"},
            {"wagons_per_timescale", data.views.wagons_per_timescale.cargo_capacity * 50, "wagon"},
            {"rockets_per_timescale", 100, "rocket"}
        }
        for _, case in ipairs(cases) do
            prefs.item_views.selected.primary = case[1]
            for _, value in ipairs{
                {0, 0, "0"}, {1, 1, "1"}, {1.000000001, 1, "1"}, {2, 2, "2"},
                {32.00001, 32, "32"}, {32.004, 32, "32"}, {32.006, 32.1, "32.01"},
                {32.04, 32.1, "32.04"}, {0.00001, 0.1, "≤0.0001"}
            } do
                local amount, tooltip = item_views.process_item(player, item, case[2] * value[1], case[4])
                assert(amount == value[2], "Match button to tooltip precision in " .. case[1])
                assert(tooltip[2] == value[3], "Keep tooltip precision across all views")
                assert(tooltip[4][1] == "fp.pl_" .. case[3])
                assert(tooltip[4][2] == (value[3] == "1" and 1 or 2), "Pluralize the displayed value")
            end
        end

        prefs.item_views.selected.primary = "items_per_second_per_machine"
        local _, without_machine = item_views.process_item(player, item, 1)
        local _, with_machine = item_views.process_item(player, item, 1, 1)
        assert(not serpent.line(without_machine):find("fp.pl_machine", 1, true))
        assert(serpent.line(with_machine):find("fp.pl_machine", 1, true))
        local amount, tooltip = item_views.process_item(player, item, 1, 0)
        assert(amount == 0 and tooltip == nil)
        _, tooltip = item_views.process_item(player, {type="fluid"}, 1)
        assert(tooltip[4][1] == "fp.l_fluid")

        prefs.item_views.selected.primary = "stacks_per_timescale"
        amount, tooltip = item_views.process_item(player, {type="fluid"}, 1)
        assert(amount == nil and tooltip[1] == "fp.fluid_item")
        prefs.item_views.selected.primary = "rockets_per_timescale"
        amount, tooltip = item_views.process_item(player, {type="item", weight=1001}, 1)
        assert(amount == nil and tooltip[1] == "fp.item_too_heavy")

        prefs.item_views.selected = {primary="items_per_timescale", secondary="stacks_per_timescale"}
        local secondary
        amount, tooltip, secondary = item_views.process_item(player, item, 100)
        assert(amount == 2 and secondary == 100)
        assert(tooltip[2][2] == "100" and tooltip[4][2] == "2", "Tooltips follow upper/main number order")
        amount, tooltip, secondary = item_views.process_item(player, {type="fluid"}, 100)
        assert(amount == nil and secondary == 100 and tooltip[4][1] == "fp.fluid_item")
        amount, tooltip, secondary = item_views.process_item(player, {type="entity", fixed_unit="units"}, 100)
        assert(amount == 100 and secondary == nil, "Entity amounts must not be duplicated")
        amount, tooltip, secondary = item_views.process_item(player, item, 100.00001)
        assert(amount == 2 and secondary == 100, "Both selected views must use tooltip precision")
        amount, tooltip, secondary = item_views.process_item(player, item, 1e-12)
        assert(amount == -1 and tooltip == nil and secondary == nil)
        amount, tooltip, secondary = item_views.process_item(player, item, 0)
        assert(amount == 0 and secondary == 0)

        prefs.timescale = 60
        item_views.rebuild_data(player)
        prefs.item_views.selected = {primary="items_per_timescale"}
        for _, proto in ipairs{item, {type="fluid"}, {type="entity"}, {type="entity", fixed_unit="units"}} do
            local rate = proto.fixed_unit and 32.00001 or 32.00001 / 60
            amount, tooltip = item_views.process_item(player, proto, rate)
            assert(amount == 32 and tooltip[2] == "32", "Round after applying the view's timescale")
        end
    end},
    selection = {check=function(context)
        local player, player_table = prepare_view(context)
        local district = context.classes.District.init()
        player_table.realm:insert(district)
        local factory = context.classes.Factory.init("item-view-selection", "sequential")
        district:insert(factory)
        lib.context.set(player, factory)
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)
        local ui, prefs = player_table.ui_state, player_table.preferences.item_views

        local function dispatch(element, event_name)
            gui.dispatch(player, element, event_name)
        end

        local function assert_selection(name, second)
            assert(prefs.selected.primary == name)
            assert(prefs.selected.secondary == second)
            for _, elements in ipairs{ui.main_elements, ui.compact_elements} do
                local selected = 0
                for _, button in pairs(elements.views_flow.table_views.children) do
                    if button.toggled then
                        assert((button.tags.view_name == name or button.tags.view_name == second) and button.visible)
                        selected = selected + 1
                    end
                end
                assert(selected == (second and 2 or 1), "Both selectors must keep the named selections")
            end
        end

        dispatch(ui.main_elements.views_flow.table_views.children[2], defines.events.on_gui_click)
        assert_selection("items_per_timescale", "throughput")
        assert(not ui.main_elements.views_flow.table_views.children[3].enabled)
        dispatch(ui.main_elements.views_flow.table_views.children[3], defines.events.on_gui_click)
        assert_selection("items_per_timescale", "throughput")
        dispatch(ui.main_elements.views_flow.table_views.children[1], defines.events.on_gui_click)
        assert_selection("throughput")
        dispatch(ui.main_elements.views_flow.table_views.children[2], defines.events.on_gui_click)
        assert_selection("throughput")
        local amount = item_views.process_item(player, {type="item"}, defaults.get(player, "belts").proto.throughput)

        lib.gui.open_dialog(player, {dialog="preferences"})
        local function move_up(index)
            local button = gui.require(lib.globals.modal_elements(player).views_table, {on_gui_click="move_preferences_view", index=index, direction="up"})
            assert(button and button.enabled)
            dispatch(button, defines.events.on_gui_click)
        end
        move_up(2) -- move the selected view
        assert(prefs.views[1].name == "throughput")
        assert_selection("throughput")
        move_up(2) -- move another view across the selection
        assert(prefs.views[2].name == "throughput")
        assert_selection("throughput")
        assert(item_views.process_item(player, {type="item"}, defaults.get(player, "belts").proto.throughput) == amount,
            "Reordering must retain the view used to format items")

        local checkbox = gui.require(lib.globals.modal_elements(player).views_table, {on_gui_checked_state_changed="toggle_preference_view", name="throughput"})
        assert(checkbox and checkbox.enabled)
        checkbox.state = false
        dispatch(checkbox, defines.events.on_gui_checked_state_changed)
        assert_selection("items_per_timescale")
        lib.gui.close_dialog(player, "cancel")

        for _, compact in ipairs{false, true} do
            ui.compact_view = compact
            local elements = compact and ui.compact_elements or ui.main_elements
            dispatch(elements.views_flow.table_views.children[1], defines.events.on_gui_click)
            assert_selection("items_per_timescale")
            dispatch(elements.views_flow.table_views.children[3], defines.events.on_gui_click)
            assert_selection("items_per_timescale", "items_per_second_per_machine")
            dispatch(elements.views_flow.table_views.children[1], defines.events.on_gui_click)
            assert_selection("items_per_second_per_machine")
            dispatch(elements.views_flow.table_views.children[1], defines.events.on_gui_click)
            assert_selection("items_per_timescale", "items_per_second_per_machine")
            dispatch(elements.views_flow.table_views.children[3], defines.events.on_gui_click)
            assert_selection("items_per_timescale")
        end
        player_table.realm:remove(district)
    end}
}
