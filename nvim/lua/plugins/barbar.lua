-- Barbar (buffer tabs) configuration  
return {
  'romgrk/barbar.nvim',
  dependencies = {
    'lewis6991/gitsigns.nvim',
    'nvim-tree/nvim-web-devicons',
  },
  init = function()
    vim.g.barbar_auto_setup = false
  end,
  opts = {
    -- Optional configuration
  },
  keys = {
    { '<C-,>', '<cmd>BufferPrevious<cr>', desc = 'Previous buffer' },
    { '<C-.>', '<cmd>BufferNext<cr>', desc = 'Next buffer' },
    { '<C-c>', '<cmd>BufferClose<cr>', desc = 'Close buffer' },
  },
}
