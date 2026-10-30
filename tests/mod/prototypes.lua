---@diagnostic disable

local prototypes = {}

-- Fuel categories
do
    local helpers = require("helpers")
    local category_a, category_b, category_c = "test-fuel-a", "test-fuel-b", "test-fuel-c"
    local combined = category_a .. "|" .. category_b

    prototypes.fuel_categories = function()
            local deepcopy = require("util").table.deepcopy
            data:extend{
                {type="fuel-category", name=category_a},
                {type="fuel-category", name=category_b},
                {type="fuel-category", name=category_c},
                {type="recipe-category", name="test-fuel-crafting"},
                {type="recipe", name="test-fuel-gear", categories={"test-fuel-crafting"},
                    ingredients={{type="item", name="iron-plate", amount=2}},
                    results={{type="item", name="iron-gear-wheel", amount=1}}}
            }

            for suffix, categories in pairs{a={category_a}, b={category_b},
                ab={category_a, category_b}, c={category_c}} do
                local fuel = deepcopy(data.raw.item.coal)
                fuel.name = "test-fuel-" .. suffix
                fuel.fuel_categories = categories
                fuel.fuel_value = (suffix == "ab") and "8MJ" or "4MJ"
                local recipe = {type="recipe", name=fuel.name, categories={"crafting"},
                    ingredients={{type="item", name="coal", amount=1}},
                    results={{type="item", name=fuel.name, amount=1}}}

                local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])
                machine.name = "test-fuel-machine-" .. suffix
                machine.crafting_categories = {"test-fuel-crafting"}
                machine.energy_source = {type="burner", fuel_categories=categories, fuel_inventory_size=1}
                machine.fast_replaceable_group = nil
                machine.next_upgrade = nil
                data:extend{fuel, recipe, machine}
            end
        end
end

-- Input targets
do
    prototypes.input_targets = function()
            local deepcopy = require("util").table.deepcopy
            data:extend{{type="recipe-category", name="test-input-target"}}
            local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
            machine.name = "test-input-target-machine"
            machine.crafting_categories = {"test-input-target"}
            machine.crafting_speed = 1
            machine.energy_source = {type="electric", usage_priority="secondary-input", drain="0W"}
            machine.energy_usage = "100kW"
            machine.module_slots = 0
            machine.allowed_effects = nil
            machine.effect_receiver = nil
            machine.fast_replaceable_group = nil
            machine.next_upgrade = nil
            data:extend{machine}
            local function item(name, amount)
                return {type="item", name=name, amount=amount}
            end
            local function recipe(name, ingredients, results)
                data:extend{{type="recipe", name="test-input-target-" .. name, categories={"test-input-target"},
                    enabled=true, energy_required=1, ingredients=ingredients, results=results,
                    icon="__base__/graphics/icons/iron-plate.png", subgroup="intermediate-product",
                    auto_recycle=false, allow_productivity=false}}
            end
            recipe("plate", {item("iron-ore", 2)}, {item("iron-plate", 1)})
            recipe("copper", {item("copper-ore", 2)}, {item("copper-plate", 1)})
            recipe("gear", {item("iron-plate", 2)}, {item("iron-gear-wheel", 1)})
            recipe("consumer", {item("iron-plate", 1)}, {item("iron-gear-wheel", 1)})
            recipe("sink", {item("iron-ore", 2)}, {})
            recipe("steam", {{type="fluid", name="steam", amount=2, minimum_temperature=100}},
                {item("iron-plate", 1)})
        end
end

-- Machine requirements
do
    prototypes.machine_requirements = function()
            data:extend{{
                type="recipe", name="test-machine-requirements", enabled=true, energy_required=1, main_product="iron-plate",
                ingredients={{type="item", name="iron-ore", amount=1}},
                results={{type="item", name="iron-plate", amount=1}, {type="item", name="copper-plate", amount=1}}
            }}
            for _, temperature in ipairs{165, 500} do
                data:extend{{
                    type="recipe", name="test-machine-steam-" .. temperature, enabled=true,
                    categories={"crafting-with-fluid"}, energy_required=1,
                    ingredients={{type="item", name="iron-ore", amount=1}},
                    results={{type="fluid", name="steam", amount=1, temperature=temperature}}
                }}
            end
        end
end

-- Research
do
    -- Covers the research pseudo-recipes: setup defines science packs, labs and
    -- technologies, check asserts what the generator made of them.
    --
    -- Each lab input set buckets the technologies it can research (their packs a subset
    -- of the inputs) by time and amount profile: costs merge when they only differ in
    -- which amount-1 packs they use, distinct above-1 amounts stay apart. A recipe takes
    -- the packs its bucket's technologies actually use, at their real amounts, and
    -- produces the research item of its time. Sets no technology matches don't exist,
    -- and neither do items for times only they observe. Machine categories are keyed on
    -- the input set, so all buckets of one set share machines and defaults, and a lab
    -- joins every category whose set is a subset of its inputs. Recipes show their
    -- set's first lab by entity order as their icon; the items get the time-badged
    -- flask.
    --
    -- Times are chosen so no base technology shares one: base uses 5/10/15/30/35/45/60s,
    -- these use 17/19/23/31/47/150s. That keeps the absence assertions meaningful even
    -- though all cases load into the same game.
    --
    -- Coverage:
    --   tech-a       17s, packs 1+2+3      merges with tech-b: all amounts are 1
    --   tech-b       17s, pack 1           same time through a subset technology
    --   tech-amount2 17s, pack 1 amount 2  distinct amount profile, its own recipe
    --   tech-c       31s, pack 1           second time, reaching both sets via subset
    --   tech-union12 23s, packs 1+2        with tech-union13, neither set containing the
    --   tech-union13 23s, packs 1+3        other: the bucket's ingredients are the union
    --   tech-hidden  19s, pack 1           hidden technology, skipped
    --   tech-none    47s, hidden-lab pack  only a hidden lab takes it: no set, and its
    --                                      time doesn't exist for any set
    --   tech-minutes 150s, pack 1          minute formatting and icon path
    --   tech-trigger trigger-based         no science units at all, skipped

    local helpers = require("helpers")

    prototypes.research = function()
        local deepcopy = require("util").table.deepcopy

        -- ** SCIENCE PACKS **

        -- Item orders deliberately disagree with the name order (pack-2 sorts last),
        -- so the order-based ingredient sorting and sprite pick are provably not
        -- falling back to name order
        local packs = {}
        for suffix, order in pairs({["1"] = "test-a-1", ["2"] = "test-a-9",
                ["3"] = "test-a-3", ["none"] = "test-a-4", ["unused"] = "test-a-5"}) do
            local pack = deepcopy(data.raw.item["automation-science-pack"])
            pack.name = "test-research-pack-" .. suffix
            pack.order = order
            table.insert(packs, pack)
        end
        data:extend(packs)

        -- Non-neutral normal modifiers expose baselines that already include quality.
        -- Other machine calculations use a synthetic FP-quality object at runtime,
        -- since Factorio rejects additional qualities with the feature flag disabled.
        data.raw.quality.normal.science_pack_drain_multiplier = 0.5
        data.raw.quality.normal.lab_research_speed_multiplier = 1.5
        data.raw.quality.normal.lab_module_slots_bonus = 2

        -- ** LABS **

        local function test_lab(name, overrides)
            local lab = deepcopy(data.raw.lab.lab)
            lab.name = name
            lab.fast_replaceable_group = nil
            lab.next_upgrade = nil
            lab.inputs = {"test-research-pack-1", "test-research-pack-2", "test-research-pack-3"}
            for key, value in pairs(overrides) do lab[key] = value end
            return lab
        end

        data:extend{
            test_lab("test-research-lab-a", {researching_speed = 2}),
            test_lab("test-research-lab-b", {researching_speed = 1, science_pack_drain_rate_percent = 70}),
            test_lab("test-research-lab-quality-drain", {science_pack_drain_rate_percent = 70,
                uses_quality_drain_modifier = true, quality_affects_module_slots = true}),
            test_lab("test-research-lab-clamped-drain", {science_pack_drain_rate_percent = 1,
                uses_quality_drain_modifier = true}),
            test_lab("test-research-lab-restricted", {inputs = {"test-research-pack-1"}}),
            -- Visible, but no technology uses its only pack, so its set is dropped
            test_lab("test-research-lab-unused", {inputs = {"test-research-pack-unused"}}),
            -- One set shared by two labs whose entity order disagrees with their name
            -- order, so the recipe icon provably follows the order
            test_lab("test-research-lab-pair-a", {order = "b",
                inputs = {"test-research-pack-1", "test-research-pack-2"}}),
            test_lab("test-research-lab-pair-z", {order = "a",
                inputs = {"test-research-pack-1", "test-research-pack-2"}}),
            -- The game refuses to load a technology no lab at all accepts, so the
            -- unaccepted-pack scenario means acceptance by a hidden lab only
            test_lab("test-research-lab-hidden", {inputs = {"test-research-pack-none"}, hidden = true})
        }

        -- ** TECHNOLOGIES **

        local function test_tech(name, overrides)
            local tech = deepcopy(data.raw.technology["automation"])
            tech.name = name
            tech.prerequisites = nil
            tech.effects = nil
            tech.unit = {count = 10, time = 17,
                ingredients = {{"test-research-pack-1", 1}}}
            for key, value in pairs(overrides) do tech[key] = value end
            return tech
        end

        data:extend{
            test_tech("test-research-tech-a", {
                effects = {{type = "laboratory-productivity", modifier = 0.1}},
                unit = {count = 10, time = 17, ingredients = {
                    {"test-research-pack-1", 1}, {"test-research-pack-2", 1},
                    {"test-research-pack-3", 1}}}
            }),
            test_tech("test-research-tech-b", {}),
            test_tech("test-research-tech-amount2", {unit = {count = 10, time = 17, ingredients = {
                {"test-research-pack-1", 2}}}}),
            test_tech("test-research-tech-c", {unit = {count = 10, time = 31, ingredients = {
                {"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-union12", {unit = {count = 10, time = 23, ingredients = {
                {"test-research-pack-1", 1}, {"test-research-pack-2", 1}}}}),
            test_tech("test-research-tech-union13", {unit = {count = 10, time = 23, ingredients = {
                {"test-research-pack-1", 1}, {"test-research-pack-3", 1}}}}),
            test_tech("test-research-tech-hidden", {hidden = true,
                unit = {count = 10, time = 19, ingredients = {{"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-none", {unit = {count = 10, time = 47, ingredients = {
                {"test-research-pack-none", 1}}}}),
            test_tech("test-research-tech-minutes", {unit = {count = 10, time = 150,
                ingredients = {{"test-research-pack-1", 1}}}}),
            test_tech("test-research-tech-trigger", {unit = nil,
                research_trigger = {type = "craft-item", item = "iron-plate", count = 1}})
        }
    end
end

-- Sequential chain
do
    prototypes.sequential_chain = function()
            local deepcopy = require("util").table.deepcopy

            local function test_item(name, base)
                local item = deepcopy(data.raw.item[base])
                item.name = name
                return item
            end

            data:extend{
                test_item("test-solver-ore", "iron-ore"),
                test_item("test-solver-plate", "iron-plate"),
                test_item("test-solver-gear", "iron-gear-wheel"),
                test_item("test-solver-slag", "stone"),
                {
                    type = "recipe-category",
                    name = "test-solver"
                },
                {
                    type = "recipe",
                    name = "test-solver-plate",
                    categories = {"test-solver"},
                    enabled = true,
                    energy_required = 0.5,
                    ingredients = {{type = "item", name = "test-solver-ore", amount = 2}},
                    results = {{type = "item", name = "test-solver-plate", amount = 1}}
                },
                {
                    type = "recipe",
                    name = "test-solver-gear",
                    categories = {"test-solver"},
                    enabled = true,
                    energy_required = 1,
                    ingredients = {{type = "item", name = "test-solver-plate", amount = 2}},
                    results = {{type = "item", name = "test-solver-gear", amount = 1}}
                }
            }

            local coproduct_recipe = deepcopy(data.raw.recipe["test-solver-plate"])
            coproduct_recipe.name = "test-solver-plate-with-slag"
            coproduct_recipe.main_product = "test-solver-plate"
            table.insert(coproduct_recipe.results, {type="item", name="test-solver-slag", amount=1})
            data:extend{coproduct_recipe}

            local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
            machine.name = "test-solver-machine"
            machine.crafting_categories = {"test-solver"}
            machine.crafting_speed = 1
            machine.energy_usage = "100kW"
            -- Drain is zeroed explicitly, since crafting machines otherwise default to usage / 30
            machine.energy_source = {type = "electric", usage_priority = "secondary-input", drain = "0W"}
            machine.module_slots = 0
            machine.allowed_effects = nil
            machine.effect_receiver = nil
            machine.fast_replaceable_group = nil
            machine.next_upgrade = nil

            data:extend{machine}
        end
end

-- Target items
do
    prototypes.target_items = function()
        local item = require("util").table.deepcopy(data.raw.item["iron-plate"])
        item.name = "test-spawnable-input"
        item.flags = {"spawnable"}
        data:extend{item, {
            type="recipe", name="test-spawnable-input", enabled=true, energy_required=1,
            ingredients={{type="item", name=item.name, amount=1}},
            results={{type="item", name="iron-plate", amount=1}}
        }}
    end
end

return prototypes
