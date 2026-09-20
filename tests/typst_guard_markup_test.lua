local root = assert(os.getenv("GRAMMARLY_BRIDGE_TEST_ROOT"))
local guard = dofile(root .. "/dotfiles/.config/nvim/lua/custom/typst_guard.lua")

local source = table.concat({
  "= Heading <sec:head>",
  'Text with @smith2024, $x^2$, `raw code`, https://example.test/a, 42, 1e-3, full24, compact3f, Float64, sampled-v1, H3-256, and #link("https://example.test")[visible link prose].',
  "// disabled prose must stay exact",
  '#figure(image("x.png"), caption: [A useful *caption* with 3.14 items.])',
  "#prose[Inline wrapper prose.]",
  "#let helper(body) = block[Function content prose #body survives.]",
  "/* Disabled old prose with @old and 99. */",
}, "\n")

local plan, chunks = guard.prepare(source, true)
assert(plan and #chunks == 1, "inline markup must remain one paragraph chunk")
local exposed = chunks[1].text
local protected = table.concat(plan.protected, "\n")
for _, exact in ipairs({
  "@smith2024",
  "$x^2$",
  "`raw code`",
  "https://example.test/a",
  "42",
  "1e-3",
  "full24",
  "compact3f",
  "Float64",
  "sampled-v1",
  "H3-256",
  "#link",
  "https://example.test",
  "// disabled",
  "3.14",
  "/* Disabled",
  "@old",
  "99",
}) do
  assert(not exposed:find(exact, 1, true), exact .. " must be protected")
end
for _, identifier in ipairs({ "full24", "compact3f", "Float64", "sampled-v1", "H3-256" }) do
  assert(protected:find(identifier, 1, true), identifier .. " must be protected as one token")
end
for _, prose in ipairs({
  "Heading",
  "Text with",
  "visible link prose",
  "A useful",
  "caption",
  "Inline wrapper prose.",
  "Function content prose",
  "survives.",
}) do
  assert(exposed:find(prose, 1, true), prose .. " must be exposed")
end

local restored, err = guard.restore(plan, { { id = 1, text = chunks[1].text } })
assert(restored and not err, err)
assert(restored == source, "identity output must restore exact source")

local revised = chunks[1].text:gsub("visible link prose", "revised link prose"):gsub("A useful", "A clear")
local result, result_err = guard.restore(plan, { { id = 1, text = revised } })
assert(result and not result_err, result_err)
assert(result:find('#link("https://example.test")[revised link prose]', 1, true))
assert(result:find("caption: [A clear *caption* with 3.14 items.]", 1, true))

local boundary_source = "Full24 is used with $x$ inline math and 47. Next."
local boundary_plan, boundary_chunks = guard.prepare(boundary_source, true)
assert(boundary_plan and #boundary_chunks == 1)
local math_marker = nil
local found_terminal_number = false
for id, value in ipairs(boundary_plan.protected) do
  if value:find("$x$", 1, true) then math_marker = string.format("⟦TYPST_GUARD_%04d⟧", id) end
  if value == "47" then found_terminal_number = true end
  assert(value ~= "47.", "terminal punctuation must not be part of a protected number")
end
assert(math_marker and found_terminal_number)
local boundary_output = boundary_chunks[1].text:gsub("⟧ ", "⟧")
boundary_output = boundary_output:gsub(math_marker, " " .. math_marker .. " ", 1)
local boundary_result, boundary_error = guard.restore(
  boundary_plan,
  { { id = boundary_chunks[1].id, text = boundary_output } }
)
assert(boundary_result and not boundary_error, boundary_error)
assert(boundary_result == boundary_source, "guard must restore original whitespace around protected terms")

local deletion_source = "Claim $x$ not @source optional."
local deletion_plan, deletion_chunks = guard.prepare(deletion_source, true)
assert(deletion_plan and #deletion_chunks == 1)
local deletion_output, deletion_count = deletion_chunks[1].text:gsub("not", "", 1)
assert(deletion_count == 1)
local deletion_result, deletion_error = guard.restore(
  deletion_plan,
  { { id = deletion_chunks[1].id, text = deletion_output } }
)
assert(not deletion_result and deletion_error:find("deleted a Typst prose span", 1, true))

local movement_source = "Left side $x$ right side."
local movement_plan, movement_chunks = guard.prepare(movement_source, true)
assert(movement_plan and #movement_chunks == 1)
local movement_marker = nil
for id, value in ipairs(movement_plan.protected) do
  if value:find("$x$", 1, true) then movement_marker = string.format("⟦TYPST_GUARD_%04d⟧", id) end
end
assert(movement_marker)
local movement_output, movement_count = movement_chunks[1].text:gsub(
  "Left side" .. movement_marker .. "right side%.",
  "Left side right side." .. movement_marker,
  1
)
assert(movement_count == 1)
local movement_result, movement_error = guard.restore(
  movement_plan,
  { { id = movement_chunks[1].id, text = movement_output } }
)
assert(not movement_result and movement_error:find("deleted a Typst prose span", 1, true))

local crossing_source = "#stage([Solver trace])"
local crossing_plan, crossing_chunks = guard.prepare(crossing_source, true)
assert(crossing_plan and #crossing_chunks == 1)
local open_marker = nil
for id, value in ipairs(crossing_plan.protected) do
  if value:find("#stage([", 1, true) then open_marker = string.format("⟦TYPST_GUARD_%04d⟧", id) end
end
assert(open_marker)
local crossing_output = crossing_chunks[1].text:gsub(
  open_marker .. "Solver trace",
  "Solver trajectory" .. open_marker,
  1
)
local crossing_result, crossing_error = guard.restore(
  crossing_plan,
  { { id = crossing_chunks[1].id, text = crossing_output } }
)
assert(not crossing_result and crossing_error:find("crossed a protected Typst boundary", 1, true))

print("typst guard markup tests passed")
