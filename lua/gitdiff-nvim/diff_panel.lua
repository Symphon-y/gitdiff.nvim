local M = {}

local state = require('gitdiff-nvim.state')
local git = require('gitdiff-nvim.git')

local function make_scratch(name, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  if ft and ft ~= '' then
    vim.bo[buf].filetype = ft
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

-- Initialize empty scratch buffers in the two diff windows.
function M.attach_empty(left_win, right_win)
  local lbuf = make_scratch('gitdiff://HEAD/<no file>', '')
  local rbuf = make_scratch('gitdiff://WORK/<no file>', '')
  vim.api.nvim_win_set_buf(left_win, lbuf)
  vim.api.nvim_win_set_buf(right_win, rbuf)
  vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, { '-- no file selected --' })
  vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, { '-- pick a file in the left panel --' })
  vim.bo[lbuf].modifiable = false
  vim.bo[rbuf].modifiable = false
  vim.bo[lbuf].modified = false
  vim.bo[rbuf].modified = false
  state.session.buffers.left = lbuf
  state.session.buffers.right = rbuf
end

function M.clear()
  M.attach_empty(state.session.windows.left, state.session.windows.right)
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function diff_off(win)
  vim.api.nvim_win_call(win, function()
    pcall(vim.cmd, 'diffoff')
  end)
end

local function diff_this(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd('diffthis')
  end)
end

-- Load a file entry into the left/right diff panes.
-- For staged group: compare HEAD vs index. For changes/untracked: compare HEAD vs worktree.
function M.load(file)
  local s = state.session
  if not s then return end
  local left_win, right_win = s.windows.left, s.windows.right
  local cwd = s.repo_root

  -- Remember the selected file in session.
  for i, f in ipairs(s.files) do
    if f == file or (f.path == file.path and f.group == file.group) then
      s.current = i
      break
    end
  end

  -- Determine source paths.
  local head_path = file.orig or file.path
  local right_path = file.path
  local is_untracked = file.group == 'untracked'
  local is_added = file.status == 'A' and not file.orig
  local is_deleted = file.status == 'D'

  -- Tear down previous diff mode on both windows.
  diff_off(left_win)
  diff_off(right_win)

  local ft = vim.filetype.match({ filename = file.path }) or ''

  local lbuf = make_scratch('gitdiff://HEAD/' .. head_path, ft)
  local rbuf = make_scratch('gitdiff://WORK/' .. right_path, ft)

  vim.api.nvim_win_set_buf(left_win, lbuf)
  vim.api.nvim_win_set_buf(right_win, rbuf)
  -- Wipe old buffers (no longer referenced).
  if s.buffers.left and vim.api.nvim_buf_is_valid(s.buffers.left) then
    pcall(vim.api.nvim_buf_delete, s.buffers.left, { force = true })
  end
  if s.buffers.right and vim.api.nvim_buf_is_valid(s.buffers.right) then
    pcall(vim.api.nvim_buf_delete, s.buffers.right, { force = true })
  end
  s.buffers.left = lbuf
  s.buffers.right = rbuf

  -- Track loads so a stale callback doesn't clobber a newer one.
  s.load_token = (s.load_token or 0) + 1
  local token = s.load_token

  local left_done, right_done = false, false
  local left_lines, right_lines = {}, {}

  local function maybe_finish()
    if not (left_done and right_done) then return end
    if token ~= s.load_token then return end
    set_lines(lbuf, left_lines)
    set_lines(rbuf, right_lines)
    diff_this(left_win)
    diff_this(right_win)
    -- Jump to first hunk in the right window.
    vim.api.nvim_win_call(right_win, function()
      vim.api.nvim_win_set_cursor(right_win, { 1, 0 })
      pcall(vim.cmd, 'normal! ]c')
    end)
  end

  -- LEFT (HEAD)
  if is_untracked or is_added then
    left_lines = {}
    left_done = true
    maybe_finish()
  else
    git.show_head(cwd, head_path, function(lines)
      left_lines = lines
      left_done = true
      maybe_finish()
    end)
  end

  -- RIGHT
  if is_deleted then
    right_lines = {}
    right_done = true
    maybe_finish()
  elseif file.group == 'staged' then
    -- Show index version of the file.
    require('plenary.job'):new({
      command = 'git',
      args = { 'show', ':' .. right_path },
      cwd = cwd,
      on_exit = function(j, code)
        vim.schedule(function()
          right_lines = code == 0 and j:result() or {}
          right_done = true
          maybe_finish()
        end)
      end,
    }):start()
  else
    git.read_worktree(cwd, right_path, function(lines)
      right_lines = lines
      right_done = true
      maybe_finish()
    end)
  end

  -- Apply diff-pane keymaps to the new buffers.
  require('gitdiff-nvim.keymaps').setup_diff_panel(lbuf)
  require('gitdiff-nvim.keymaps').setup_diff_panel(rbuf)
end

return M
