-- blink.cmp — replaces nvim-cmp + cmp-* sources + lspkind.
--
-- The nixpkgs `blink-cmp` derivation ships the prebuilt Rust fuzzy matcher at
-- `target/release/libblink_cmp_fuzzy.so`, so `prebuilt_binaries.download` is
-- turned off: there is nothing to fetch and the store path is read-only.
--
-- Keymaps deliberately mirror the old nvim-cmp ones (preset = "none"), and
-- `selection = { preselect = false, auto_insert = false }` reproduces the old
-- "nothing selected until I move, nothing inserted until I confirm" feel.
local setup = function()
    require("blink.cmp").setup({
        snippets = {
            preset = "luasnip",
            -- lsp(0) > buffer(-2) > snippets(-3) > path(-4), mirroring the old
            -- nvim-cmp source priorities (10 / 9 / 8 / 5).
            score_offset = -3,
        },

        keymap = {
            preset = "none",

            ["<C-p>"] = { "select_prev", "fallback_to_mappings" },
            ["<C-n>"] = { "select_next", "fallback_to_mappings" },

            ["<C-d>"] = { "scroll_documentation_up", "fallback" },
            ["<C-f>"] = { "scroll_documentation_down", "fallback" },

            ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
            ["<C-e>"] = { "cancel", "fallback" },

            -- blink has no insert-vs-replace confirm behaviour, so <S-CR> is
            -- kept only as an alias for muscle memory.
            ["<CR>"] = { "select_and_accept", "fallback" },
            ["<S-CR>"] = { "select_and_accept", "fallback" },

            ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
            ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        },

        appearance = {
            -- kanagawa ships native BlinkCmp* highlights, so don't fall back to
            -- the nvim-cmp groups.
            use_nvim_cmp_as_default = false,
            nerd_font_variant = "mono",
        },

        completion = {
            list = {
                selection = { preselect = false, auto_insert = false },
            },
            menu = {
                border = "rounded",
                draw = {
                    -- lspkind's "symbol_text": icon, then label, then the kind name.
                    columns = {
                        { "kind_icon" },
                        { "label", "label_description", gap = 1 },
                        { "kind" },
                    },
                    components = {
                        label = { width = { fill = true, max = 50 } },
                    },
                },
            },
            documentation = {
                auto_show = true,
                auto_show_delay_ms = 200,
                window = { border = "rounded" },
            },
            ghost_text = { enabled = false },
        },

        sources = {
            default = { "lsp", "buffer", "snippets", "path" },
            providers = {
                lsp = { score_offset = 0 },
                buffer = { score_offset = -2 },
                snippets = { score_offset = 0 },
                path = { score_offset = -4 },
            },
        },

        fuzzy = {
            implementation = "rust",
            prebuilt_binaries = { download = false },
        },

        -- Signature help stays on <leader>sh via vim.lsp.buf.signature_help.
        signature = { enabled = false },
    })
end

return { setup = setup }
