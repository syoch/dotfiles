-- Hyprlang LSP configuration
return {
  'luckasRanarison/tree-sitter-hyprlang',
  config = function()
    -- Setup Hyprlang filetype detection
    vim.filetype.add({
      pattern = {
        ['.*%.hl'] = 'hyprlang',
        ['hypr.*%.conf'] = 'hyprlang',
      },
    })

    -- Setup LSP autocmd
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
      pattern = { "*.hl", "hypr*.conf" },
      callback = function(event)
        vim.lsp.start {
          name = "hyprlang",
          cmd = { "hyprls" },
          root_dir = vim.fn.getcwd(),
        }
      end
    })
  end,
}
