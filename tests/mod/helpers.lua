---@diagnostic disable

-- Shared helpers for test cases

local helpers = {}

-- Collects failures instead of aborting on the first one, so a single run reports every mismatch
function helpers.collector()
    local failures = {}

    return {
        check = function(condition, message)
            if not condition then table.insert(failures, message) end
        end,
        equal = function(actual, expected, label)
            if actual ~= expected then
                failures[#failures + 1] = label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
            end
        end,
        close = function(actual, expected, label)
            if not helpers.approx(actual, expected) then
                failures[#failures + 1] = label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
            end
        end,
        done = function()
            if #failures > 0 then
                error(string.format("%d checks failed:\n    ", #failures)
                    .. table.concat(failures, "\n    "), 0)
            end
        end
    }
end

-- True if the two numbers are equal up to floating point noise
function helpers.approx(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) <= 1e-6 * math.max(1, math.abs(b))
end

-- Machines are filed under combined category names, so a lookup by the original
-- category only works when some recipe uses exactly that one. Scanning by name
-- sidesteps that; the proto's own .category field carries the original category.
function helpers.find_machine(name)
    for _, category in pairs(storage.prototypes.machines) do
        for _, member in pairs(category.members) do
            if member.name == name then return member end
        end
    end
end

-- Checks one machine's category, speed, fuel category, and further burner fields
function helpers.check_machine(c, name, expected)
    local proto = helpers.find_machine(name)
    if not proto then
        c.check(false, name .. ": machine missing entirely")
        return nil
    end

    if expected.category then
        c.check(proto.category == expected.category, string.format(
            "%s: expected category %s, got %s", name, expected.category, proto.category))
    end
    if expected.speed then
        c.check(helpers.approx(proto.speed, expected.speed),
            string.format("%s: expected speed %g, got %g", name, expected.speed, proto.speed))
    end
    if expected.fuel_category then
        c.check(proto.burner ~= nil and proto.burner.categories[expected.fuel_category] ~= nil,
            name .. ": missing fuel category " .. expected.fuel_category)
    end
    for key, value in pairs(expected.burner or {}) do
        local actual = proto.burner and proto.burner[key]
        -- Prototype values can pass through 32-bit floats, so compare numbers loosely
        local matches = (type(value) == "number") and helpers.approx(actual, value) or (actual == value)
        c.check(matches, string.format("%s: burner.%s expected %s, got %s",
            name, key, tostring(value), tostring(actual)))
    end

    return proto
end

-- GUI lookup and event dispatch
do
    local gui = {}

    function gui.find(root, tags)
        local found
        local function visit(element)
            local matches = true
            for key, value in pairs(tags) do
                if element.tags[key] ~= value then matches = false; break end
            end
            if matches then
                assert(not found, "Ambiguous GUI element: " .. serpent.line(tags))
                found = element
            end
            for _, child in pairs(element.children) do visit(child) end
        end
        visit(root)
        return found
    end

    function gui.require(root, tags)
        local element = gui.find(root, tags)
        assert(element, "Missing GUI element: " .. serpent.line(tags))
        return element
    end

    function gui.dispatch(player, element, event_name, overrides)
        assert(element and element.valid, "Cannot dispatch to a missing GUI element")
        local event = {name=event_name, tick=game.tick, player_index=player.index, element=element,
            button=defines.mouse_button_type.left, control=false, alt=false, shift=false,
            cursor_display_location={x=0, y=0}}
        for key, value in pairs(overrides or {}) do event[key] = value end
        lib.globals.ui_state(player).last_action = nil
        local handler = assert(script.get_event_handler(event_name), "Missing GUI event handler")
        handler(event)
    end

    function gui.click(player, element, overrides)
        gui.dispatch(player, element, defines.events.on_gui_click, overrides)
    end

    helpers.gui = gui
end

return helpers
