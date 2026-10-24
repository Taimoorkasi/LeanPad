local wow = require("spec.wow")

-- Bindings.xml is loaded by the client, not the TOC; read it and run each binding body against the fake API.
local function bindings()
	local xml = io.open("LeanPad/Bindings.xml"):read("*a")
	local found = {}
	for attributes, body in xml:gmatch("<Binding ([^>]*)>(.-)</Binding>") do
		local binding = { body = body }
		for key, value in attributes:gmatch('(%w+)="([^"]*)"') do binding[key] = value end
		found[binding.name] = binding
	end
	return found
end

describe("Bindings.xml", function()
	local w
	before_each(function() _, w = wow.boot(nil) end)
	after_each(wow.restore)

	it("offers a gamepad cursor toggle under AddOns > LeanPad, named for the key binding list", function()
		local toggle = bindings().LEANPAD_TOGGLE_CURSOR
		assert.equal("ADDONS", toggle.category)
		assert.equal("LEANPAD", toggle.header)
		assert.equal("LeanPad", BINDING_HEADER_LEANPAD)
		assert.equal("Toggle gamepad cursor", BINDING_NAME_LEANPAD_TOGGLE_CURSOR)
	end)

	it("names every binding it defines", function()
		for name in pairs(bindings()) do
			assert.is_string(_G["BINDING_NAME_" .. name], name)
		end
	end)

	it("toggles Blizzard's gamepad cursor control", function()
		local run = assert(loadstring(bindings().LEANPAD_TOGGLE_CURSOR.body))
		run()
		assert.is_true(w.cursorControl)
		run()
		assert.is_false(w.cursorControl)
	end)

end)
