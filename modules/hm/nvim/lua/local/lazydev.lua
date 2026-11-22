-- lazydev.nvim — replaces neodev.nvim for editing this config's own Lua.
--
-- neodev worked by patching nvim-lspconfig's `require("lspconfig").lua_ls.setup{}`.
-- Since lua/local/lsp.lua moved to vim.lsp.config/vim.lsp.enable, lspconfig's
-- framework is never require'd, so neodev was a silent no-op and lua_ls had no
-- idea what `vim` was ("Undefined global `vim`").
--
-- lazydev talks to LuaLS directly and owns `Lua.runtime` + `Lua.workspace`: the
-- $VIMRUNTIME library (where the vim.* `---@meta` files live) is always added,
-- and plugin libraries are added lazily as the open buffers `require("…")` them.
--
-- Two things will fight it:
--   * setting `settings.Lua.workspace.library` on the lua_ls config — lazydev
--     merges whatever is already there, so junk entries stick permanently;
--   * a `.luarc.json` in the workspace, which overrides what lazydev negotiates
--     (lazydev warns about it in :LazyDev debug).
local setup = function()
    require("lazydev").setup({
        integrations = {
            -- nvim-cmp and coq aren't installed; the blink.cmp source for
            -- `require("…")` / `---@module` is registered in local/blink.lua.
            cmp = false,
            coq = false,
            -- Keeps lua_ls' root_dir in sync with the lazydev workspace, which
            -- matters because vim.lsp.config resolves roots from markers only.
            lspconfig = true,
        },
        library = {
            -- luv types, pulled in only once a file mentions vim.uv
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        },
    })
end

return { setup = setup }
