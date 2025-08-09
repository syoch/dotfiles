-- NERDTree configuration
return {
  'preservim/nerdtree',
  cmd = { 'NERDTree', 'NERDTreeToggle', 'NERDTreeFind' },
  keys = {
    { '<leader>e', '<cmd>NERDTreeToggle<cr>', desc = 'Toggle NERDTree' },
  },
  config = function()
    -- NERDTree settings can be added here
    vim.g.NERDTreeShowHidden = 1
  end,
}
