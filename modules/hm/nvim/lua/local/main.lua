local setup = function(binaries)
    -- globals
    local api = vim.api
    local map = vim.keymap.set
    local global_opt = vim.opt_global
    local diag = vim.diagnostic

    global_opt.clipboard = "unnamed"
    global_opt.timeoutlen = 200
    vim.o.signcolumn = "yes"
    -- YANK highlight
    vim.cmd([[autocmd TextYankPost * silent! lua vim.highlight.on_yank {}]])

    vim.cmd([[au BufRead,BufNewFile *.smithy setfiletype smithy]])
    vim.cmd([[au BufRead,BufNewFile *.log setfiletype log]])
    vim.cmd([[au BufRead,BufNewFile flake.lock setfiletype json]])
    vim.cmd([[au BufRead,BufNewFile package.lock setfiletype json]])

    -- <CTRL> + a and <CTRL> + e move to the beginning and the end of the line
    map("c", "<C-a>", "<HOME>", { noremap = true })
    map("c", "<C-e>", "<END>", { noremap = true })
    -- }

    map("n", "<F11>", ":wall<CR>", { noremap = true, silent = true })
    map("n", "<leader>su", function()
        diag.setqflist()
    end, { desc = "Diagnostics into qflist" })
    map("n", "<leader>se", function()
        diag.setqflist({ severity = "E" })
    end, { desc = "Diagnostics[E] into qflist" })

    local toggle_qf = function()
        local qf_exists = false
        for _, win in pairs(vim.fn.getwininfo()) do
            if win["quickfix"] == 1 then
                qf_exists = true
            end
        end
        if qf_exists == true then
            vim.cmd("cclose")
            return
        end
        vim.cmd("copen")
    end
    map("n", "<leader>to", toggle_qf, { desc = "qflist toggle" })

    local navic = require("nvim-navic")

    local hocon_group = api.nvim_create_augroup("hocon", { clear = true })
    api.nvim_create_autocmd(
        { "BufNewFile", "BufRead" },
        { group = hocon_group, pattern = "*/resources/*.conf", command = "set ft=hocon" }
    )

    require("nvim-autopairs").setup({
        enable_check_bracket_line = false,
        check_ts = true,
    })

    require("Comment").setup()
    local ft = require("Comment.ft")
    ft.smithy = "//%s"

    require("neoclip").setup()
    require("telescope").load_extension("neoclip")
    map("n", "<leader>'", require("telescope").extensions.neoclip.star, { desc = "clipboard" })

    require("ibl").setup({
        indent = { char = "▏" },
        scope = { enabled = false },
    })

    require("fidget").setup()

    require("nvim-lightbulb").setup({
        autocmd = { enabled = true },
    })

    require("goto-preview").setup({
        default_mappings = true,
    })

    map("n", "k", function()
        diag.open_float()
    end, { desc = "show diagnostic under the cursor" })

    map("n", "[q", function()
        local status = pcall(vim.cmd, "cprevious")
        if not status then
            vim.notify("No more items", vim.log.levels.INFO, { title = "Quickfix" })
        end
    end, { desc = "prev qfix" })

    map("n", "[d", function()
        diag.jump({ count = -1, float = false, wrap = false, severity = { min = diag.severity.WARN } })
    end, { desc = "previous diagnostic" })
    map("n", "]d", function()
        diag.jump({ count = 1, float = false, wrap = false, severity = { min = diag.severity.WARN } })
    end, { desc = "next diagnostic" })

    require("gitlinker").setup()

    local hocon_group = vim.api.nvim_create_augroup("hocon", { clear = true })
    vim.api.nvim_create_autocmd(
        { "BufNewFile", "BufRead" },
        { group = hocon_group, pattern = "*.conf", command = "set ft=hocon" }
    )
    require("ssr").setup({
        border = "rounded",
        min_width = 50,
        min_height = 5,
        max_width = 120,
        max_height = 25,
        adjust_window = true,
        keymaps = {
            close = "q",
            next_match = "n",
            prev_match = "N",
            replace_confirm = "<cr>",
            replace_all = "<leader><cr>",
        },
    })

    require("local/trouble").setup()
    local diffview = require("local/diffview").setup()
    local telescope = require("local/telescope").setup(diffview)
    require("local/noice").setup(telescope.core)
    ---@diagnostic disable-next-line: undefined-global
    local lsp = require("local/lsp").setup(telescope.core, telescope.builtin, navic, binaries)
    require("local/gitsigns").setup()
    local luasnip = require("local/luasnip").setup()
    require("local/cmp").setup(luasnip)
    require("local/lualine").setup(navic)
    require("local/treesitter").setup()
    require("local/neoscroll").setup()
    require("local/smart-split").setup()
    require("local/dial").setup()
    require("local/hydra").setup(lsp)
    require("local/neotree").setup()
    require("which-key").setup()
    require("local/substitute").setup()
    require("local/neogit").setup()
    require("local/flash").setup()
    require("local/hover").setup()
end

return { setup = setup }
