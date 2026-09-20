-- A backend turns org source lines into an HTML *fragment* (no <html>/<head>).
-- Page assembly (CSS, live-reload script) happens in page.lua, so backends
-- stay symmetric and can be swapped via opts.backend.
--
-- Backend shape:
--   cmd    string[]  command reading org from stdin, writing HTML to stdout
--   render function(lines, cb)  optional; overrides cmd for non-CLI backends
local M = {}

local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

M.builtin = {
  pandoc = {
    -- Custom template: emits pandoc's own highlighting CSS (only when a src
    -- block is present), a table of contents, then the body; nothing else.
    cmd = {
      "pandoc",
      "-f",
      "org",
      "-t",
      "html5",
      "--standalone",
      "--toc",
      "--template",
      vim.fs.joinpath(plugin_root, "templates", "pandoc.html"),
    },
  },
}

--- Run a backend on buffer lines. cb(html) on success, cb(nil, err) on failure.
--- cb is called on the main loop (safe for vim.api calls).
---@param backend table
---@param lines string[]
---@param cb fun(html: string|nil, err: string|nil)
function M.run(backend, lines, cb)
  if backend.render then
    return backend.render(lines, cb)
  end
  local input = table.concat(lines, "\n") .. "\n"
  -- vim.system raises on spawn failure (e.g. ENOENT); report it like any
  -- other backend error instead of unwinding into the caller.
  local ok, err = pcall(
    vim.system,
    backend.cmd,
    { stdin = input, text = true },
    vim.schedule_wrap(function(r)
      if r.code ~= 0 then
        return cb(nil, ("%s exited %d: %s"):format(backend.cmd[1], r.code, r.stderr or ""))
      end
      cb(r.stdout)
    end)
  )
  if not ok then
    cb(nil, ("cannot run %s: %s"):format(backend.cmd[1], tostring(err)))
  end
end

--- Resolve opts.backend (builtin name or backend table). Errors on an
--- unknown name or a table without cmd/render.
function M.get(spec)
  local b = type(spec) == "table" and spec or M.builtin[spec]
  if type(b) ~= "table" or not (b.cmd or b.render) then
    error("org-preview: unknown backend " .. vim.inspect(spec), 0)
  end
  return b
end

return M
