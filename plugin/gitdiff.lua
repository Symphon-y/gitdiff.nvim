if vim.g.loaded_gitdiff == 1 then
  return
end
vim.g.loaded_gitdiff = 1

vim.api.nvim_create_user_command('GitDiffStart', function()
  require('gitdiff-nvim').open()
end, { desc = 'Open VS Code-style git diff UI' })

vim.api.nvim_create_user_command('GitDiffStop', function()
  require('gitdiff-nvim').close()
end, { desc = 'Close the gitdiff session' })

vim.api.nvim_create_user_command('GitDiffClose', function()
  require('gitdiff-nvim').close()
end, { desc = 'Alias for :GitDiffStop' })

vim.api.nvim_create_user_command('GitDiffRefresh', function()
  require('gitdiff-nvim').refresh()
end, { desc = 'Refresh the gitdiff session' })
