local root = assert(os.getenv("GRAMMARLY_BRIDGE_TEST_ROOT"))
package.path = root
  .. "/dot_config/nvim/lua/?.lua;"
  .. root
  .. "/dot_config/nvim/lua/?/init.lua;"
  .. package.path

local bridge = dofile(root .. "/dot_config/nvim/lua/custom/grammarly_bridge.lua")

local bridge_url = "https://grammarly-bridge.localhost"
assert(bridge._is_bridge_buffer_name(bridge_url .. "/", bridge_url))
assert(bridge._is_bridge_buffer_name("/tmp/grammarly-bridge.localhost", bridge_url))
assert(not bridge._is_bridge_buffer_name("/tmp/unrelated.typ", bridge_url))

local function fingerprint(text)
  local value, err = bridge._fingerprint(vim.split(text, "\n", { plain = true }))
  assert(value, err)
  return value
end

local original = "= Heading\nThis sentence are awkward.\n#let answer = 42"
local prose_edit = "= Better heading\nThis sentence is clear.\n#let answer = 42"
local code_edit = "= Heading\nThis sentence are awkward.\n#let answer = 43"

assert(fingerprint(original) == fingerprint(prose_edit), "prose-only edits must preserve structure")
assert(
  fingerprint(original) ~= fingerprint(code_edit),
  "code edits must change protected structure"
)

local parsed, parse_error = bridge._fingerprint({ "#let =" })
assert(parsed == nil and parse_error:find("parse error"), "broken Typst must fail closed")

print("grammarly bridge tests passed")
