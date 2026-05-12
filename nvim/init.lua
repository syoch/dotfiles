-- Load basic configurations
require("config.options")
require("config.keymaps")

-- Setup lazy.nvim plugin manager
require("config.lazy")

vim.filetype.add({
  pattern = {
    [".*%.lambda"] = "lambda",
  }
})

vim.lsp.config.lambda = {
  cmd = { "/home/syoch/work/lambda/bin/lambda", "lsp" },
  filetypes = { "lambda" },
  root_markers = { ".git" },
}
vim.lsp.enable("lambda")
