---@diagnostic disable

local tests = {}

-- Expression fields
do
    local helpers = require("helpers")

    tests.expressions = {
        check = function()
            local c = helpers.collector()
            local field = game.players[1].gui.screen.add{type="textfield"}

            for _, text in ipairs{"1/0", "-1/0", "0/0", "10^400", "", "1+"} do
                for _, positive in ipairs{false, true} do
                    field.text = text
                    c.check(lib.gui.parse_expression_field(field, positive) == nil,
                        "Reject invalid expression: " .. text)
                    c.check(not lib.gui.confirm_expression_field(field, positive) and field.text == text,
                        "Invalid expressions must remain unconfirmed and unchanged: " .. text)
                end
            end

            for _, case in ipairs{
                {"2*(3+4)", true, 14},
                {"1.5k+2M", true, 2001500},
                {"1/4", true, 0.25},
                {"10^308", true, 1e308},
                {"0", false, 0},
                {"-5", false, -5},
                {"0", true, nil},
                {"-5", true, nil}
            } do
                field.text = case[1]
                c.check(lib.gui.parse_expression_field(field, case[2]) == case[3],
                    "Preserve finite expression validation: " .. case[1])
            end

            field.destroy()
            c.done()
        end
    }
end

-- Default prototypes
do
    tests.defaults = {
        lookup = {check=function()
            local player = game.players[1]
            local player_table = lib.globals.player_table(player)
            player_table.preferences.default_prototypes = {
                pumps=defaults.get_fallback("pumps"), wagons=defaults.get_fallback("wagons")
            }
            local saved = player_table.preferences.default_prototypes
            local pump = defaults.get(player, "pumps")
            assert(defaults.get_optional(player, "pumps") == pump, "A usable default must be returned unchanged")
            local cargo = prototyper.util.find("wagons", nil, "cargo-wagon")
            local cargo_default = defaults.get(player, "wagons", cargo.id)
            assert(defaults.get_optional(player, "wagons", "cargo-wagon") == cargo_default)
            assert(defaults.get_optional(player, "wagons", cargo.id) == cargo_default)
            assert(defaults.get_optional(player, "wagons", "missing-category") == nil)
            assert(defaults.get_optional(player, "wagons", #storage.prototypes.wagons + 1) == nil)
            assert(defaults.get_optional(player, "wagons") == nil, "A category collection is not a prototype default")

            saved.pumps = {}
            saved.wagons[cargo.id] = {}
            assert(defaults.get_optional(player, "pumps") == nil)
            assert(defaults.get_optional(player, "wagons", cargo.id) == nil)
            assert(defaults.get(player, "pumps") == saved.pumps, "Existing callers must still be able to read empty entries")
            saved.wagons[cargo.id] = nil
            assert(defaults.get_optional(player, "wagons", "cargo-wagon") == nil)
        end}
    }
end

-- Research effects
do
    tests.research = {check=function(context)
        local force = context.player.force
        context.set(force, "laboratory_productivity_bonus", 0.125)
        assert(lib.effects.get_recipe_productivity(force, "custom-research") == 1250,
            "Expected the 12.5% lab bonus at effect precision")
    end}
end

return tests
