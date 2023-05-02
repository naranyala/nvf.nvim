local M = {}

local ns = vim.api.nvim_create_namespace "NvfHighlight"

function M.setup()
  vim.api.nvim_set_hl(0, "NvfCWD", { default = true, link = "Function" })
  vim.api.nvim_set_hl(0, "NvfSign", { default = true, link = "Constant" })
  vim.api.nvim_set_hl(0, "NvfDir", { default = true, link = "Preproc" })
  vim.api.nvim_set_hl(0, "NvfFile", { default = true, link = "Normal" })
  vim.api.nvim_set_hl(0, "NvfLink", { default = true, link = "Number" })
  vim.api.nvim_set_hl(0, "NvfSize", { default = true, link = "Statement" })
  vim.api.nvim_set_hl(0, "NvfTime", { default = true, link = "Type" })
end

function M.render(fs_stat, signs, mtime_start)
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(0, ns, "NvfCWD", 0, 0, -1)

  for i, v in ipairs(fs_stat) do
    local name_start = v.depth + vim.fn.strlen(signs[v.expanded and "expanded" or v.type])
    local name_end = name_start + vim.fn.strlen(v.name)
    vim.api.nvim_buf_add_highlight(0, ns, "NvfSign", i, 0, name_start)
    if v.type == "directory" then
      vim.api.nvim_buf_add_highlight(0, ns, "NvfDir", i, name_start, name_end)
    else
      vim.api.nvim_buf_add_highlight(0, ns, "NvfFile", i, name_start, name_end)
    end
    if v.link then
      vim.api.nvim_buf_add_highlight(0, ns, "NvfLink", i, name_start, name_end)
    end
    if v.size then
      local size_end = mtime_start - vim.fn.strlen(v.size)
      vim.api.nvim_buf_add_highlight(0, ns, "NvfSize", i, size_end, mtime_start)
    end
    vim.api.nvim_buf_add_highlight(0, ns, "NvfTime", i, mtime_start, -1)
  end
end

return M
