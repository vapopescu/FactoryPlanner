---@diagnostic disable

local helpers = require("helpers")
local gui = helpers.gui
local fixtures = require("fixtures")
local fixture = fixtures.target_item
local target_definition = fixtures.definition
local dispatch = gui.dispatch

local tests = {}

-- Target toggles
local function arrange(context)
    local player, factory, item = fixture(context)
    local line = context.classes.Line.init(prototyper.util.find("recipes", "iron-plate"))
    factory.top_floor:insert(line)
    line:change_machine_to_proto(player, helpers.find_machine("stone-furnace"))
    main_dialog.rebuild(player, false)
    compact_dialog.rebuild(player, false)

    local function product_button()
        return lib.globals.main_elements(player).item_boxes.product_item_table.children[1]
    end
    local function menu_toggle()
        local button = product_button()
        gui.click(player, button, {button=defines.mouse_button_type.right})
        local menu = lib.globals.ui_state(player).context_menu
        assert(menu, "Right-click must open the product context menu")
        for _, action in pairs(menu.children[1].children) do
            if action.tags.action == "toggle" then return action end
        end
        error("Product context menu must offer Toggle")
    end
    return player, factory, item, line, product_button, menu_toggle
end

for _, solver_name in ipairs{"sequential", "simplex", "gaussian"} do
    for _, kind in ipairs{"amount", "belts", "machines"} do
        tests["testProductToggle_" .. solver_name .. "_" .. kind] = {check=function(context)
            local player, factory, item, line, product_button, menu_toggle = arrange(context)
            factory.top_floor.solver = solver_name
            local definition = target_definition(kind)
            item.definition, item.active = definition, true
            solver.update(player, factory)
            local expected = line.machine.amount
            assert(expected > 0, "Active products must drive production")
            lib.gui.run_refresh(player, "production")
            dispatch(player, menu_toggle(), defines.events.on_gui_click)
            assert(item.active == false, "The menu toggle must disable the target")
            assert(item.definition == definition, "Disabling must retain the target definition")
            assert(line.machine.amount == 0, "A disabled target must stop driving production")
            assert(line.machine_requirement == nil, "Disabling must clear the machine requirement")
            assert(product_button().style.name == "fflib_slot_button_red", "A disabled target must use the red button style")
            -- Re-enable the replacement object created by pasting the disabled target
            lib.clipboard.copy(player, item)
            assert(lib.clipboard.paste(player, item), "Pasting the disabled target must succeed")
            item = factory.first
            dispatch(player, menu_toggle(), defines.events.on_gui_click)
            assert(item.active == true, "The menu toggle must re-enable the pasted target")
            assert(helpers.approx(line.machine.amount, expected), "Re-enabling must restore the original machine amount")
            assert(product_button().style.name == "fflib_slot_button_green", "An enabled target must use the green button style")
        end}
    end
end
tests.testPickerToggleSubmission = {check=function(context)
    local player, factory, item, line = arrange(context)
    item.definition = {type="machines", machine_count=5}
    solver.update(player, factory)
    for _, close_action in ipairs{"cancel", "submit", "submit"} do
        local active = item.active
        lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
        local button = lib.globals.modal_elements(player).active_button
        assert(button, "Editing a target must show an active toggle")
        assert(button.toggled == active, "The picker toggle must reflect the current active state")
        button.toggled = not active
        assert(item.active == active, "Editing the toggle must wait for submission")
        lib.gui.close_dialog(player, close_action)
        local expected = active
        if close_action == "submit" then expected = not active end
        assert(item.active == expected, "Closing the picker must apply the toggle only on submission")
        assert((line.machine.amount > 0) == expected, "Production must follow the submitted active state")
    end
    for _, create_factory in ipairs{false, true} do
        lib.gui.open_dialog(player, {dialog="picker",
            modal_data={item_category="product", create_factory=create_factory}})
        assert(lib.globals.modal_elements(player).active_button == nil,
            "The active toggle must only be offered when editing")
        lib.gui.close_dialog(player, "cancel")
    end
end}

tests.testArchivedTargetToggle = {check=function(context)
    local player, factory, item, line, product_button, menu_toggle = arrange(context)
    factory.archived = true
    lib.gui.run_refresh(player, "production")
    assert(not menu_toggle().enabled, "Archived targets must not be toggleable")
    modal_dialog.close_context_menu(player)
    factory.archived = false
end}

-- Target picker
for _, category in ipairs{"product", "ingredient"} do
    for _, create_factory in ipairs{false, true} do
        tests["testPickerCursorSelection_" .. category .. (create_factory and "_new" or "_existing")] = {check=function(context)
            local player, factory, item = fixture(context)
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)
            lib.gui.open_dialog(player, {dialog="picker",
                modal_data={item_category=category, create_factory=create_factory}})
            local modal_data = lib.globals.modal_data(player)
            player.cursor_stack.set_stack{name=item.proto.name, count=1}
            dispatch(player, modal_data.modal_elements.item_choice_button, defines.events.on_gui_click)
            if create_factory then
                assert(modal_data.item_proto == item.proto, "A new factory must ignore the old factory's targets")
            else
                assert(modal_data.item_proto == nil, "Cursor selection must reject duplicates on either side")
            end
            player.clear_cursor()
            lib.gui.close_dialog(player, "cancel")
        end}
    end
end
for _, unit in ipairs{"belts", "lanes"} do
    for _, mode in ipairs{"amount", "belts"} do
        tests["testPickerDefinitionTransitions_" .. unit .. "_" .. mode] = {check=function(context)
            local player, factory, item = fixture(context)
            local preferences = lib.globals.preferences(player)
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)
            preferences.belts_or_lanes = unit
            item.definition = (mode == "amount") and {type="amount", amount=90}
                or {type="belts", belt_count=2, belt_stack=2,
                    belt_proto=prototyper.util.find("belts", "transport-belt")}
            local expected = item:get_defined_amount()
            lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
            local e = lib.globals.modal_elements(player)
            assert(e.item_amount_textfield.enabled == (mode == "amount"))
            assert(e.belt_amount_textfield.enabled == (mode == "belts"))
            if mode == "belts" then
                assert(tonumber(e.belt_amount_textfield.text) == ((unit == "lanes") and 4 or 2))
                assert(e.belt_stack_dropdown.selected_index == 2)
            end
            assert(e.dialog_submit_button.enabled)
            lib.gui.close_dialog(player, "submit")
            assert(item.definition.type == mode, "Submitting unchanged fields must preserve the definition type")
            assert(math.abs(item:get_defined_amount() - expected) < 0.0001, "Submitting unchanged fields must preserve the defined amount")
            assert((item.definition.belt_proto ~= nil) == (mode == "belts"))
            lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
            e = lib.globals.modal_elements(player)
            assert(not e.machine_count_checkbox.state, "Amount and belt targets must start with machine mode unchecked")
            assert(not e.machine_count_textfield.enabled, "Machine count must be disabled outside machine mode")
            e.machine_count_checkbox.state = true
            dispatch(player, e.machine_count_checkbox, defines.events.on_gui_checked_state_changed)
            assert(not e.item_amount_textfield.enabled, "Machine mode must disable the item amount")
            assert(not e.belt_amount_textfield.enabled, "Machine mode must disable the belt amount")
            assert(not e.belt_choice_button.enabled, "Machine mode must disable belt selection")
            assert(not e.belt_stack_dropdown.enabled, "Machine mode must disable belt stack selection")
            assert(e.item_amount_textfield.text == "", "Changing definition mode must clear the item amount")
            assert(e.belt_amount_textfield.text == "", "Changing definition mode must clear the belt amount")
            assert(e.belt_choice_button.elem_value == nil)
            assert(e.belt_stack_dropdown.selected_index == preferences.belt_stack)
            assert(e.machine_count_textfield.enabled, "Machine mode must enable the machine count field")
            assert(not e.dialog_submit_button.enabled, "An empty machine count must prevent submission")
            e.machine_count_textfield.text = "2+3"
            dispatch(player, e.machine_count_textfield, defines.events.on_gui_text_changed)
            assert(e.dialog_submit_button.enabled)
            dispatch(player, e.machine_count_textfield, defines.events.on_gui_confirmed)
            assert(e.machine_count_textfield.text == "5")
            dispatch(player, e.machine_count_textfield, defines.events.on_gui_confirmed)
            assert(item.definition.type == "machines", "Submitting a machine count must select the machine definition")
            assert(item.definition.machine_count == 5, "Submitting the expression 2+3 must save five machines")
            assert(item:get_defined_amount() == nil, "A machine definition must not retain a defined amount")
            assert(item.definition.belt_proto == nil, "A machine definition must not retain a belt prototype")
            lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
            e = lib.globals.modal_elements(player)
            assert(e.machine_count_checkbox.state, "Reopening a machine target must select machine mode")
            assert(e.machine_count_textfield.enabled, "Reopening a machine target must enable its count field")
            assert(e.machine_count_textfield.text == "5", "Reopening must show the saved machine count")
            assert(e.dialog_submit_button.enabled, "The saved machine count must permit submission")
            assert(e.item_amount_textfield.text == "", "Reopening a machine target must leave the item amount blank")
            assert(not e.item_amount_textfield.enabled, "Reopening a machine target must disable the item amount")
            assert(e.belt_choice_button.elem_value == nil, "Reopening a machine target must leave belt selection empty")
            assert(not e.belt_choice_button.enabled, "Reopening a machine target must disable belt selection")
            e.machine_count_checkbox.state = false
            dispatch(player, e.machine_count_checkbox, defines.events.on_gui_checked_state_changed)
            assert(e.item_amount_textfield.enabled, "Leaving machine mode must enable the item amount")
            assert(not e.belt_amount_textfield.enabled, "Leaving machine mode without a belt must disable the belt amount")
            assert(e.item_amount_textfield.text == "", "Changing definition mode must clear the item amount")
            assert(e.belt_amount_textfield.text == "", "Changing definition mode must clear the belt amount")
            assert(not e.machine_count_textfield.enabled, "Leaving machine mode must disable the machine count")
            assert(not e.dialog_submit_button.enabled, "An empty item amount must prevent submission")
            e.item_amount_textfield.text = "60"
            dispatch(player, e.item_amount_textfield, defines.events.on_gui_text_changed)
            lib.gui.close_dialog(player, "submit")
            assert(item.definition.type == "amount", "Submitting an item amount must select the amount definition")
            assert(item.definition.machine_count == nil, "An amount definition must clear the previous machine count")
            assert(item:get_defined_amount() == 60 / preferences.timescale)
        end}
    end
end
tests.testMachineTargetPresentation = {check=function(context)
    local player, factory, item = fixture(context)
    main_dialog.rebuild(player, false)
    compact_dialog.rebuild(player, false)
    item.definition = {type="machines", machine_count=5}
    for _, amount in ipairs{0, 12} do
        item.amount = amount
        lib.gui.run_refresh(player, "item_boxes")
        local button = lib.globals.main_elements(player).item_boxes.product_item_table.children[1]
        local expected = item_views.process_item(player, item.proto, amount, nil)
        assert(button.number == expected, "A machine target button must show the formatted calculated amount")
        assert(button.style.name == "fflib_slot_button_green", "An active machine target must use the green button style")
        local tooltip = lib.globals.ui_state(player).tooltips.item_boxes[button.index]
        local machine_definition = tooltip[#tooltip][3]
        assert(machine_definition[1] == "fp.item_defined_by_machines", "The tooltip must describe a machine-defined target")
        assert(machine_definition[2] == "5", "The tooltip must show the configured count of five")
        assert(machine_definition[3][1] == "fp.pl_machine", "The tooltip must use the machine unit")
        assert(machine_definition[3][2] == 5, "The tooltip must pluralize using the configured count")
    end
end}

-- Research targets
tests.testResearchTargetRecipeSelection = {check=function(context)
    local player, factory, item = fixture(context)
    for _, proto in ipairs(SORTED_ITEMS.product) do
        if proto.name:find("^custom%-research%-") then
            item.proto = proto
            break
        end
    end
    assert(item.proto.type == "entity" and not item.proto.special, "Expected a research target")
    item.definition.amount = 1
    main_dialog.rebuild(player, false)
    compact_dialog.rebuild(player, false)
    local button = lib.globals.main_elements(player).item_boxes.product_item_table.children[1]
    assert(button.tags.flags.can_produce, "Research must have producing recipes")
    dispatch(player, button, defines.events.on_gui_click)

    if factory.top_floor:count() == 0 then
        local modal_data = lib.globals.modal_data(player)
        assert(modal_data and lib.globals.ui_state(player).modal_dialog_type == "recipe",
            "Clicking a research target must add its recipe or open the recipe picker")
        local choice
        for _, group in pairs(modal_data.modal_elements.groups) do
            for _, candidate in pairs(group.recipe_buttons) do
                if candidate.visible then choice = candidate; break end
            end
            if choice then break end
        end
        assert(choice, "The research picker must offer a recipe")
        dispatch(player, choice, defines.events.on_gui_click)
    end
    assert(factory.top_floor:count() == 1, "Selecting a research recipe must add one line")
    local line = factory.top_floor.first
    assert(line.recipe.proto.products[1].name == item.proto.name)
    assert(line.machine.proto.prototype_category == "lab", "Research recipes must use a lab")
end}

return tests
