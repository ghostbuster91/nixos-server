local api = vim.api
local map = vim.keymap.set
local lsp = vim.lsp
local diag = vim.diagnostic

local setup = function(navic, binaries)
    local M = {
        on_attach_dap_subscribers = {},
    }
    M.virtual_text = {
        enabled = false,
        enable = function()
            M.virtual_text.enabled = true
            diag.config({ virtual_text = true })
            vim.notify("virtual text enabled", vim.log.levels.INFO, { title = "LSP" })
        end,
        disable = function()
            M.virtual_text.enabled = false
            diag.config({ virtual_text = false })
            vim.notify("virtual text disabled", vim.log.levels.INFO, { title = "LSP" })
        end,
        toggle = function()
            if M.virtual_text.enabled then
                M.virtual_text.disable()
            else
                M.virtual_text.enable()
            end
        end,
    }
    diag.config({ virtual_text = M.virtual_text.enabled })

    M.auto_format = {
        enabled = true,
        enable = function()
            M.auto_format.enabled = true
            vim.notify("auto format enabled", vim.log.levels.INFO, { title = "LSP" })
        end,
        disable = function()
            M.auto_format.enabled = false
            vim.notify("auto format disabled", vim.log.levels.INFO, { title = "LSP" })
        end,
        toggle = function()
            if M.auto_format.enabled then
                M.auto_format.disable()
            else
                M.auto_format.enable()
            end
        end,
    }

    -- actions-preview picks the first available of
    -- { telescope, minipick, snacks, nui }; be explicit now telescope is gone.
    require("actions-preview").setup({ backend = { "snacks" } })

    -- Use an on_attach function to only map the following keys
    -- after the language server attaches to the current buffer
    local lsp_group = api.nvim_create_augroup("lsp", { clear = true })
    local on_attach = function(client, bufnr)
        if client.server_capabilities.documentSymbolProvider then
            navic.attach(client, bufnr)
        end
        local function mapB(mode, l, r, desc)
            local opts = { noremap = true, silent = true, buffer = bufnr, desc = desc }
            map(mode, l, r, opts)
        end

        -- Mappings.

        local vertical = { layout = { preset = "vertical" } }
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        mapB("n", "<leader>rn", lsp.buf.rename, "[lsp] rename")
        mapB("n", "<leader>gD", function()
            lsp.buf.declaration()
        end, "[lsp] goto declaration")
        mapB("n", "<leader>nd", function()
            Snacks.picker.lsp_definitions(vertical)
        end, "[lsp] goto definition")
        mapB("n", "<leader>nD", function()
            Snacks.picker.lsp_type_definitions(vertical)
        end, "[lsp] goto type definition")
        mapB("n", "<leader>ni", function()
            Snacks.picker.lsp_implementations(vertical)
        end, "[lsp] goto implementation")
        mapB("n", "<leader>f", lsp.buf.format, "[lsp] format")
        mapB("n", "<leader>nt", function()
            -- the class/method/function filter now lives in the picker's
            -- `lsp_symbols` source config, see local/snacks.lua
            Snacks.picker.lsp_symbols(vertical)
        end, "[lsp] document symbols")
        map("n", "<Leader>ns", function()
            Snacks.picker.lsp_workspace_symbols(vertical)
        end, { desc = "[lsp] workspace symbols" })
        mapB({ "v", "n" }, "<leader>ca", require("actions-preview").code_actions, "[lsp] code actions")
        mapB("n", "<leader>cl", lsp.codelens.run, "[lsp] code lenses")

        -- mapB("n", "K", lsp.buf.hover, "lsp hover")
        mapB("n", "<Leader>nr", function()
            Snacks.picker.lsp_references(vertical)
        end, "[lsp] references")
        mapB("n", "<leader>sh", lsp.buf.signature_help, "[lsp] signature")

        if client.server_capabilities.documentFormattingProvider then
            local augroup = api.nvim_create_augroup("LspFormatting", { clear = true })
            api.nvim_create_autocmd("BufWritePre", {
                group = augroup,
                buffer = bufnr,
                desc = "format with lsp on save",
                callback = function()
                    if M.auto_format.enabled then
                        lsp.buf.format()
                    end
                end,
            })
        end
        -- Enable inlay hints if the client supports it.
        -- if client.server_capabilities.inlayHintProvider then
        --     vim.lsp.inlay_hint(bufnr, true)
        -- end
    end

    M.spell_check = {
        enabled = false,
        toggle = function()
            if M.spell_check.enabled then
                M.spell_check.disable()
            else
                M.spell_check.enable()
            end
        end,
        enable = function()
            vim.opt.spell = true
            M.spell_check.enabled = true
            vim.notify("Spell check enabled", vim.log.levels.INFO, { title = "spell" })
        end,
        disable = function()
            vim.opt.spell = false
            M.spell_check.enabled = false
            vim.notify("Spell check disabled", vim.log.levels.INFO, { title = "spell" })
        end,
    }
    vim.opt.spell = M.spell_check.enabled

    -- Servers use Neovim's built-in vim.lsp.config/vim.lsp.enable (Neovim
    -- 0.11+). nvim-lspconfig only ships the per-server defaults under
    -- lsp/<name>.lua nowadays; the old require("lspconfig")[name].setup{}
    -- framework is deprecated. Shared config goes through the "*" pseudo-name;
    -- capabilities are set per-server so ts_ls can keep its own set below.
    local capabilities = require("blink.cmp").get_lsp_capabilities({}, true)
    vim.lsp.config("*", { on_attach = on_attach })

    local servers = { "bashls", "vimls", "yamlls", "rust_analyzer", "gopls" }
    for _, name in ipairs(servers) do
        vim.lsp.config(name, { capabilities = capabilities })
    end
    vim.lsp.enable(servers)

    local capabilities_no_format = vim.deepcopy(capabilities)
    capabilities_no_format.textDocument.formatting.dynamicRegistration = false
    capabilities_no_format.textDocument.rangeFormatting.dynamicRegistration = false

    vim.lsp.config("ts_ls", {
        on_attach = function(client, buffer)
            client.server_capabilities.documentFormattingProvider = false
            on_attach(client, buffer)
        end,
        capabilities = capabilities_no_format,
        cmd = {
            binaries.tsserver_path,
            "--stdio",
        },
    })
    vim.lsp.enable("ts_ls")

    -- No `settings.Lua.workspace` here on purpose: local/lazydev.lua owns the
    -- runtime/library configuration and merges whatever it finds in
    -- `client.settings`, so anything set here would be pinned forever. The old
    -- `library = vim.api.nvim_get_runtime_file("*.lua", true)` globbed only the
    -- top level of each runtime dir and resolved to six unrelated files
    -- (example_init.lua, a plugin's repro.lua, ...), never the vim.* meta files.
    vim.lsp.config("lua_ls", {
        capabilities = capabilities,
        cmd = { binaries.lua_language_server },
    })
    vim.lsp.enable("lua_ls")

    vim.lsp.config("nil_ls", {
        capabilities = capabilities,
        settings = {
            ["nil"] = {
                formatting = {
                    command = { binaries.nix_fmt },
                },
                nix = {
                    binary = binaries.nix,
                    flake = {
                        autoArchive = true,
                    },
                },
            },
        },
    })
    vim.lsp.enable("nil_ls")

    local misc_group = api.nvim_create_augroup("misc", { clear = true })
    api.nvim_create_autocmd("FileType", {
        pattern = { "log" },
        callback = function()
            require("baleia").setup({}).once(0)
        end,
        group = misc_group,
    })
    return M
end

return { setup = setup }
