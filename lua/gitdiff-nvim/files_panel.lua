local M = {}

local state = require('gitdiff-nvim.state')

local NS = vim.api.nvim_create_namespace('gitdiff_files')

local function short_path(p)
  local parts = vim.split(p, '/', { plain = true })
  if #parts < 3 then return p end
  return '…/' .. parts[#parts - 1] .. '/' .. parts[#parts]
end

local STATUS_HL = {
  M = 'GitDiffStatusModified',
  A = 'GitDiffStatusAdded',
  D = 'GitDiffStatusDeleted',
  R = 'GitDiffStatusRenamed',
  C = 'GitDiffStatusRenamed',
  U = 'GitDiffStatusConflict',
  ['?'] = 'GitDiffStatusUntracked',
}

local function make_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'gitdiff-files'
  vim.api.nvim_buf_set_name(buf, 'gitdiff://files')
  return buf
end

function M.attach(win)
  local buf = make_buffer()
  vim.api.nvim_win_set_buf(win, buf)
  state.session.buffers.files = buf
  require('gitdiff-nvim.keymaps').setup_files_panel(buf)
  return buf
end

-- Render the three groups into the files-panel buffer.
function M.render(groups)
  local s = state.session
  if not s or not s.buffers.files then return end
  local buf = s.buffers.files
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {}
  local highlights = {} -- { {line, col_start, col_end, hl} }
  local line_map = {}   -- lua line index (0-based row) -> file entry
  local flat = {}       -- ordered list of all file entries for nav

  local function add_group(title, items)
    if #items == 0 then return end
    if #lines > 0 then
      table.insert(lines, '')
    end
    local header = string.format('%s (%d)', title, #items)
    table.insert(lines, header)
    table.insert(highlights, { #lines - 1, 0, #header, 'GitDiffSectionHeader' })
    for _, f in ipairs(items) do
      local letter = f.status
      -- Two-character status badge column for alignment.
      local label = short_path(f.path)
      if f.orig then
        label = short_path(f.orig) .. ' \u{2192} ' .. short_path(f.path)
      end
      local row = string.format('  %s  %s', letter, label)
      table.insert(lines, row)
      local row_idx = #lines - 1
      -- highlight status letter at byte offset 2..3
      local hl = STATUS_HL[letter] or 'GitDiffStatusModified'
      table.insert(highlights, { row_idx, 2, 3, hl })
      table.insert(flat, f)
      line_map[row_idx] = #flat
    end
  end

  add_group('STAGED CHANGES', groups.staged)
  add_group('CHANGES', groups.changes)
  add_group('UNTRACKED', groups.untracked)

  if #lines == 0 then
    lines = { 'No changes' }
    table.insert(highlights, { 0, 0, 10, 'Comment' })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, NS, h[4], h[1], h[2], h[3])
  end

  s.files = flat
  s.line_map = line_map
end

-- Get the file entry under the cursor in the files panel.
function M.file_at_cursor()
  local s = state.session
  if not s or not s.windows.files then return nil end
  local win = s.windows.files
  if not vim.api.nvim_win_is_valid(win) then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local idx = s.line_map and s.line_map[row]
  if not idx then return nil end
  return s.files[idx], idx
end

-- Move cursor to row representing index `idx` in s.files. Returns true if moved.
function M.focus_index(idx)
  local s = state.session
  if not s or not s.windows.files or not s.line_map then return false end
  for row, i in pairs(s.line_map) do
    if i == idx then
      vim.api.nvim_win_set_cursor(s.windows.files, { row + 1, 0 })
      return true
    end
  end
  return false
end

return M
