-- tmux's window-style/window-active-style only dims cells a program left
-- uncolored; Neovim paints every cell itself, so switching tmux panes away
-- from it shows no change. `focus-events on` (tmux config) means Neovim still
-- gets FocusLost/FocusGained on pane switch — cover every window with a dark
-- floating overlay to fake the same dimming tmux gives plain shell panes.
local M = {}

local OPACITY = 80

local overlays = {}

local function cover_window(winid)
    local info = vim.fn.getwininfo(winid)[1]
    local bufid = vim.api.nvim_create_buf(false, true)
    local overlay_winid = vim.api.nvim_open_win(bufid, false, {
        relative = "editor",
        row = info.winrow - 1,
        col = info.wincol - 1,
        width = info.width,
        height = info.height,
        style = "minimal",
        focusable = false,
        zindex = 200,
    })
    vim.wo[overlay_winid].winhighlight = "Normal:FocusDimOverlay"
    vim.wo[overlay_winid].winblend = OPACITY
    return { winid = overlay_winid, bufid = bufid }
end

local function dim()
    if #overlays > 0 then
        return
    end
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(winid).relative == "" then
            table.insert(overlays, cover_window(winid))
        end
    end
end

local function undim()
    for _, overlay in ipairs(overlays) do
        if vim.api.nvim_win_is_valid(overlay.winid) then
            vim.api.nvim_win_close(overlay.winid, true)
        end
        if vim.api.nvim_buf_is_valid(overlay.bufid) then
            vim.api.nvim_buf_delete(overlay.bufid, { force = true })
        end
    end
    overlays = {}
end

function M.setup()
    vim.api.nvim_set_hl(0, "FocusDimOverlay", { bg = "#000000" })

    local group = vim.api.nvim_create_augroup("local_focus_dim", { clear = true })
    vim.api.nvim_create_autocmd("FocusLost", { group = group, callback = dim })
    vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = undim })
    -- in case the layout changed while unfocused (shouldn't normally happen)
    vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, { group = group, callback = undim })
end

return M
