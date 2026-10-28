---@diagnostic disable

local configurations = {}
do
    local case = require("suite.generators")
    configurations[#configurations + 1] = {name="generators", setup={case.setup}, cases={testGeneratorPrototypes=case}}
end
do
    local case = require("suite.boilers")
    configurations[#configurations + 1] = {name="boilers", setup={case.setup}, cases={testBoilerPrototypes=case}}
end
do
    local case = require("suite.fluid-energy")
    configurations[#configurations + 1] = {name="fluid-energy", setup={case.setup}, cases={testFluidEnergyPrototypes=case}}
end
do
    local case = require("suite.fuel-categories")
    configurations[#configurations + 1] = {name="fuel-categories", setup={require("prototypes").fuel_categories}, cases={testFuelCategories=case}}
end
do
    local case = require("suite.quality")
    configurations[#configurations + 1] = {name="quality", setup={case.setup}, cases={testQualityBaselines=case}}
end
do
    local case = require("suite.item-recipes")
    configurations[#configurations + 1] = {name="item-recipes", setup={case.setup}, cases={testItemRecipeEligibility=case}}
end
do
    local case = require("suite.research-durability")
    configurations[#configurations + 1] = {name="research-durability", setup={case.setup}, cases={testResearchDurability=case}}
end
configurations[#configurations + 1] = {name="research", setup={require("prototypes").research}, cases=require("suite.research")}
return configurations
