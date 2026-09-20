local backends = require("org-preview.backends")
local page = require("org-preview.page")
local server = require("org-preview.server")

local M = {}

M.defaults = {
  host = "127.0.0.1",
  port = 0, -- 0 = pick a free port once per Neovim instance and keep it
  backend = "pandoc",
  css = { "https://cdn.jsdelivr.net/npm/water.css@2/out/water.css" },
  debounce_ms = 300,
  open = true, -- open the browser via vim.ui.open when the server starts
}

M.opts = M.defaults

local state = {
  buf = nil,
  backend = nil,
  fragment = "",
  generation = 0,
  last_err = nil,
  timer = nil,
  augroup = nil,
  port = nil, -- port bound on the first start; reused so open tabs reconnect
}

---@param opts table|nil
function M.setup(opts)
  -- vim.system, vim.uv and vim.ui.open are 0.10 APIs; fail with a message
  -- instead of a cryptic nil-call later.
  if vim.fn.has("nvim-0.10") ~= 1 then
    vim.notify("org-preview.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
    return
  end
  M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  local ok, err = pcall(backends.get, M.opts.backend)
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

local function title()
  local name = vim.api.nvim_buf_get_name(state.buf)
  return name ~= "" and vim.fs.basename(name) or ("buffer " .. state.buf)
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  state.generation = state.generation + 1
  local generation = state.generation
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  backends.run(state.backend, lines, function(html, err)
    -- Renders are async and may finish out of order; only the newest may
    -- publish, and none after :OrgPreviewStop.
    if generation ~= state.generation or not server.running() then
      return
    end
    if not html then
      -- Report each distinct failure once, not on every debounce tick.
      if err ~= state.last_err then
        state.last_err = err
        vim.notify("org-preview: " .. err, vim.log.levels.ERROR)
      end
      return
    end
    state.last_err = nil
    state.fragment = html
    server.push(html)
  end)
end

local function schedule_render()
  state.timer = state.timer or vim.uv.new_timer()
  state.timer:stop()
  -- The timer callback runs in a fast event context; render() needs vim.api.
  state.timer:start(M.opts.debounce_ms, 0, vim.schedule_wrap(render))
end

local function handle(path)
  if path == "/" then
    return page.build({ title = title(), css = M.opts.css, fragment = state.fragment })
  end
  return nil
end

function M.url()
  return ("http://%s:%d/"):format(M.opts.host, state.port or M.opts.port)
end

local function start_server()
  local port, err = server.start({ host = M.opts.host, port = state.port or M.opts.port, handler = handle })
  -- The remembered port may have been taken by another process meanwhile;
  -- with an automatic port, pick a fresh one rather than fail.
  if not port and state.port and M.opts.port == 0 then
    port, err = server.start({ host = M.opts.host, port = 0, handler = handle })
  end
  if port then
    state.port = port
  end
  return port, err
end

--- Start previewing the current buffer.
function M.start()
  local ok, backend = pcall(backends.get, M.opts.backend)
  if not ok then
    return vim.notify(tostring(backend), vim.log.levels.ERROR)
  end
  local started = not server.running()
  local port, err = start_server()
  if not port then
    return vim.notify("org-preview: " .. err, vim.log.levels.ERROR)
  end

  state.buf = vim.api.nvim_get_current_buf()
  state.backend = backend
  state.fragment = ""
  state.augroup = vim.api.nvim_create_augroup("org-preview", { clear = true })
  -- BufReadPost covers :e!, FileChangedShellPost a reload after an outside
  -- write; neither fires TextChanged.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufReadPost", "FileChangedShellPost" }, {
    group = state.augroup,
    buffer = state.buf,
    desc = "org-preview: re-render after a change",
    callback = schedule_render,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = state.augroup,
    buffer = state.buf,
    desc = "org-preview: stop when the previewed buffer unloads",
    callback = function(ev)
      -- :e! unloads and reloads the same buffer; only stop if it stays gone.
      vim.schedule(function()
        if state.buf == ev.buf and not vim.api.nvim_buf_is_loaded(ev.buf) then
          M.stop()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = state.augroup,
    desc = "org-preview: stop on exit",
    callback = M.stop,
  })

  render()
  if started and M.opts.open then
    vim.ui.open(M.url())
  end
end

function M.toggle()
  if server.running() then
    M.stop()
  else
    M.start()
  end
end

function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.augroup then
    vim.api.nvim_del_augroup_by_id(state.augroup)
    state.augroup = nil
  end
  server.stop()
  state.buf = nil
  state.backend = nil
  state.fragment = ""
  state.last_err = nil
end

return M
