local M = {}

M.session = nil

function M.new(tabpage, repo_root)
  M.session = {
    tabpage = tabpage,
    repo_root = repo_root,
    files = {},
    current = nil,
    windows = { files = nil, left = nil, right = nil },
    buffers = { files = nil, left = nil, right = nil },
  }
  return M.session
end

function M.clear()
  M.session = nil
end

function M.active()
  return M.session ~= nil
    and M.session.tabpage
    and vim.api.nvim_tabpage_is_valid(M.session.tabpage)
end

function M.current_file()
  local s = M.session
  if not s or not s.current then
    return nil
  end
  return s.files[s.current]
end

return M
