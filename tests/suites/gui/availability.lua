---@diagnostic disable

local prepare_view = require("fixtures").view
local gui = require("helpers").gui

local tests = {}

-- Wagons
do
    local function check_selection(player, cargo_available, fluid_available)
        local ui, prefs = lib.globals.ui_state(player), lib.globals.preferences(player).item_views
        local available = cargo_available or fluid_available
        local expected_selection = available and "wagons_per_timescale" or "items_per_timescale"
        assert(prefs.selected.primary == expected_selection)
        for _, view in ipairs(prefs.views) do
            assert(view.enabled == (view.name == expected_selection), "Only the selected view should remain enabled in this fixture")
        end
        for _, elements in ipairs{ui.main_elements, ui.compact_elements} do
            local visible, selected = 0, 0
            for _, button in pairs(elements.views_flow.table_views.children) do
                if button.visible then visible = visible + 1 end
                if button.toggled then
                    selected = selected + 1
                    assert(button.visible and button.tags.view_name == prefs.selected.primary)
                end
            end
            assert(visible == 1 and selected == 1, "Both selectors must show the enabled and selected view")
        end
        for _, entry in ipairs{{"cargo-wagon", "item", cargo_available}, {"fluid-wagon", "fluid", fluid_available}} do
            local amount, tooltip = item_views.process_item(player, {type=entry[2], stack_size=100}, 2)
            if expected_selection == "items_per_timescale" then
                assert(amount == 120, "The items/minute selection must control formatting")
            elseif not entry[3] then
                assert(amount == nil and tooltip == nil, "Missing wagon types must leave amounts blank without a warning")
            else
                local default = defaults.get_optional(player, "wagons", entry[1])
                local proto = prototypes.entity[default.proto.name]
                local capacity = entry[1] == "cargo-wagon"
                    and proto.get_inventory_size(defines.inventory.cargo_wagon, default.quality.name) * 100
                    or proto.get_fluid_capacity(default.quality.name)
                amount = item_views.process_item(player, {type=entry[2], stack_size=100}, capacity / 60)
                assert(amount == 1, "Available wagons must still produce wagon counts")
            end
        end
        lib.gui.open_dialog(player, {dialog="preferences"})
        local modal = lib.globals.modal_elements(player)
        for _, entry in ipairs{{"cargo-wagon", cargo_available}, {"fluid-wagon", fluid_available}} do
            local control = gui.require(modal.modal_frame, {on_gui_elem_changed="select_preference_box_default", category_id=entry[1]})
            assert(control and control.enabled == entry[2])
            if entry[2] then
                assert(prototypes.entity[control.elem_value.name].type == entry[1], "Controls must resolve category names, not fixed IDs")
            else
                assert(control.elem_value == nil)
            end
        end
        for _, element in pairs(modal.views_table.children) do
            if element.type == "checkbox" and element.tags.name == "wagons_per_timescale" then
                assert(element.state == (expected_selection == "wagons_per_timescale"))
                if not available then assert(not element.enabled) end
            end
        end
        lib.gui.close_dialog(player, "cancel")
    end

    local function fixture(player, player_table, context)
        player_table.preferences.timescale = 60
        local prefs = player_table.preferences.item_views
        prefs.selected.primary = "wagons_per_timescale"
        for _, view in ipairs(prefs.views) do view.enabled = view.name == "wagons_per_timescale" end
        player_table.ui_state.views_data = nil
        item_views.rebuild_data(player)
        local district = context.classes.District.init()
        player_table.realm:insert(district)
        local factory = context.classes.Factory.init("wagon-views", "sequential")
        district:insert(factory)
        lib.context.set(player, factory)
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)
        return district
    end

    local wagon_views = {}

    function wagon_views.case(cargo_available, fluid_available)
        return {
            setup = function()
                for _, entry in ipairs{{"cargo-wagon", cargo_available}, {"fluid-wagon", fluid_available}} do
                    if not entry[2] then
                        for _, proto in pairs(data.raw[entry[1]]) do proto.hidden = true end
                        data.raw["item-with-entity-data"][entry[1]].hidden = true
                    end
                end
            end,
            check = function(context)
                local player, player_table = prepare_view(context)
                local district = fixture(player, player_table, context)
                check_selection(player, cargo_available, fluid_available)
                for _, compact in ipairs{false, true} do
                    player_table.ui_state.compact_view = compact
                    item_views.rebuild_data(player)
                    local expected = (cargo_available or fluid_available) and "wagons_per_timescale" or "items_per_timescale"
                    assert(player_table.preferences.item_views.selected.primary == expected)
                end
                player_table.realm:remove(district)
            end
        }
    end

    tests.wagons = wagon_views
end

-- Throughput
do
    local throughput_views = {}

    function throughput_views.case(pump_available)
        return {
            setup = function()
                if not pump_available then
                    for _, proto in pairs(data.raw.pump) do proto.hidden = true end
                end
            end,
            check = function(context)
                local player, player_table = prepare_view(context)
                local prefs = player_table.preferences
                prefs.item_views.selected.primary = "throughput"
                for _, view in ipairs(prefs.item_views.views) do view.enabled = view.name == "throughput" end

                local district = context.classes.District.init()
                player_table.realm:insert(district)
                local factory = context.classes.Factory.init("throughput-views", "sequential")
                district:insert(factory)
                lib.context.set(player, factory)
                main_dialog.rebuild(player, false)
                compact_dialog.rebuild(player, false)

                local belt_rate = defaults.get(player, "belts").proto.throughput
                local pump = defaults.get_optional(player, "pumps")
                for _, unit in ipairs{"belts", "lanes"} do
                    for _, stack in ipairs{1, 4} do
                        prefs.belts_or_lanes, prefs.belt_stack = unit, stack
                        item_views.rebuild_data(player)
                        local rate = belt_rate * stack / (unit == "lanes" and 2 or 1)
                        local amount, tooltip = item_views.process_item(player, {type="item"}, rate)
                        assert(amount == 1 and tooltip[4][1] == "fp.pl_" .. unit:sub(1, -2))
                        if pump_available then
                            local pump_rate = prototypes.entity[pump.proto.name].get_pumping_speed(pump.quality.name) * 60
                            amount, tooltip = item_views.process_item(player, {type="fluid"}, pump_rate)
                            assert(amount == 1 and tooltip[4][1] == "fp.pl_pump")
                        else
                            amount, tooltip = item_views.process_item(player, {type="fluid"}, 100)
                            assert(amount == nil and tooltip == nil, "Missing pumps must leave fluid amounts blank")
                        end
                    end
                end

                item_views.rebuild_interface(player)
                assert(prefs.item_views.selected.primary == "throughput", "Missing pumps must not drop the throughput selection")
                for _, elements in ipairs{player_table.ui_state.main_elements, player_table.ui_state.compact_elements} do
                    for _, button in pairs(elements.views_flow.table_views.children) do
                        local selected = button.tags.view_name == "throughput"
                        assert(button.visible == selected and button.toggled == selected)
                    end
                end

                lib.gui.open_dialog(player, {dialog="preferences"})
                local picker = gui.require(lib.globals.modal_elements(player).modal_frame, {on_gui_elem_changed="select_preference_box_default", data_type="pumps"})
                assert(picker and picker.enabled == pump_available)
                if pump_available then
                    assert(picker.elem_value.name == pump.proto.name)
                else
                    assert(picker.elem_value == nil and picker.tooltip[1] == "fp.preference_no_default_prototype")
                    assert(picker.tooltip[2][1] == "fp.pl_pump")
                end
                lib.gui.close_dialog(player, "cancel")
                player_table.realm:remove(district)
            end
        }
    end

    tests.throughput = throughput_views
end

-- Rockets
do
    tests.rockets = {
        setup = function()
            for _, proto in pairs(data.raw["rocket-silo"]) do proto.launch_to_space_platforms = false end
        end,
        check = function(context)
            local player, player_table = prepare_view(context)
            player_table.preferences.timescale = 60
            local prefs = player_table.preferences.item_views
            prefs.selected.primary = "rockets_per_timescale"
            for _, view in ipairs(prefs.views) do view.enabled = view.name == "rockets_per_timescale" end

            local district = context.classes.District.init()
            player_table.realm:insert(district)
            local factory = context.classes.Factory.init("rocket-views", "sequential")
            district:insert(factory)
            lib.context.set(player, factory)
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)

            assert(prefs.selected.primary == "items_per_timescale")
            for _, view in ipairs(prefs.views) do
                assert(view.enabled == (view.name == "items_per_timescale"))
            end
            assert(item_views.process_item(player, {type="item"}, 2) == 120)

            lib.gui.open_dialog(player, {dialog="preferences"})
            local modal = lib.globals.modal_elements(player)
            local picker = gui.require(modal.modal_frame, {on_gui_elem_changed="select_preference_box_default", data_type="silos"})
            assert(picker and not picker.enabled and picker.elem_value == nil)
            assert(picker.tooltip[1] == "fp.preference_no_default_prototype")

            local checkbox
            for _, child in pairs(modal.views_table.children) do
                if child.tags.name == "rockets_per_timescale" then checkbox = child end
            end
            assert(checkbox and not checkbox.enabled and not checkbox.state)
            assert(checkbox.tooltip[1] == "fp.preference_no_default_prototype")
            lib.gui.close_dialog(player, "cancel")

            player_table.realm:remove(district)
        end
    }
end

return tests
