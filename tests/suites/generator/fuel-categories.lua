---@diagnostic disable

local helpers = require("helpers")
local category_a, category_b, category_c = "test-fuel-a", "test-fuel-b", "test-fuel-c"
local combined = category_a .. "|" .. category_b

return {check=function()
    local find = prototyper.util.find
    for _, category in ipairs{category_a, category_b, combined} do
        assert(find("fuels", "test-fuel-ab", category), "Shared fuel must fit " .. category)
        assert(not find("fuels", "test-fuel-c", category), "Unrelated fuel must not fit " .. category)
    end
    assert(table_size(find("fuels", nil, combined).members) == 3,
        "Overlapping categories must not duplicate fuels")
    assert(not find("fuels", "test-fuel-a", category_b), "A-only fuel must not fit B")
    assert(not find("fuels", "test-fuel-b", category_a), "B-only fuel must not fit A")
end}
