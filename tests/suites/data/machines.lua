---@diagnostic disable

local tests = {}

-- Machine requirement persistence
do
    local machine_fixture = require("fixtures").machine
    tests.packing = {check=function(context)
        local f = machine_fixture(context)
        solver.update(f.player, f.factory)
        assert(f.first:pack(false).machine_requirement == nil, "Factory packing must omit the calculated machine requirement")
        assert(f.first:pack(true).machine_requirement == nil, "Clipboard packing must omit the calculated machine requirement")
    end}
end

-- Research machine calculations
do
    local helpers = require("helpers")

    local single_set = "test-research-pack-1"
    local pair_set = "test-research-pack-1-test-research-pack-2"
    local multi_set = "test-research-pack-1-test-research-pack-2-test-research-pack-3"
    local unused_set = "test-research-pack-unused"
    local single_category = "research-" .. single_set
    local pair_category = "research-" .. pair_set
    local multi_category = "research-" .. multi_set

    local function lab_categories(name)
        local categories = {}
        for _, category in pairs(storage.prototypes.machines) do
            for _, member in pairs(category.members) do
                if member.name == name then categories[member.category] = member end
            end
        end
        return categories
    end

    tests.research = {check=function(context)
        local c = helpers.collector()
        local find = prototyper.util.find
        -- Exercise the runtime Machine calculations without involving any solver.
        local normal_quality = find("qualities", "normal")
        c.check(helpers.approx(normal_quality.science_pack_drain_multiplier, 0.5),
            "quality: science-pack drain multiplier was not preserved")
        local test_quality = {
            name = "synthetic-research-quality",
            lab_research_speed_multiplier = 1.6,
            science_pack_drain_multiplier = 0.5,
            lab_module_slots_bonus = 3
        }

        local function calculated_lab(name)
            local proto = lab_categories(name)[multi_category]
            if not proto then c.check(false, name .. ": missing machine"); return nil end
            local machine = context.classes.Machine.init({}, proto)
            c.check(helpers.approx(machine:get_speed(),
                    prototypes.entity[name].get_researching_speed("normal")),
                name .. ": normal research multiplier was counted twice")
            c.check(machine.proto.module_limit == 2,
                name .. ": expected two raw module slots")
            c.check(machine:get_module_limit() == prototypes.entity[name].module_inventory_size,
                name .. ": normal module slot bonus was counted twice")
            machine.quality_proto = test_quality
            return machine
        end
        local lab_b_calculated = calculated_lab("test-research-lab-b")
        local quality_lab_calculated = calculated_lab("test-research-lab-quality-drain")
        local clamped_lab_calculated = calculated_lab("test-research-lab-clamped-drain")

        if lab_b_calculated then
            c.check(helpers.approx(lab_b_calculated:get_speed(), 1.6),
                "lab-b: expected quality to multiply researching speed")
            c.check(helpers.approx(lab_b_calculated:get_resource_drain_rate(), 0.7),
                "lab-b: quality drain modifier should be ignored")
            c.check(lab_b_calculated:get_module_limit() == lab_b_calculated.proto.module_limit,
                "lab-b: quality added slots without the opt-in flag")
            c.check(helpers.approx(lab_b_calculated:get_energy_usage(),
                    lab_b_calculated.proto.energy_usage),
                "lab-b: quality unexpectedly changed lab energy usage")
        end
        if quality_lab_calculated then
            c.check(helpers.approx(quality_lab_calculated:get_resource_drain_rate(), 0.35),
                "quality-drain lab: expected an above-floor drain rate of 0.35")
            c.check(quality_lab_calculated:get_module_limit() == 5,
                "quality-drain lab: expected three quality module slots")
        end
        if clamped_lab_calculated then
            c.check(helpers.approx(clamped_lab_calculated:get_resource_drain_rate(), 0.01),
                "clamped-drain lab: expected the minimum drain rate of 0.01")
        end

        c.check(PRODUCTIVITY_RECIPES["custom-research"] == true,
            "custom-research missing from PRODUCTIVITY_RECIPES")
        c.done()
    end}
end

-- Fuel selection and defaults
do
    local helpers = require("helpers")
    local category_a, category_b, category_c = "test-fuel-a", "test-fuel-b", "test-fuel-c"
    local combined = category_a .. "|" .. category_b

    tests.fuels = {check=function(context)
        local find = prototyper.util.find
        local player = context.player
        lib.globals.player_table(player).preferences.default_prototypes = {fuels=defaults.get_fallback("fuels")}
        defaults.set(player, "fuels", {prototype="test-fuel-a"}, category_a)
        defaults.set(player, "fuels", {prototype="test-fuel-b"}, category_b)
        defaults.set(player, "fuels", {prototype="test-fuel-ab"}, combined)

        local line = context.classes.Line.init(find("recipes", "test-fuel-gear"))
        local function change_machine(suffix)
            line:change_machine_to_proto(player, helpers.find_machine("test-fuel-machine-" .. suffix))
            return line.machine.fuel
        end

        local fuel = change_machine("ab")
        assert(fuel.proto.name == "test-fuel-ab", "New machine must use its combination's default")
        for _, suffix in ipairs{"a", "b", "ab"} do
            assert(change_machine(suffix) == fuel, "Switching compatible machines must retain the fuel object")
            assert(fuel.proto == find("fuels", "test-fuel-ab", line.machine.proto.burner.combined_category),
                "Switching must use the destination category's fuel prototype")
        end
        local filter = line.machine:compile_fuel_filter()
        assert(#filter[1].name == 3, "Picker must offer each compatible fuel once")

        -- Validation must also retain a shared fuel across category changes
        for _, suffix in ipairs{"b", "a", "ab"} do
            line.machine.proto = helpers.find_machine("test-fuel-machine-" .. suffix)
            assert(fuel:validate(player), "Shared fuel must validate in " .. suffix)
            assert(fuel.proto.combined_category == line.machine.proto.burner.combined_category)
        end
        line.machine.proto = helpers.find_machine("test-fuel-machine-c")
        assert(not fuel:validate(player), "Unrelated fuel must fail validation")
        assert(change_machine("c").proto.name == "test-fuel-c", "Incompatible fuel must use the new default")

        defaults.set_all(player, "fuels", {prototype="test-fuel-ab"})
        for _, category in ipairs{category_a, category_b, combined} do
            assert(defaults.get(player, "fuels", category).proto.name == "test-fuel-ab",
                "Save for all must update every compatible combination")
        end
        assert(defaults.get(player, "fuels", category_c).proto.name == "test-fuel-c",
            "Save for all must preserve unrelated defaults")
    end}
end

return tests
