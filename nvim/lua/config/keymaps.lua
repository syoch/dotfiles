-- Keymaps configuration
local map = vim.keymap.set

-- Normal Mode
map('n', '<Space>w', ':<C-u>w<CR>', { desc = 'ファイル保存' })

-- Insert Mode
map('i', 'jj', '<ESC>:<C-u>w<CR>', { desc = 'InsertMode抜けて保存', silent = true })

-- Insert mode movement key bindings
map('i', '<C-d>', '<BS>', { desc = 'Backspace' })
map('i', '<C-h>', '<Left>', { desc = 'Move left' })
map('i', '<C-l>', '<Right>', { desc = 'Move right' })
map('i', '<C-k>', '<Up>', { desc = 'Move up' })
map('i', '<C-j>', '<Down>', { desc = 'Move down' })
