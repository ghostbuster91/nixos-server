local api = require("nvim-tree.api")
local openfile = require("nvim-tree.actions.node.open-file")
local M = {}

-- Pickers launched from inside the tree have to hand the file to nvim-tree's
-- own open-file, or it would be edited in the tree window itself.
local function view_selection(picker, item)
    picker:close()
    if not item then
        return
    end
    local path = Snacks.picker.util.path(item)
    vim.schedule(function()
        openfile.fn("edit", path)
        -- grep results carry a position; the telescope version dropped it
        if item.pos and item.pos[1] > 0 then
            vim.api.nvim_win_set_cursor(0, { item.pos[1], item.pos[2] })
            vim.cmd("norm! zzzv")
        end
    end)
end

-- directory of the node under the cursor
local function basedir()
    local node = api.tree.get_node_under_cursor()
    local is_folder = node.fs_stat and node.fs_stat.type == "directory" or false
    return is_folder and node.absolute_path or vim.fn.fnamemodify(node.absolute_path, ":h")
end

function M.launch_live_grep()
    return Snacks.picker.grep({
        cwd = basedir(),
        layout = { preset = "vertical" },
        confirm = view_selection,
    })
end

function M.launch_find_files()
    return Snacks.picker.files({
        cwd = basedir(),
        confirm = view_selection,
    })
end

return M
