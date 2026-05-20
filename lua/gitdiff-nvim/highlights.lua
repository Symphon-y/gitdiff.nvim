local M = {}

local function link(name, target)
  vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

function M.setup()
  link('GitDiffStatusModified', 'DiagnosticWarn')
  link('GitDiffStatusAdded',    'DiagnosticOk')
  link('GitDiffStatusDeleted',  'DiagnosticError')
  link('GitDiffStatusRenamed',  'DiagnosticInfo')
  link('GitDiffStatusConflict', 'DiagnosticError')
  link('GitDiffStatusUntracked', 'Comment')
  link('GitDiffSectionHeader',  'Title')
end

-- Initialize highlights eagerly on require so users who don't call setup()
-- still get sensible colors.
M.setup()

-- Re-apply on colorscheme change.
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('GitDiffHighlights', { clear = true }),
  callback = function() M.setup() end,
})

return M
