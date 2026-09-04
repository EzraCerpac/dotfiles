local root = assert(os.getenv("GRAMMARLY_BRIDGE_TEST_ROOT"))
package.path = root .. "/dot_config/nvim/lua/?.lua;" .. package.path
local guard = require("custom.typst_guard")

local source = table.concat({
  "= Heading",
  "A citation @smith2024, equation $x^2$, code `x = 1`, URL https://example.test/a, and 42 numbers.",
  "The DOI 10.1234/example.567 must also stay exact.",
  "",
  '#import "shared.typ": helper',
  "#let answer = 42",
  "```typ",
  "#let fenced = 99",
  "```",
}, "\n")
local plan, chunks = guard.prepare(source, true)
assert(plan and #chunks == 1, "protected-only paragraphs must not be sent upstream")
assert(chunks[1].text:find("@smith2024", 1, true) == nil, "citation must be protected")
assert(chunks[1].text:find("⟦TYPST_GUARD_", 1, true), "protected placeholders must be visible")
assert(chunks[1].text:find("10.1234/example.567", 1, true) == nil, "DOIs must be protected")

local outputs = {}
for _, chunk in ipairs(chunks) do
  outputs[#outputs + 1] = { id = chunk.id, text = chunk.text:gsub("Heading", "Improved heading") }
end
local restored, err = guard.restore(plan, outputs)
assert(restored and not err, err)
assert(restored:find("@smith2024", 1, true) and restored:find("42", 1, true), "syntax and numbers must survive")
assert(restored:find("Improved heading", 1, true), "prose must reconstruct")

local bad = { { id = 1, text = chunks[1].text:gsub("⟦TYPST_GUARD_0001⟧", "⟦TYPST_GUARD_9999⟧") } }
assert(not guard.restore(plan, bad), "placeholder mismatch must fail closed")
local malformed, parse_error = guard.prepare("#let =", true)
assert(not malformed and parse_error:find("parse error"), "malformed Typst must fail closed")
assert(not guard.restore(plan, { { id = 1, text = chunks[1].text .. " $" } }), "syntax change must fail closed")
print("typst guard tests passed")
