---@diagnostic disable
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

return {
    testResearchRecipes = {check=function(context)
        local c = helpers.collector()
        local find = prototyper.util.find
        -- One recipe per lab input set and observed cost bucket
        local function check_recipe(signature, ticks, category)
            local name = "impostor-research-" .. signature .. "-" .. ticks
            local proto = find("recipes", name)
            if not proto then
                c.check(false, name .. ": missing")
                return nil
            end
            c.check(proto.categories[category] ~= nil, name .. ": missing category " .. category)
            return proto
        end

        local multi = check_recipe(multi_set, 1020, multi_category)
        local single = check_recipe(single_set, 1020, single_category)
        local slow = check_recipe(single_set, 1860, single_category)
        -- Subset technologies reach bigger sets: 31s comes from a pack-1-only tech
        local multi_slow = check_recipe(multi_set, 1860, multi_category)
        -- The amount-2 technology is its own bucket in both sets
        local amount2 = check_recipe(single_set, "1020-test-research-pack-1-2", single_category)
        local multi_amount2 = check_recipe(multi_set, "1020-test-research-pack-1-2", multi_category)

        -- Same time, two technologies whose packs contain neither the other
        local union_multi = check_recipe(multi_set, 1380, multi_category)
        local union_pair = check_recipe(pair_set, 1380, pair_category)
        local minutes = check_recipe(single_set, 9000, single_category)
        local multi_minutes = check_recipe(multi_set, 9000, multi_category)

        -- Base's 15s only comes from technologies using none of the test packs
        c.check(find("recipes", "impostor-research-" .. single_set .. "-900") == nil,
            "single: time generated from a base technology matching no test pack")
        -- Neither 23s technology fits the single-pack set, so it has no such bucket
        c.check(find("recipes", "impostor-research-" .. single_set .. "-1380") == nil,
            "single: 23s offered despite accepting neither union technology")
        c.check(find("recipes", "impostor-research-" .. single_set .. "-1140") == nil,
            "single: hidden technology was offered")
        c.check(find("recipes", "impostor-research-" .. unused_set .. "-9000") == nil,
            "unused: recipe generated for a set matching no technologies")

        if multi then
            -- research_unit_energy is given in ticks: a 17s tech must yield 17, not 1020
            c.check(multi.energy == 17, "multi: expected energy 17, got " .. multi.energy)
            -- Labs a and b tie on entity order, so the name decides the recipe icon
            c.check(multi.sprite == "entity/test-research-lab-a",
                "multi: expected lab-a's entity icon, got " .. multi.sprite)
            -- tech-a's three packs merged with tech-b's one, all at amount 1
            c.check(#multi.ingredients == 3, "multi: expected the bucket's three packs")
            -- Ingredients follow item order (1, 3, 2), not name order
            c.check(multi.ingredients[2].name == "test-research-pack-3"
                and multi.ingredients[3].name == "test-research-pack-2",
                "multi: expected ingredients sorted by item order")
            -- The name counts the recipe's own packs, not the whole lab input set
            c.check(multi.localised_name[2] == 3, "multi: expected a pack count of 3 in the name")
            c.check(multi.localised_name[3] == 17 and multi.localised_name[4][1] == "fp.unit_second",
                "multi: expected a 17-second localised name")
            c.check(multi.allowed_effects.productivity and multi.allowed_effects.speed,
                "multi: modules must be allowed, gated by the lab entity instead")
            c.check(multi.productivity_recipe == "custom-research",
                "multi: missing the force-wide research productivity key")
        end
        if single then
            -- The amount-2 technology sits in its own bucket, not here
            c.check(single.ingredients[1].amount == 1, "single: expected ingredient amount 1")
            c.check(single.sprite == "entity/test-research-lab-restricted",
                "single: expected the restricted lab's entity icon, got " .. single.sprite)
        end
        if amount2 then
            c.check(#amount2.ingredients == 1 and amount2.ingredients[1].amount == 2,
                "amount2: expected the single pack at amount 2")
        end
        if multi_amount2 then
            -- Buckets take only the packs their technologies use, so this one matches
            -- the amount-2 cost exactly despite living in the full set's category
            c.check(#multi_amount2.ingredients == 1
                and multi_amount2.ingredients[1].name == "test-research-pack-1"
                and multi_amount2.ingredients[1].amount == 2,
                "multi-amount2: expected only the single pack at amount 2")
            c.check(multi_amount2.localised_name[2] == 1,
                "multi-amount2: expected a pack count of 1 in the name")
        end
        if union_multi then
            -- Packs 1+2 and 1+3 at one time merge into a single bucket taking all three
            c.check(#union_multi.ingredients == 3,
                "union-multi: expected the union of both technologies' packs")
        end
        if union_pair then
            -- The same time in a set that accepts only one of the two technologies
            c.check(#union_pair.ingredients == 2
                and union_pair.ingredients[1].name == "test-research-pack-1"
                and union_pair.ingredients[2].name == "test-research-pack-2",
                "union-pair: expected only the packs this set accepts")
            -- pair-z sorts last by name but first by entity order, which is what counts
            c.check(union_pair.sprite == "entity/test-research-lab-pair-z",
                "union-pair: expected the lower-ordered lab's icon, got " .. union_pair.sprite)
        end
        if multi_slow then
            c.check(#multi_slow.ingredients == 1 and multi_slow.ingredients[1].amount == 1,
                "multi-slow: expected only the 31s technology's single pack")
        end
        if minutes then
            c.check(minutes.localised_name[3] == "2.5"
                    and minutes.localised_name[4][1] == "fp.unit_minute",
                "minutes: expected a 2.5-minute localised name")
        end
        if single and slow then
            c.check(single.order < slow.order, "single: recipes must order by ascending time")
        end
        if single and multi then
            c.check(single.order < multi.order, "single: smaller pack set must order first")
        end

        -- Every research recipe produces the research item of its time
        for _, pair in ipairs({{multi, 1020}, {single, 1020}, {slow, 1860},
                {multi_slow, 1860}, {amount2, 1020}, {multi_amount2, 1020},
                {union_multi, 1380}, {union_pair, 1380}, {minutes, 9000},
                {multi_minutes, 9000}}) do
            local recipe, ticks = pair[1], pair[2]
            if recipe then
                c.check(recipe.products[1].name == "custom-research-" .. ticks
                    and recipe.products[1].amount == 1,
                    recipe.name .. ": expected 1 custom-research-" .. ticks .. " as product")
            end
        end

        -- The hidden lab creates no set, and its 47s doesn't exist for any set.
        -- Trigger technologies have no science units, which would show up as an
        -- ingredient-less recipe (and crash the solver's minimum_energy handling as a
        -- free product).
        for _, recipe_proto in pairs(storage.prototypes.recipes) do
            local name = recipe_proto.name
            if name:find("^impostor%-research%-") then
                c.check(not name:find("test%-research%-pack%-none"),
                    "hidden lab's set offered anyway: " .. name)
                c.check(not name:find("%-2820$"), "hidden lab's time offered anyway: " .. name)
                c.check(not name:find("%-1140$"), "hidden technology's time offered anyway: " .. name)
                c.check(not name:find("test%-research%-pack%-unused"),
                    "unused lab's set offered anyway: " .. name)
                c.check(#recipe_proto.ingredients > 0, "research recipe without ingredients: " .. name)
            end
        end
        c.done()
    end},
    testResearchItems = {check=function(context)
        local c = helpers.collector()
        local find = prototyper.util.find
        -- One research item per observed time, living in the dedicated research
        -- group; the pack sets exist only as recipes
        for _, ticks in ipairs({1020, 1380, 1860, 9000}) do
            local item = find("items", "custom-research-" .. ticks, "entity")
            if item then
                c.check(item.type == "entity" and item.hidden == false
                    and item.fixed_unit == nil and lib.availability.has_productive_recipe(item, "produce"),
                    "item: expected a visible entity item without a fixed unit")
                c.check(item.group.name == prototypes.item_subgroup["science-pack"].group.name
                    and item.subgroup.name == "fp_research",
                    "item: expected the science packs' group and the fake fp_research subgroup")
                c.check(item.sprite == "fp_research_" .. ticks,
                    "item: expected the composed time icon, got " .. item.sprite)
            else
                c.check(false, "item: missing the research item for " .. ticks)
            end
        end
        c.check(find("items", "custom-research", "entity") == nil,
            "item: time-less item created despite the per-time model")
        c.check(find("items", "custom-research-" .. single_set, "entity") == nil,
            "item: per-set item created despite the per-time model")
        -- The hidden lab's 47s is observed by no usable set, so its item doesn't exist
        c.check(find("items", "custom-research-2820", "entity") == nil,
            "item: hidden lab's time got an item anyway")
        c.check(find("items", "custom-research-1140", "entity") == nil,
            "item: hidden technology's time got an item anyway")

        local minute_item = find("items", "custom-research-9000", "entity")
        if minute_item then
            c.check(minute_item.localised_name[2] == "2.5"
                    and minute_item.localised_name[3][1] == "fp.unit_minute",
                "item: expected a 2.5-minute localised name")
        end
        c.done()
    end},
    testResearchLabCategories = {check=function(context)
        local c = helpers.collector()
        local find = prototyper.util.find
        for _, lab_name in ipairs({"test-research-lab-a", "test-research-lab-b"}) do
            local categories = lab_categories(lab_name)
            c.check(categories[single_category] ~= nil and categories[multi_category] ~= nil,
                lab_name .. ": expected membership in both research categories")
        end
        local restricted = lab_categories("test-research-lab-restricted")
        c.check(restricted[single_category] ~= nil, "restricted lab: missing its single-pack category")
        c.check(restricted[multi_category] == nil, "restricted lab: joined a category it can't research")
        c.check(next(lab_categories("test-research-lab-unused")) == nil,
            "unused lab: generated despite its set matching no technologies")

        local lab_a = lab_categories("test-research-lab-a")[single_category]
        if lab_a then
            c.check(lab_a.prototype_category == "lab", "lab-a: expected prototype_category lab")
            c.check(helpers.approx(lab_a.speed, 2), "lab-a: expected researching speed 2")
            c.check(helpers.approx(lab_a.resource_drain_rate, 1), "lab-a: expected drain rate 1")
        end
        local lab_b = lab_categories("test-research-lab-b")[single_category]
        if lab_b then
            c.check(helpers.approx(lab_b.speed, 1), "lab-b: expected researching speed 1")
            c.check(helpers.approx(lab_b.resource_drain_rate, 0.7), "lab-b: expected drain rate 0.7")
        end
        c.done()
    end},
}
