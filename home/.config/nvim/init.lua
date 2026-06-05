vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
local lazy_module = lazypath .. "/lua/lazy/init.lua"
local uv = vim.uv or vim.loop

if not uv.fs_stat(lazy_module) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  if uv.fs_stat(lazypath) then
    vim.api.nvim_err_writeln("lazy.nvim is incomplete at " .. lazypath)
    vim.api.nvim_err_writeln("Remove that directory or run ./install.sh from the dotfiles repo.")
    error("lazy.nvim bootstrap failed", 0)
  end

  local output = vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_err_writeln("Failed to clone lazy.nvim into " .. lazypath)
    vim.api.nvim_err_writeln(output)
    error("lazy.nvim bootstrap failed", 0)
  end
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
local function load_base46_cache(name)
  local file = vim.g.base46_cache .. name
  if uv.fs_stat(file) then
    dofile(file)
  end
end

load_base46_cache "defaults"
load_base46_cache "statusline"

require "options"
require "autocmds"

vim.schedule(function()
  require "mappings"
end)
