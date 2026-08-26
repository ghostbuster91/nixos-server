local setup = function()
    local neoscroll = require("neoscroll")
    neoscroll.setup()
    local modes = { "n", "v", "x" }
    vim.keymap.set(modes, "<C-u>", function() neoscroll.ctrl_u({ duration = 250 }) end)
    vim.keymap.set(modes, "<C-d>", function() neoscroll.ctrl_d({ duration = 250 }) end)
    vim.keymap.set(modes, "zt", function() neoscroll.zt({ half_win_duration = 250 }) end)
    vim.keymap.set(modes, "zz", function() neoscroll.zz({ half_win_duration = 250 }) end)
    vim.keymap.set(modes, "zb", function() neoscroll.zb({ half_win_duration = 250 }) end)
end

return { setup = setup }
