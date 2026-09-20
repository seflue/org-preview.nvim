local eq = MiniTest.expect.equality
local page = require("org-preview.page")

local T = MiniTest.new_set()

T["build wraps fragment with css links and reload client"] = function()
  local html = page.build({ title = "a<b", css = { "x.css", "y.css" }, fragment = "<p>hi</p>" })
  eq(html:find("<title>a&lt;b</title>", 1, true) ~= nil, true)
  eq(html:find('<link rel="stylesheet" href="x.css">', 1, true) ~= nil, true)
  eq(html:find('<link rel="stylesheet" href="y.css">', 1, true) ~= nil, true)
  eq(html:find("<p>hi</p>", 1, true) ~= nil, true)
  eq(html:find("new EventSource('/events')", 1, true) ~= nil, true)
end

return T
