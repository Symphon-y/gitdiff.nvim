local M = {}

local config = require('gitdiff-nvim.config')
local state = require('gitdiff-nvim.state')

local function map(buf, mode, lhs, rhs, desc)
  if not lhs or lhs == '' then return end
  vim.keymap.set(mode, lhs, rhs, {
    buffer = buf,
    nowait = true,
    silent = true,
    desc = desc,
  })
end

-- ----- files panel -----
function M.setup_files_panel(buf)
  local km = config.options.keymaps.files_panel
  local files_panel = require('gitdiff-nvim.files_panel')
  local diff_panel = require('gitdiff-nvim.diff_panel')
  local git = require('gitdiff-nvim.git')
  local ui = require('gitdiff-nvim.ui')

  map(buf, 'n', km.open, function()
    local f = files_panel.file_at_cursor()
    if f then diff_panel.load(f) end
  end, 'gitdiff: open file diff')

  map(buf, 'n', km.stage, function()
    local f = files_panel.file_at_cursor()
    if not f then return end
    git.stage_file(state.session.repo_root, f.path, function(ok, err)
      if not ok then
        vim.notify('gitdiff: stage failed: ' .. (err or ''), vim.log.levels.ERROR)
        return
      end
      ui.refresh()
    end)
  end, 'gitdiff: stage file')

  map(buf, 'n', km.unstage, function()
    local f = files_panel.file_at_cursor()
    if not f then return end
    git.unstage_file(state.session.repo_root, f.path, function(ok, err)
      if not ok then
        vim.notify('gitdiff: unstage failed: ' .. (err or ''), vim.log.levels.ERROR)
        return
      end
      ui.refresh()
    end)
  end, 'gitdiff: unstage file')

  map(buf, 'n', km.refresh, function()
    ui.refresh()
  end, 'gitdiff: refresh')

  map(buf, 'n', km.close, function()
    ui.close()
  end, 'gitdiff: close')

  map(buf, 'n', km.help, function()
    M.show_help()
  end, 'gitdiff: help')
end

-- ----- diff panes -----
function M.setup_diff_panel(buf)
  local km = config.options.keymaps.diff_panel
  local ui = require('gitdiff-nvim.ui')
  local hunks = require('gitdiff-nvim.hunks')
  local diff_panel = require('gitdiff-nvim.diff_panel')
  local files_panel = require('gitdiff-nvim.files_panel')

  map(buf, 'n', km.close, function()
    ui.close()
  end, 'gitdiff: close')

  map(buf, 'n', km.next_file, function()
    local s = state.session
    if not s or #s.files == 0 then return end
    local i = (s.current or 0) % #s.files + 1
    diff_panel.load(s.files[i])
    files_panel.focus_index(i)
  end, 'gitdiff: next file')

  map(buf, 'n', km.prev_file, function()
    local s = state.session
    if not s or #s.files == 0 then return end
    local i = ((s.current or 1) - 2) % #s.files + 1
    diff_panel.load(s.files[i])
    files_panel.focus_index(i)
  end, 'gitdiff: previous file')

  map(buf, 'n', km.stage_hunk, function()
    hunks.act_on_hunk_at_cursor('stage')
  end, 'gitdiff: stage hunk')

  map(buf, 'n', km.unstage_hunk, function()
    hunks.act_on_hunk_at_cursor('unstage')
  end, 'gitdiff: unstage hunk')

  map(buf, 'n', km.discard_hunk, function()
    hunks.act_on_hunk_at_cursor('discard')
  end, 'gitdiff: discard hunk')
end

function M.show_help()
  local km = config.options.keymaps
  local lines = {
    ' gitdiff keymaps ',
    '',
    ' Files panel:',
    '   ' .. km.files_panel.open    .. '   open diff for file',
    '   ' .. km.files_panel.stage   .. '   stage file',
    '   ' .. km.files_panel.unstage .. '   unstage file',
    '   ' .. km.files_panel.refresh .. '   refresh',
    '   ' .. km.files_panel.close   .. '   close session',
    '   ' .. km.files_panel.help    .. '   this help',
    '',
    ' Diff panes:',
    '   ]c / [c              next / prev hunk (built-in)',
    '   ' .. km.diff_panel.stage_hunk   .. '         stage hunk',
    '   ' .. km.diff_panel.unstage_hunk .. '         unstage hunk',
    '   ' .. km.diff_panel.discard_hunk .. '         discard hunk (worktree)',
    '   ' .. km.diff_panel.next_file    .. '              next file',
    '   ' .. km.diff_panel.prev_file    .. '              prev file',
    '   ' .. km.diff_panel.close        .. '                    close session',
    '',
    ' Press q to dismiss',
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = 'nofile'
  local width = 0
  for _, l in ipairs(lines) do
    if #l > width then width = #l end
  end
  width = width + 2
  local height = #lines
  local ui = vim.api.nvim_list_uis()[1]
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    border = 'rounded',
    style = 'minimal',
    title = ' gitdiff help ',
    title_pos = 'center',
  })
  vim.wo[win].cursorline = false
  vim.keymap.set('n', 'q', function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true, silent = true })
end

return M
