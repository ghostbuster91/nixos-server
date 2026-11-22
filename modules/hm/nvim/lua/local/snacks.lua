local api = vim.api
local map = vim.keymap.set

-- snacks.nvim is a bundle of small modules, each enabled by passing a (possibly
-- empty) table to setup. It replaces, in this config:
--   * telescope + telescope-fzf-native + telescope-ui-select + telescope-undo
--     -> snacks.picker (own matcher, no native dependency; `ui_select` is on by
--        default and takes over vim.ui.select)
--   * indent-blankline -> snacks.indent
--   * neoscroll        -> snacks.scroll (hooks window scrolls, no keymaps)
--   * gitlinker        -> snacks.gitbrowse
-- The clipboard picker that used to be a telescope extension lives in
-- lua/local/neoclip.lua; notifications are routed here from noice.
local setup = function(diffview)
    -- telescope's `layout_strategy = "vertical"` equivalent, used by the
    -- pickers whose entries are long (paths + text).
    local vertical = { layout = { preset = "vertical" } }

    require("snacks").setup({
        bigfile = {},
        quickfile = {},
        input = {},
        notifier = {},
        indent = {
            indent = { char = "▏" },
            -- scope highlighting was off with indent-blankline too; with no
            -- scope there is nothing left to animate.
            scope = { enabled = false },
            animate = { enabled = false },
        },
        scroll = {
            -- matches the 250ms neoscroll used for <C-u>/<C-d>/zz
            animate = { duration = { step = 10, total = 250 } },
        },
        picker = {
            -- telescope ran "flex" with flip_columns = 15, i.e. horizontal in
            -- any real terminal. snacks' own default flips to vertical below
            -- 120 columns, so pin the horizontal preset instead.
            layout = {
                preset = "telescope",
                layout = { backdrop = false },
            },
            -- telescope had a custom buffer_previewer_maker that skipped
            -- files over 100kB.
            previewers = { file = { max_size = 100 * 1024 } },
            win = {
                -- `f` sent the selection to the quickfix list in normal mode
                input = { keys = { ["f"] = { "qflist", mode = "n" } } },
                list = { keys = { ["f"] = "qflist" } },
            },
            sources = {
                buffers = {
                    -- was actions.delete_buffer + actions.move_to_top
                    win = { input = { keys = { ["<c-d>"] = { "bufdelete", mode = { "i", "n" } } } } },
                },
                -- open the commit under the cursor in diffview instead of
                -- checking it out (snacks' default confirm is git_checkout)
                git_log_file = {
                    confirm = function(picker, item)
                        picker:close()
                        if item and item.commit then
                            diffview.open(item.commit .. "~1..." .. item.commit)
                        end
                    end,
                },
                -- telescope's lsp_document_symbols was filtered down to
                -- class/method/function; keep that for every filetype that has
                -- a kind filter.
                lsp_symbols = {
                    filter = {
                        default = { "Class", "Method", "Function" },
                        lua = { "Class", "Method", "Function" },
                    },
                },
            },
        },
    })

    -- Put the picker back on the editor background.
    --
    -- snacks' panes are floats, so they render on NormalFloat. kanagawa makes
    -- that sumiInk0 (#16161d, fg #c8c093) against Normal's sumiInk3 (#1f1f28,
    -- fg #dcd7ba), i.e. near-black and dimmer text. Telescope escaped this
    -- because kanagawa ships explicit Telescope* highlights; snacks has none.
    --
    --   * `SnacksPicker` is the base group every pane links to (list, input,
    --     …), so overriding it covers all of them. The preview pane already
    --     renders on `Normal`.
    --   * border/title/footer keep their own fg but have to take that same
    --     background, or the float bg stays behind them as a dark ring. The
    --     per-pane variants (SnacksPickerListBorder, …) link to these.
    --   * `SnacksPickerDir` defaults to `NonText`, which greys out the dirname
    --     of every path; telescope drew the whole path in the normal fg.
    --
    -- snacks declares these with `default = true` when a picker first opens,
    -- so an explicit definition wins no matter which runs first. `colorscheme`
    -- wipes them, hence the autocmd — kanagawa is applied from init.vim before
    -- this runs, so the initial call already sees the real colors.
    local hl_augroup = api.nvim_create_augroup("snacks_picker_hl", { clear = true })
    local function picker_highlights()
        local bg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
        api.nvim_set_hl(0, "SnacksPicker", { link = "Normal" })
        api.nvim_set_hl(0, "SnacksPickerDir", { link = "Normal" })
        for _, part in ipairs({ "Border", "Title", "Footer" }) do
            local hl = api.nvim_get_hl(0, { name = "Float" .. part, link = false })
            hl.bg = bg
            api.nvim_set_hl(0, "SnacksPicker" .. part, hl)
        end
    end
    picker_highlights()
    api.nvim_create_autocmd("ColorScheme", { group = hl_augroup, callback = picker_highlights })

    -- `commands` confirms with the built-in `cmd` action, which drops the
    -- command on the cmdline instead of running it — the behaviour the
    -- telescope config hand-rolled for its `commands` picker.
    map("n", "<Leader>/", function()
        Snacks.picker.commands()
    end, { desc = "show commands" })
    map("n", "<Leader>gwd", function()
        Snacks.picker.diagnostics(vertical)
    end, { desc = "diagnostics" })
    map("n", "<leader>ec", function()
        Snacks.picker.git_log_file()
    end, { desc = "Buffer commites" })
    map("n", "<leader>ti", function()
        Snacks.picker.grep(vertical)
    end, { desc = "Live grep" })
    map("v", "<leader>ti", function()
        Snacks.picker.grep_word(vertical)
    end, { desc = "Grep string" })
    map("n", "<leader>gh", function()
        Snacks.picker.git_log()
    end, { desc = "Commites" })
    map("n", "<leader>ts", function()
        Snacks.picker.git_status()
    end, { desc = "Git status" })
    map("n", "<leader>tf", function()
        Snacks.picker.git_files()
    end, { desc = "Git files" })
    map("n", "<leader>tt", function()
        Snacks.picker.files()
    end, { desc = "Files" })
    map("n", "<leader>th", function()
        Snacks.picker.buffers(vertical)
    end, { desc = "Buffers" })
    map("n", "<leader>hh", function()
        Snacks.picker.help()
    end, { desc = "Help tags" })
    map("n", "<leader>tr", function()
        Snacks.picker.resume()
    end, { desc = "Picker resume" })
    map("n", "<leader>u", function()
        Snacks.picker.undo()
    end, { desc = "Undo tree" })
    map("n", "<leader>sn", function()
        Snacks.picker.notifications()
    end, { desc = "Notification history" })

    -- gitlinker's single default mapping: copy a permalink to the clipboard.
    -- `Snacks.gitbrowse()` on its own opens the url in a browser.
    map({ "n", "x" }, "<leader>gy", function()
        Snacks.gitbrowse({
            what = "permalink",
            open = function(url)
                vim.fn.setreg("+", url)
                Snacks.notify.info(url, { title = "Git Browse" })
            end,
            notify = false,
        })
    end, { desc = "copy git permalink" })
end

return { setup = setup }
