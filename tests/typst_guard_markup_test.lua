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

print("typst guard markup tests passed")
