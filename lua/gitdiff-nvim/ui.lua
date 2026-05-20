local M = {}

local config = require('gitdiff-nvim.config')
local state = require('gitdiff-nvim.state')
local git = require('gitdiff-nvim.git')
local files_panel = require('gitdiff-nvim.files_panel')
local diff_panel = require('gitdiff-nvim.diff_panel')

local function setup_diff_window(win)
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'yes'
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].scrollbind = true
  vim.wo[win].cursorbind = true
  vim.wo[win].foldcolumn = '0'
end

local function setup_files_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].list = false
end

-- Build layout in the current (already-new) tabpage:
--   [files | left | right]
local function build_layout()
  local opts = config.options

  -- Start: one window from `tabnew`. Make it the files panel (leftmost).
  local files_win = vim.api.nvim_get_current_win()
  -- Create the right area by splitting to the right; the new window becomes
  -- the diff area, file panel stays on the left.
  vim.cmd('rightbelow vsplit')
  local right_area = vim.api.nvim_get_current_win()
  -- Split the diff area into left + right.
  vim.cmd('rightbelow vsplit')
  local right_win = vim.api.nvim_get_current_win()

  -- Resize: files panel width
  vim.api.nvim_win_set_width(files_win, opts.files_width)

  -- The middle (HEAD) window is `right_area` now, and `right_win` is the new
  -- split to the right of it.
  local left_win = right_area

  -- Apply explicit left-diff width so the two diff panes are deterministically
  -- balanced (or split by diff_ratio). The right pane gets the remainder.
  local remaining = vim.o.columns - opts.files_width
  local left_width = math.floor(remaining * opts.diff_ratio)
  vim.api.nvim_win_set_width(left_win, left_width)

  setup_files_window(files_win)
  setup_diff_window(left_win)
  setup_diff_window(right_win)

  return files_win, left_win, right_win
end

function M.open()
  local cwd = vim.fn.getcwd()
  git.is_repo(cwd, function(ok)
    if not ok then
      vim.notify('gitdiff: not inside a git repository', vim.log.levels.WARN)
      return
    end
    git.repo_root(function(root, err)
      if not root then
        vim.notify('gitdiff: ' .. (err or 'failed to find repo root'), vim.log.levels.ERROR)
        return
      end

      vim.cmd('tabnew')
      local tabpage = vim.api.nvim_get_current_tabpage()
      local files_win, left_win, right_win = build_layout()

      local session = state.new(tabpage, root)
      session.windows.files = files_win
      session.windows.left = left_win
      session.windows.right = right_win

      -- Initialize the file panel (creates its buffer + sets keymaps).
      files_panel.attach(files_win)
      -- Initialize empty diff panes so they have buffers.
      diff_panel.attach_empty(left_win, right_win)

      -- Auto-clear session if its tabpage gets closed.
      local grp = vim.api.nvim_create_augroup('GitDiffSession_' .. tabpage, { clear = true })
      vim.api.nvim_create_autocmd('TabClosed', {
        group = grp,
        callback = function()
          if state.session and not vim.api.nvim_tabpage_is_valid(state.session.tabpage) then
            state.clear()
            vim.api.nvim_del_augroup_by_id(grp)
          end
        end,
      })

      M.refresh()
    end)
  end)
end

function M.close()
  if not state.active() then
    return
  end
  local tab = state.session.tabpage
  local tabnr = vim.api.nvim_tabpage_get_number(tab)
  state.clear()
  pcall(vim.cmd, tabnr .. 'tabclose')
end

function M.refresh()
  if not state.active() then
    return
  end
  local s = state.session
  git.status(s.repo_root, function(groups, err)
    if not groups then
      vim.notify('gitdiff: ' .. (err or 'status failed'), vim.log.levels.ERROR)
      return
    end
    files_panel.render(groups)
    -- If a file was currently loaded, try to reload it; if it no longer has
    -- changes, clear the diff panes.
    local cur = state.current_file()
    if cur then
      local still_present = false
      for _, list in ipairs({ groups.staged, groups.changes, groups.untracked }) do
        for _, f in ipairs(list) do
          if f.path == cur.path then
            still_present = true
            break
          end
        end
        if still_present then break end
      end
      if still_present then
        diff_panel.load(cur)
      else
        diff_panel.clear()
        s.current = nil
      end
    end
  end)
end

return M
