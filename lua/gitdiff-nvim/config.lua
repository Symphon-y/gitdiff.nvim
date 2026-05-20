local M = {}

local defaults = {
  files_width = 32,
  diff_ratio = 0.5,
  keymaps = {
    files_panel = {
      open = '<CR>',
      stage = 's',
      unstage = 'u',
      refresh = 'r',
      close = 'q',
      help = '?',
    },
    diff_panel = {
      stage_hunk = '<leader>hs',
      unstage_hunk = '<leader>hu',
      discard_hunk = '<leader>hr',
      next_file = '<C-l>',
      prev_file = '<C-h>',
      close = 'q',
    },
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

return M
