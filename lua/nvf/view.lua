local config = require "nvf.config"
local buffer = require "nvf.buffer"
local window = require "nvf.window"
local cursor = require "nvf.cursor"
local utils = require "nvf.utils"
local highlight = require "nvf.highlight"

local M = {}

local sep = utils.sep
local list = {}

function M.get_list()
  return list
end

function M.get_fname(line)
  return list[line - 1].name
end

local function new_buffer(buf)
  vim.api.nvim_buf_set_option(buf, "filetype", "nvf")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)

  vim.cmd("buffer " .. buf)
  vim.opt_local.wrap = false
  vim.opt_local.cursorline = true
  vim.opt_local.number = false
end

function M.create_default_buf(buf)
  vim.api.nvim_buf_set_name(buf, "[nvf]-default")
  new_buffer(buf)
end

function M.create_new_buf(buf)
  vim.api.nvim_buf_set_name(buf, "[nvf]-" .. buf)
  new_buffer(buf)
end

local function sort(a, b)
  local t1 = a.type == "directory"
  local t2 = b.type == "directory"
  if t1 and not t2 then
    return true
  elseif not t1 and t2 then
    return false
  end
  return a.name:lower() < b.name:lower()
end

local function winwidth()
  local width = vim.api.nvim_get_option "columns"
  if width >= 99 then
    width = 80
  elseif width <= 40 then
    width = 40
  else
    width = width - 10
  end
  return width
end

local function line_item(path, name, type)
  local absolute_path = path .. name
  local fs_lstat = vim.loop.fs_lstat(absolute_path)
  local link = nil
  local has_children = false
  if type == "directory" then
    name = name .. sep
  elseif type == "link" then
    if vim.fn.isdirectory(absolute_path) == 1 then
      name = name .. sep
      type = "directory"
    else
      type = "file"
    end
    link = type
  end
  return {
    name = name,
    type = type,
    link = link,
    mtime = fs_lstat.mtime.sec,
    has_children = has_children,
    absolute_path = absolute_path,
  }
end

local function create_list(fs, path, buf)
  local local_list = {}
  local name, type = vim.loop.fs_scandir_next(fs)
  while name ~= nil do
    local item = line_item(path, name, type)
    if not config.default.show_hidden_files then
      if not vim.startswith(name, ".") then
        table.insert(local_list, item)
      end
    else
      table.insert(local_list, item)
    end
    name, type = vim.loop.fs_scandir_next(fs)
  end

  table.sort(local_list, sort)

  return local_list
end

function M.redraw(buf, cur_path)
  local path = vim.fn.fnamemodify(cur_path, ":p")
  local fs, err = vim.loop.fs_scandir(path)
  if not fs then
    vim.api.nvim_notify(err, vim.log.levels.ERROR, {})
    return
  end

  -- reset list
  for i, _ in ipairs(list) do
    list[i] = nil
  end

  list = utils.shallowcopy(create_list(fs, path, buf))

  local names = vim.tbl_map(function(t)
    local align = winwidth() - vim.fn.strdisplaywidth(t.name)
    local format = " %s %" .. align .. "s"
    return string.format(format, t.name, os.date("%x %H:%M", t.mtime))
  end, list)

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { path })
  vim.api.nvim_buf_set_lines(buf, 1, -1, false, names)
  highlight.render(list, winwidth() - 16)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

local function find_cursor_line_from(file_list, name)
  local cursor_line
  for i, v in ipairs(file_list) do
    if v.name == name then
      cursor_line = i + 1
      break
    end
  end
  return cursor_line
end

function M.up()
  local buf = vim.api.nvim_get_current_buf()
  local cur_path = buffer.get_cwd(buf)
  local parent_path = vim.fn.fnamemodify(cur_path, ":h")
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  buffer.set_cwd(buf, parent_path)
  M.redraw(buf, parent_path)

  local parent_name = vim.fn.fnamemodify(cur_path, ":t") .. sep
  local parent_cursor_line = find_cursor_line_from(list, parent_name)
  cursor.new(buf, cur_path, cursor_pos)
  cursor.set(buf, nil, { parent_cursor_line, 0 })
end

function M.expand_or_collapse()
  local line = vim.fn.line "."
  if line == 1 then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local cur_path = buffer.get_cwd(buf)
  M.redraw(buf, cur_path)
end

local function cd_to(dest)
  local buf = vim.api.nvim_get_current_buf()
  local cur_path = buffer.get_cwd(buf)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  buffer.set_cwd(buf, dest)
  M.redraw(buf, dest)

  cursor.new(buf, cur_path, cursor_pos)
  cursor.set(buf, dest, { 2, 0 })
end

function M.cwd()
  cd_to(vim.loop.cwd())
end

function M.home()
  cd_to(vim.loop.os_homedir())
end

local function is_root(pathname)
  if sep == "\\" then
    return string.match(pathname, "^[A-Z]:\\?$")
  end
  return pathname == "/"
end

local function get_next_path(cur_path, name)
  local path
  if is_root(cur_path) then
    path = utils.remove_trailing_slash(vim.fs.normalize(cur_path .. name))
  else
    path = utils.remove_trailing_slash(vim.fs.normalize(cur_path .. sep .. name))
  end
  return path
end

function M.open()
  local line = vim.fn.line "."
  if line == 1 then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local cur_path = buffer.get_cwd(buf)
  local name = M.get_fname(line)
  local next_path = get_next_path(cur_path, name)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  if vim.fn.isdirectory(next_path) == 1 then
    buffer.set_cwd(buf, next_path)
    M.redraw(buf, next_path)
  else
    vim.cmd "redraw"
    vim.cmd("edit " .. next_path)
  end

  cursor.new(buf, cur_path, cursor_pos)
  cursor.set(buf, next_path, { 2, 0 })
end

function M.quit()
  local win = vim.api.nvim_get_current_win()
  vim.cmd("buffer " .. window.get_prev_buf(win))
end

function M.toggle_hidden_files()
  config.default.show_hidden_files = not config.default.show_hidden_files
  local line = vim.fn.line "."
  local name
  if line == 1 then
    name = vim.api.nvim_get_current_line()
  else
    name = M.get_fname(line)
  end

  local buf = vim.api.nvim_get_current_buf()
  local cur_path = buffer.get_cwd(buf)
  M.redraw(buf, cur_path)

  local cursor_line = find_cursor_line_from(list, name)
  cursor.new(buf, cur_path, { cursor_line, 0 })
  cursor.set(buf, nil, { cursor_line, 0 })
end

return M
