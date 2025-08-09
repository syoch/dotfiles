-- Editor options
local opt = vim.opt

-- Encoding
vim.g.encoding = 'utf-8'

-- Line numbers and UI
opt.number = true           -- 行番号表示
opt.ruler = true            -- カーソルの位置表示
opt.cursorline = true       -- カーソルハイライト

-- Window splitting
opt.splitbelow = true       -- 水平分割時に下に表示
opt.splitright = true       -- 縦分割時を右に表示
opt.equalalways = false     -- 分割時に自動調整を無効化

-- Command line
opt.wildmenu = true         -- コマンドモードの補完

-- Tab settings
opt.expandtab = true        -- tabを複数のspaceに置き換え
opt.tabstop = 2            -- tabは半角2文字
opt.shiftwidth = 2         -- tabの幅

vim.g.have_nerd_font = true
vim.o.showmode = false
vim.o.mouse = 'a'
opt.termguicolors = true
opt.winblend = 0 -- ウィンドウの不透明度
opt.pumblend = 0 -- ポップアップメニューの不透明度
