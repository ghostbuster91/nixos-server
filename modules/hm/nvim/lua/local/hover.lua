-- hover.nvim's API changed upstream and broke this file three ways:
--
--   * `require("hover").register(...)` is gone — `K` died with "attempt to call
--     field 'register' (a nil value)". Providers are now declared as *module
--     names* in `config{}` and loaded by `hover.providers`.
--   * providers are filtered by module name (`vim.tbl_contains(opts.providers,
--     provider.module)`), so `mouse_providers = { "LSP" }` — a display name —
--     silently matched nothing.
--   * the old entry points are @deprecated aliases: setup() -> config(),
--     hover() -> open(), hover_select() -> select().
--
-- The hand-rolled LSPWithDiagSource that merged LSP hover with the cursor's
-- diagnostics is obsolete too: upstream ships `hover.providers.diagnostic`
-- (priority 1001, i.e. ranked above `hover.providers.lsp`), which is exactly
-- what that workaround existed for.
--
-- `providers` must stay a complete list — `config{}` runs it through
-- vim.tbl_deep_extend, which *replaces* list-like tables rather than merging
-- them, so listing two entries drops the upstream dap/man/dictionary defaults.
local setup = function()
    require("hover").config({
        providers = {
            "hover.providers.diagnostic",
            "hover.providers.lsp",
        },
        mouse_providers = { "hover.providers.lsp" },
        preview_opts = {
            border = "single",
        },
        -- Whether the contents of a currently open hover window should be moved
        -- to a :h preview-window when pressing the hover keymap.
        preview_window = false,
        title = true,
        mouse_delay = 1000,
    })

    -- Setup keymaps.
    --
    -- select() must be handed an explicit table: unlike open()/switch() it never
    -- does `opts = opts or {}`, so the nil that a keymap callback passes reaches
    -- get_providers() and dies on `opts.pos = ...` (hover/actions.lua:25).
    vim.keymap.set("n", "K", require("hover").open, { desc = "hover.nvim" })
    vim.keymap.set("n", "gK", function()
        require("hover").select({})
    end, { desc = "hover.nvim (select)" })
end

return { setup = setup }
