local api = vim.api
local map = vim.keymap.set
local lsp = vim.lsp
local diag = vim.diagnostic

local setup = function(telescope, telescope_builtin, navic, binaries)
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
    -- setup neodev in a way that it loads all plugins when editing dot-files
    local username = vim.fn.expand("$USER")
    local dotfiles_dir = "/home/" .. username .. "/workspace/dot-files"
    require("neodev").setup({
        override = function(root_dir, library)
            if root_dir:find(dotfiles_dir, 1, true) then
                library.enabled = true
                library.plugins = true
            end
        end,
    })
    local lspconfig = require("lspconfig")

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

        local vertical_layout = { layout_strategy = "vertical", fname_width = 80 }
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        mapB("n", "<leader>rn", lsp.buf.rename, "[lsp] rename")
        mapB("n", "<leader>gD", function()
            lsp.buf.declaration(vertical_layout)
        end, "[lsp] goto declaration")
        mapB("n", "<leader>nd", function()
            telescope_builtin.lsp_definitions(vertical_layout)
        end, "[lsp] goto definition")
        mapB("n", "<leader>nD", function()
            telescope_builtin.lsp_type_definitions(vertical_layout)
        end, "[lsp] goto type definition")
        mapB("n", "<leader>ni", function()
            telescope_builtin.lsp_implementations(vertical_layout)
        end, "[lsp] goto implementation")
        mapB("n", "<leader>f", lsp.buf.format, "[lsp] format")
        mapB("n", "<leader>nt", function()
            telescope_builtin.lsp_document_symbols(
                vim.tbl_extend("force", { symbols = { "class", "method", "function" } }, vertical_layout)
            )
        end, "[lsp] document symbols")
        map("n", "<Leader>ns", function()
            telescope_builtin.lsp_dynamic_workspace_symbols(vertical_layout)
        end, { desc = "[lsp] workspace symbols" })
        mapB({ "v", "n" }, "<leader>ca", require("actions-preview").code_actions, "[lsp] code actions")
        mapB("n", "<leader>cl", lsp.codelens.run, "[lsp] code lenses")

        -- mapB("n", "K", lsp.buf.hover, "lsp hover")
        mapB("n", "<Leader>nr", function()
            telescope_builtin.lsp_references(vertical_layout)
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

    -- Use a loop to conveniently call 'setup' on multiple servers and
    -- map buffer local keybindings when the language server attaches
    -- local capabilities = vim.lsp.protocol.make_client_capabilities()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()
    local servers = { "bashls", "vimls", "yamlls", "rust_analyzer", "gopls" }
    for _, lsp in ipairs(servers) do
        lspconfig[lsp].setup({
            on_attach = on_attach,
            capabilities = capabilities,
            -- after 150ms of no calls to lsp, send call
            -- compare with throttling that is done by default in compe
            -- flags = {
            --   debounce_text_changes = 150,
            -- }
        })
    end

    local capabilities_no_format = lsp.protocol.make_client_capabilities()
    capabilities_no_format.textDocument.formatting = false
    capabilities_no_format.textDocument.rangeFormatting = false
    capabilities_no_format.textDocument.range_formatting = false

    require("lspconfig")["ts_ls"].setup({
        on_attach = function(client, buffer)
            client.server_capabilities.document_formatting = false
            client.server_capabilities.document_range_formatting = false
            on_attach(client, buffer)
        end,
        capabilities = capabilities_no_format,
        cmd = {
            binaries.tsserver_path,
            "--stdio",
        },
    })
    local library = vim.api.nvim_get_runtime_file("*.lua", true)
    require("lspconfig").lua_ls.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        cmd = { binaries.lua_language_server },
        settings = {
            Lua = {
                workspace = {
                    -- Make the server aware of Neovim runtime files
                    checkThirdParty = false,
                    library = library,
                },
            },
        },
    })
    require("lspconfig").nil_ls.setup({
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
