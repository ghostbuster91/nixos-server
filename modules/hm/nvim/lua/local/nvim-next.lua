-- Repeatable movements engine. Every next/prev motion that goes through
-- nvim-next is remembered, so `;` repeats it forward and `,` backward — one
-- pair of keys for f/t, diagnostics, git hunks, quickfix and merge conflicts
-- instead of each plugin claiming `;` for itself.
--
-- `repeat_style = "directional"`: `;` always moves forward and `,` always
-- backward, whatever the direction of the original move ("original" would
-- instead repeat the move as typed, so `;` after `[d` would go backward).
--
-- Returns the integrations table; callers hand their own next/prev functions
-- to it (see local/gitsigns.lua, local/diffview.lua).
local setup = function()
    local builtins = require("nvim-next.builtins")
    require("nvim-next").setup({
        default_mappings = {
            repeat_style = "directional",
        },
        -- Let the builtin f/F/t/T go through the engine as well, so `;` after
        -- `fx` keeps behaving as in stock vim once nvim-next owns the key.
        items = {
            builtins.f,
            builtins.t,
        },
    })

    local integrations = require("nvim-next.integrations")

    -- ]q / [q
    integrations.quickfix().setup()

    -- ]d / [d, with the opts these mappings always had
    local nndiag = integrations.diagnostic()
    local jump_opts = {
        float = false,
        wrap = false,
        severity = { min = vim.diagnostic.severity.WARN },
    }
    vim.keymap.set("n", "[d", nndiag.goto_prev(jump_opts), { desc = "nvim-next: previous diagnostic" })
    vim.keymap.set("n", "]d", nndiag.goto_next(jump_opts), { desc = "nvim-next: next diagnostic" })

    return integrations
end

return { setup = setup }
