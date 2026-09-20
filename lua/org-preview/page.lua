-- Wraps a backend fragment into a full HTML document with the configured
-- stylesheets and the live-reload client. The client swaps <body> in place on
-- each SSE message, so scroll position survives updates.
local M = {}

local client_script = [[
<script>
const es = new EventSource('/events');
es.onmessage = e => { document.body.innerHTML = JSON.parse(e.data); };
</script>]]

---@param opts { title: string, css: string[], fragment: string }
---@return string html
function M.build(opts)
  local links = {}
  for _, href in ipairs(opts.css) do
    links[#links + 1] = ('<link rel="stylesheet" href="%s">'):format(M.escape(href))
  end
  return table.concat({
    "<!DOCTYPE html>",
    '<html><head><meta charset="utf-8">',
    "<title>" .. M.escape(opts.title) .. "</title>",
    table.concat(links, "\n"),
    "</head><body>",
    opts.fragment,
    client_script,
    "</body></html>",
  }, "\n")
end

function M.escape(s)
  return (s:gsub('[<>&"]', { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;" }))
end

return M
