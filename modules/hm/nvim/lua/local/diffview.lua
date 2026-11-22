local map = vim.keymap.set

local setup = function(next_integrations)
    local diffview_actions = require("diffview.actions")
    local diffview = require("diffview")

    -- Conflict navigation through nvim-next, so `;` / `,` repeat it while
    -- resolving a merge.
    local nndv = next_integrations.diffview(diffview_actions)

    diffview.setup({
        keymaps = {
            view = {
                {
                    "n",
                    "[x",
                    nndv.prev_conflict,
                    { desc = "In the merge-tool: jump to the previous conflict" },
                },
                {
                    "n",
                    "]x",
                    nndv.next_conflict,
                    { desc = "In the merge-tool: jump to the next conflict" },
                },
                {
                    "n",
                    "q",
                    function()
                        diffview.close()
                    end,
                    { desc = "Close diffview" },
                },
            },
            file_panel = {
                {
                    "n",
                    "q",
                    function()
                        diffview.close()
                    end,
                    { desc = "Close diffview" },
                },
                {
                    "n",
                    "<ESC>",
                    function()
                        diffview.close()
                    end,
                    { desc = "Close diffview" },
                },
            },
            file_history_panel = {
                {
                    "n",
                    "q",
                    function()
                        diffview.close()
                    end,
                    { desc = "Close diffview" },
                },
                {
                    "n",
                    "<ESC>",
                    function()
                        diffview.close()
                    end,
                    { desc = "Close diffview" },
                },
            },
        },
    })
    map("n", "<leader>hd", function()
        diffview.open({ "--", "%" })
    end, { desc = "Open current file diff" })
    map("n", "<leader>hD", function()
        diffview.open({})
    end, { desc = "Open diff" })

    return diffview
end

return { setup = setup }
