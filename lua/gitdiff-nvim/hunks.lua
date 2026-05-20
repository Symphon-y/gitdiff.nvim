local M = {}

local state = require('gitdiff-nvim.state')
local git = require('gitdiff-nvim.git')

-- Parse the unified-diff output of `git diff -U0` (or --cached).
-- Returns a list of hunks: { old_start, old_count, new_start, new_count, body = {lines} }
function M.parse(diff_lines)
  local hunks = {}
  local current = nil
  for _, line in ipairs(diff_lines) do
    local os_, oc, ns, nc = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
    if os_ then
      if current then table.insert(hunks, current) end
      current = {
        old_start = tonumber(os_),
        old_count = tonumber(oc ~= '' and oc or '1'),
        new_start = tonumber(ns),
        new_count = tonumber(nc ~= '' and nc or '1'),
        header = line,
        body = {},
      }
    elseif current then
      local c = line:sub(1, 1)
      if c == '+' or c == '-' or c == ' ' or c == '\\' then
        table.insert(current.body, line)
      elseif line:match('^diff ') or line:match('^index ') or line:match('^%-%-%- ') or line:match('^%+%+%+ ') then
        -- header for a new file (shouldn't happen for single-file diff)
        table.insert(hunks, current)
        current = nil
      end
    end
  end
  if current then table.insert(hunks, current) end
  return hunks
end

-- Decide which side ('left' or 'right') the current buffer represents.
local function current_side()
  local s = state.session
  if not s then return nil end
  local buf = vim.api.nvim_get_current_buf()
  if buf == s.buffers.left then return 'left' end
  if buf == s.buffers.right then return 'right' end
  return nil
end

-- Given a list of hunks, a side, and the cursor's line (1-based), return the
-- best-matching hunk or nil.
local function find_hunk(hunks, side, lnum)
  for _, h in ipairs(hunks) do
    if side == 'right' then
      if h.new_count > 0 then
        if lnum >= h.new_start and lnum < h.new_start + h.new_count then
          return h
        end
      else
        -- pure deletion: anchor at new_start or new_start+1
        if lnum == h.new_start or lnum == h.new_start + 1 then
          return h
        end
      end
    else -- left
      if h.old_count > 0 then
        if lnum >= h.old_start and lnum < h.old_start + h.old_count then
          return h
        end
      else
        -- pure addition: anchor at old_start or old_start+1
        if lnum == h.old_start or lnum == h.old_start + 1 then
          return h
        end
      end
    end
  end
  return nil
end

-- Build a minimal patch containing a single hunk.
local function build_patch(path, hunk)
  local lines = {
    'diff --git a/' .. path .. ' b/' .. path,
    '--- a/' .. path,
    '+++ b/' .. path,
    hunk.header,
  }
  for _, l in ipairs(hunk.body) do
    table.insert(lines, l)
  end
  -- git apply expects trailing newline.
  return table.concat(lines, '\n') .. '\n'
end

-- action: 'stage' | 'unstage' | 'discard'
function M.act_on_hunk_at_cursor(action)
  local s = state.session
  if not s then return end
  local file = state.current_file()
  if not file then
    vim.notify('gitdiff: no file loaded', vim.log.levels.WARN)
    return
  end
  if file.orig then
    vim.notify('gitdiff: hunk operations not supported on renamed files; stage the whole file', vim.log.levels.WARN)
    return
  end

  local side = current_side()
  if not side then
    vim.notify('gitdiff: cursor must be in a diff pane', vim.log.levels.WARN)
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]

  -- For unstage, we look at the cached diff (between HEAD and index).
  local diff_opts = { cached = action == 'unstage' }

  git.diff(s.repo_root, file.path, diff_opts, function(diff_lines, err)
    if not diff_lines then
      vim.notify('gitdiff: diff failed: ' .. (err or ''), vim.log.levels.ERROR)
      return
    end
    local hunks = M.parse(diff_lines)
    if #hunks == 0 then
      vim.notify('gitdiff: no hunks found', vim.log.levels.WARN)
      return
    end
    local hunk = find_hunk(hunks, side, lnum)
    if not hunk then
      -- Fallback: pick the nearest hunk by start line.
      local best, dist = nil, math.huge
      for _, h in ipairs(hunks) do
        local anchor = side == 'right' and h.new_start or h.old_start
        local d = math.abs(anchor - lnum)
        if d < dist then best, dist = h, d end
      end
      hunk = best
    end
    if not hunk then
      vim.notify('gitdiff: no hunk under cursor', vim.log.levels.WARN)
      return
    end

    local patch = build_patch(file.path, hunk)
    local cb = function(ok, err2)
      if not ok then
        vim.notify('gitdiff: ' .. action .. ' hunk failed: ' .. (err2 or ''), vim.log.levels.ERROR)
        return
      end
      require('gitdiff-nvim.ui').refresh()
    end

    if action == 'stage' then
      git.apply_patch(s.repo_root, patch, { reverse = false }, cb)
    elseif action == 'unstage' then
      git.apply_patch(s.repo_root, patch, { reverse = true }, cb)
    elseif action == 'discard' then
      git.apply_worktree_reverse(s.repo_root, patch, cb)
    end
  end)
end

return M
