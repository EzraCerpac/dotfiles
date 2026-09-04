local root = assert(os.getenv("GRAMMARLY_BRIDGE_TEST_ROOT"))
local guard = dofile(root .. "/dot_config/nvim/lua/custom/typst_guard.lua")

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

local structured = table.concat({
  '#section("introduction")[',
  "  = Introduction <ch:introduction>",
  "  #outline[",
  "    - A solver can change action.",
  "    #chapter-contract(",
  "      [Can changing action save work?],",
  "    )",
  "  ]",
  "]",
}, "\n")
local structured_plan, structured_chunks = guard.prepare(structured, true)
assert(structured_plan and #structured_chunks == 1, "structural lines must stay protected inside the prose chunk")
for _, chunk in ipairs(structured_chunks) do
  assert(not chunk.text:find("#section", 1, true), "command lines must be protected")
  assert(not chunk.text:find("#outline", 1, true), "container lines must be protected")
  assert(not chunk.text:match("^%s*=+%s"), "heading prefixes must be protected")
  assert(not chunk.text:match("^%s*[-+]%s"), "list prefixes must be protected")
end
local structured_outputs = {}
for _, chunk in ipairs(structured_chunks) do
  structured_outputs[#structured_outputs + 1] = { id = chunk.id, text = chunk.text }
end
local structured_result, structured_error = guard.restore(structured_plan, structured_outputs)
assert(structured_result and not structured_error, structured_error)
assert(structured_result == structured, "structural Typst must round-trip exactly")

local shorthand_source = "#prose[\n  A direction--globalization recipe.\n]"
local shorthand_plan, shorthand_chunks = guard.prepare(shorthand_source, true)
assert(shorthand_plan and #shorthand_chunks == 1)
local shorthand_output = shorthand_chunks[1].text:gsub("direction%-%-globalization", "direction and globalization")
local shorthand_result, shorthand_error = guard.restore(
  shorthand_plan,
  { { id = shorthand_chunks[1].id, text = shorthand_output } }
)
assert(shorthand_result and not shorthand_error, shorthand_error)

local emphasis_source = "#outline[\n  - *Stage:* explanation with _emphasis_.\n]"
local emphasis_plan, emphasis_chunks = guard.prepare(emphasis_source, true)
assert(emphasis_plan and #emphasis_chunks == 1)
assert(not emphasis_chunks[1].text:find("*", 1, true), "strong markers must be protected")
assert(not emphasis_chunks[1].text:find("_emphasis_", 1, true), "emphasis markers must be protected")
local emphasis_result, emphasis_error = guard.restore(
  emphasis_plan,
  { { id = emphasis_chunks[1].id, text = emphasis_chunks[1].text:gsub("explanation", "clear explanation") } }
)
assert(emphasis_result and not emphasis_error, emphasis_error)

local quote_source = "#prose[\n  The solver's retained work.\n]"
local quote_plan, quote_chunks = guard.prepare(quote_source, true)
assert(quote_plan and #quote_chunks == 1)
local quote_output = quote_chunks[1].text:gsub("solver's retained", "solver retained")
local quote_result, quote_error = guard.restore(
  quote_plan,
  { { id = quote_chunks[1].id, text = quote_output } }
)
assert(quote_result and not quote_error, quote_error)

local display_math_source = table.concat({
  "#prose[",
  "  Equation follows.",
  "]",
  "",
  "$",
  "  E(u)",
  "  arrow.r bold(x)_d = phi(z_d)",
  "$",
  "",
  "#prose[",
  "  Text continues.",
  "]",
}, "\n")
local display_math_plan, display_math_chunks = guard.prepare(display_math_source, true)
assert(display_math_plan and #display_math_chunks == 2, "display math must not become a prose chunk")
for _, chunk in ipairs(display_math_chunks) do
  assert(not chunk.text:find("arrow.r", 1, true), "display math body must be protected")
end
local display_math_outputs = {}
for _, chunk in ipairs(display_math_chunks) do
  display_math_outputs[#display_math_outputs + 1] = { id = chunk.id, text = chunk.text }
end
local display_math_result, display_math_error = guard.restore(display_math_plan, display_math_outputs)
assert(display_math_result and not display_math_error, display_math_error)
assert(display_math_result == display_math_source, "display math must round-trip exactly")
print("typst guard tests passed")
