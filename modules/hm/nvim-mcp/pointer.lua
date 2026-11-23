-- What "this line" / "ten fragment" points at -- resolved once, shown on screen.
--
-- `NvimMcpPointer.resolve()` is the single answer to "where is the user
-- pointing", and FocusLost paints that same answer, so the screen agrees with
-- what Claude got: tmux draws no cursor in an inactive pane, and a selection
-- the user is holding is worth seeing while they type the question about it.
--
-- A selection counts only while visual mode is **live**. `'<`/`'>` are never
-- read: they outlive the selection by design (and leaving visual mode parks the
-- cursor *at* the range end, so every "is it still current?" heuristic on top
-- of them keeps a long-dead range alive). <Esc> means never mind -- then the
-- cursor is the pointer.

local api = vim.api
local ns = api.nvim_create_namespace("nvim_mcp_pointer")
local group = api.nvim_create_augroup("nvim_mcp_pointer", { clear = true })

api.nvim_set_hl(0, "McpPointerSelection", { link = "Visual", default = true })
api.nvim_set_hl(0, "McpPointerLine", { link = "CursorLine", default = true })
-- Terminal colorschemes rarely style `Cursor` (in the TUI the cursor is the
-- terminal's own), so draw the cell ourselves.
api.nvim_set_hl(0, "McpPointerCursor", { reverse = true, default = true })

local M = {}

local VISUAL = { v = true, V = true, ["\22"] = true, s = true, S = true, ["\19"] = true }
local LINEWISE = { V = true, S = true }

-- Buffer currently carrying the pointer highlight, if any.
local painted = nil

-- Re-sourcing this file (editing it, then `:luafile`) leaves the previous
-- instance's extmarks behind with nothing holding the handle to clear them.
for _, buf in ipairs(api.nvim_list_bufs()) do
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

local function line_at(buf, row)
    return api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
end

-- Byte column (exclusive, 0-based) just past the character that the inclusive
-- 1-based `col` points at -- the selection end and the cursor both address a
-- character, not a gap between two.
local function past_char(line, col)
    local start = math.min(col, #line)
    if start < 1 then
        return 0
    end
    local ok, tail = pcall(vim.str_utf_end, line, start)
    return start + (ok and tail or 0)
end

-- The selection in progress: `getpos("v")` is its anchor, the cursor the moving
-- end, and they come in either order.
local function selection(win)
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    if not VISUAL[mode] then
        return nil
    end
    local a, b = vim.fn.getpos("v"), api.nvim_win_get_cursor(win)
    local s, e = { a[2], a[3] }, { b[1], b[2] + 1 }
    if s[1] > e[1] or (s[1] == e[1] and s[2] > e[2]) then
        s, e = e, s
    end
    -- Blockwise collapses to the enclosing charwise range; good enough to point at.
    return s, e, LINEWISE[mode] or false
end

--- Where the user is pointing. All rows and columns are 1-based, as the file
--- shows them. `kind` is "selection" (visual mode is live -- use the range as
--- given) or "cursor" (a single spot; widen it yourself, e.g. to the enclosing
--- symbol).
function M.resolve()
    local win = api.nvim_get_current_win()
    local buf = api.nvim_win_get_buf(win)
    local cur = api.nvim_win_get_cursor(win)
    local out = {
        kind = "cursor",
        buffer_id = buf,
        buffer_name = api.nvim_buf_get_name(buf),
        modified = vim.bo[buf].modified,
        mode = api.nvim_get_mode().mode,
        cursor_row = cur[1],
        cursor_col = cur[2] + 1,
    }
    local s, e, linewise = selection(win)
    if s then
        out.kind = "selection"
        out.start_row, out.start_col = s[1], s[2]
        out.end_row = e[1]
        out.end_col = linewise and #line_at(buf, e[1]) or e[2]
        out.linewise = linewise
    end
    return out
end

local function clear()
    if painted then
        if api.nvim_buf_is_valid(painted) then
            api.nvim_buf_clear_namespace(painted, ns, 0, -1)
        end
        painted = nil
    end
end

local function paint_selection(buf, s, e, linewise)
    local line = line_at(buf, e[1])
    api.nvim_buf_set_extmark(buf, ns, s[1] - 1, math.max(s[2] - 1, 0), {
        end_row = e[1] - 1,
        end_col = linewise and #line or past_char(line, e[2]),
        hl_group = "McpPointerSelection",
        hl_eol = linewise,
        priority = 200,
    })
end

local function paint_cursor(buf, row, col)
    api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
        line_hl_group = "McpPointerLine",
        priority = 199,
    })
    local line = line_at(buf, row)
    if col <= #line then
        api.nvim_buf_set_extmark(buf, ns, row - 1, col - 1, {
            end_col = past_char(line, col),
            hl_group = "McpPointerCursor",
            priority = 200,
        })
    else
        -- Past the last character (empty line, or `virtualedit`): nothing to
        -- recolour, so stand a cell in for the missing terminal cursor.
        api.nvim_buf_set_extmark(buf, ns, row - 1, #line, {
            virt_text = { { " ", "McpPointerCursor" } },
            virt_text_pos = "overlay",
            priority = 200,
        })
    end
end

api.nvim_create_autocmd("FocusLost", {
    group = group,
    desc = "Show what Claude resolves 'this' to while the editor is unfocused",
    callback = function()
        clear()
        local win = api.nvim_get_current_win()
        local buf = api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype ~= "" then
            return
        end
        painted = buf
        local s, e, linewise = selection(win)
        if s then
            paint_selection(buf, s, e, linewise)
        else
            local cur = api.nvim_win_get_cursor(win)
            paint_cursor(buf, cur[1], cur[2] + 1)
        end
    end,
})

-- FocusGained is the real signal; the others only fire when the user is
-- demonstrably back in the editor, and keep the highlight from sticking on a
-- terminal that reports no focus events at all.
api.nvim_create_autocmd({ "FocusGained", "ModeChanged", "CursorMoved", "CursorMovedI", "TextChanged" }, {
    group = group,
    desc = "Drop the nvim-mcp pointer highlight",
    callback = clear,
})

-- The MCP side reads this (`exec_lua`), so there is one implementation of
-- "where is the user pointing" rather than one per consumer. No `return` here:
-- the file is inlined into a shared Lua chunk, where it would cut the rest off.
_G.NvimMcpPointer = M
