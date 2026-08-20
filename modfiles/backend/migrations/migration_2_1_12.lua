---@diagnostic disable

local SimpleItem = require("backend.data.SimpleItem")

local migration = {}

function migration.player_table(player_table)
    for district in player_table.realm:iterator() do
        for factory in district:iterator() do
            if factory.matrix_free_items then
                for _, item_proto in ipairs(factory.matrix_free_items) do
                    --- Avoid constructor to mitigate breaking dependencies
                    local simple_item = {
                        class = "SimpleItem",
                        proto = item_proto,
                        amount = 0
                    }
                    setmetatable(simple_item, SimpleItem)
                    item_proto = simple_item
                end
            end
        end
    end
end

function migration.packed_factory(packed_factory)
    if packed_factory.matrix_free_items then
        for _, packed_item_proto in ipairs(packed_factory.matrix_free_items) do
            local packed_simple_item = {
                class = "SimpleItem",
                proto = packed_item_proto,
                amount = 0
            }
            packed_item_proto = packed_simple_item
        end
    end
end

return migration
