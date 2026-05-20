local M = {}

local Job = require('plenary.job')

local function run(args, cwd, opts, on_done)
  opts = opts or {}
  local stdout = {}
  local stderr = {}
  Job:new({
    command = 'git',
    args = args,
    cwd = cwd,
    writer = opts.stdin,
    on_stdout = function(_, line)
      stdout[#stdout + 1] = line
    end,
    on_stderr = function(_, line)
      stderr[#stderr + 1] = line
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        on_done(code, stdout, stderr)
      end)
    end,
  }):start()
end

function M.repo_root(cb)
  run({ 'rev-parse', '--show-toplevel' }, vim.fn.getcwd(), nil, function(code, out, err)
    if code ~= 0 then
      cb(nil, table.concat(err, '\n'))
      return
    end
    cb(out[1], nil)
  end)
end

-- Parse `git status --porcelain=v1 -uall -z` joined stdout (lines were split on \n
-- by plenary; we need raw bytes split on \0).
local function parse_status(raw)
  local files = {}
  local i = 1
  local len = #raw
  while i <= len do
    -- find next NUL
    local nul = raw:find('\0', i, true)
    if not nul then
      break
    end
    local entry = raw:sub(i, nul - 1)
    i = nul + 1
    if #entry < 3 then
      -- skip malformed
    else
      local x = entry:sub(1, 1)
      local y = entry:sub(2, 2)
      local path = entry:sub(4)
      local orig = nil
      if x == 'R' or x == 'C' then
        -- next record is the original path
        local nul2 = raw:find('\0', i, true)
        if nul2 then
          orig = raw:sub(i, nul2 - 1)
          i = nul2 + 1
        end
      end
      table.insert(files, {
        x = x,
        y = y,
        path = path,
        orig = orig,
      })
    end
  end
  return files
end

-- Returns three groups: staged, changes (unstaged tracked), untracked.
function M.status(cwd, cb)
  -- Use a job that captures raw bytes; plenary splits on \n which is fine
  -- because -z emits \0 (never \n in paths).
  Job:new({
    command = 'git',
    args = { 'status', '--porcelain=v1', '-uall', '-z' },
    cwd = cwd,
    on_exit = function(j, code)
      vim.schedule(function()
        if code ~= 0 then
          cb(nil, table.concat(j:stderr_result(), '\n'))
          return
        end
        -- plenary stores stdout as table of "lines" but with -z there are no
        -- newlines, so join with \n yields a single string OR we need to grab
        -- raw. Use j:result() then concat with \n in case multiple chunks.
        local raw = table.concat(j:result(), '\n')
        local entries = parse_status(raw)

        local staged, changes, untracked = {}, {}, {}
        for _, e in ipairs(entries) do
          if e.x == '?' and e.y == '?' then
            table.insert(untracked, {
              path = e.path,
              status = '??',
              group = 'untracked',
            })
          else
            if e.x ~= ' ' and e.x ~= '?' then
              table.insert(staged, {
                path = e.path,
                orig = e.orig,
                status = e.x,
                group = 'staged',
              })
            end
            if e.y ~= ' ' and e.y ~= '?' then
              table.insert(changes, {
                path = e.path,
                orig = e.orig,
                status = e.y,
                group = 'changes',
              })
            end
          end
        end
        cb({ staged = staged, changes = changes, untracked = untracked }, nil)
      end)
    end,
  }):start()
end

-- Read a file's content at HEAD. Returns lines table (may be empty).
function M.show_head(cwd, path, cb)
  Job:new({
    command = 'git',
    args = { 'show', 'HEAD:' .. path },
    cwd = cwd,
    on_exit = function(j, code)
      vim.schedule(function()
        if code ~= 0 then
          cb({}, nil) -- treat missing-at-HEAD as empty (added file)
          return
        end
        cb(j:result(), nil)
      end)
    end,
  }):start()
end

-- Read the working tree version of a path. Returns lines table.
function M.read_worktree(cwd, path, cb)
  local full = cwd .. '/' .. path
  vim.uv.fs_stat(full, function(_, stat)
    if not stat then
      vim.schedule(function() cb({}, nil) end)
      return
    end
    vim.uv.fs_open(full, 'r', 438, function(err, fd)
      if err or not fd then
        vim.schedule(function() cb({}, err) end)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(err2, data)
        vim.uv.fs_close(fd, function() end)
        if err2 then
          vim.schedule(function() cb({}, err2) end)
          return
        end
        local lines = vim.split(data or '', '\n', { plain = true })
        -- vim.split keeps a trailing empty line for files ending in \n;
        -- nvim_buf_set_lines expects no trailing empty for that case.
        if #lines > 0 and lines[#lines] == '' then
          table.remove(lines)
        end
        vim.schedule(function() cb(lines, nil) end)
      end)
    end)
  end)
end

function M.stage_file(cwd, path, cb)
  run({ 'add', '--', path }, cwd, nil, function(code, _, err)
    cb(code == 0, code == 0 and nil or table.concat(err, '\n'))
  end)
end

function M.unstage_file(cwd, path, cb)
  run({ 'reset', 'HEAD', '--', path }, cwd, nil, function(code, _, err)
    cb(code == 0, code == 0 and nil or table.concat(err, '\n'))
  end)
end

function M.apply_patch(cwd, patch, opts, cb)
  opts = opts or {}
  local args = { 'apply', '--cached', '--unidiff-zero' }
  if opts.reverse then
    table.insert(args, '--reverse')
  end
  table.insert(args, '-')
  run(args, cwd, { stdin = patch }, function(code, _, err)
    cb(code == 0, code == 0 and nil or table.concat(err, '\n'))
  end)
end

-- Discard a hunk in the working tree by reverse-applying without --cached.
function M.apply_worktree_reverse(cwd, patch, cb)
  run(
    { 'apply', '--unidiff-zero', '--reverse', '-' },
    cwd,
    { stdin = patch },
    function(code, _, err)
      cb(code == 0, code == 0 and nil or table.concat(err, '\n'))
    end
  )
end

-- Raw unified diff for a single path (unstaged by default, or --cached).
function M.diff(cwd, path, opts, cb)
  opts = opts or {}
  local args = { 'diff', '-U0', '--no-color' }
  if opts.cached then
    table.insert(args, '--cached')
  end
  table.insert(args, '--')
  table.insert(args, path)
  run(args, cwd, nil, function(code, out, err)
    if code ~= 0 then
      cb(nil, table.concat(err, '\n'))
      return
    end
    cb(out, nil)
  end)
end

function M.is_repo(cwd, cb)
  Job:new({
    command = 'git',
    args = { 'rev-parse', '--is-inside-work-tree' },
    cwd = cwd,
    on_exit = function(_, code)
      vim.schedule(function()
        cb(code == 0)
      end)
    end,
  }):start()
end

return M
