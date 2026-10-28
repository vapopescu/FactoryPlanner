---@diagnostic disable
local formatters = require("suite.formatters")
local utilities = require("suite.utilities")
return {{name="normal", cases={
    testResearchProductivityEffect = utilities.research,
    testDefaultsLookup = utilities.defaults.lookup,
    testLibExpressions = utilities.expressions,
    testLibFormatNumber = formatters.number,
    testLibFormatSIValue = formatters.SI_value,
    testLibFormatSpecialAmount = formatters.special_amount,
    testLibFormatButtonNumber = formatters.button_number,
    testLibFormatMachineAmount = formatters.machine_amount
}}}
