local M = {}

local config = require('gitdiff-nvim.config')
local state = require('gitdiff-nvim.state')

function M.setup(opts)
  config.setup(opts)
  require('gitdiff-nvim.highlights').setup()
end

function M.open()
  if state.active() then
    vim.api.nvim_set_current_tabpage(state.session.tabpage)
    return
  end
  require('gitdiff-nvim.ui').open()
end

function M.close()
  require('gitdiff-nvim.ui').close()
end

function M.refresh()
  if not state.active() then
    vim.notify('gitdiff: no active session', vim.log.levels.WARN)
    return
  end
  require('gitdiff-nvim.ui').refresh()
end

return M
