local map = vim.keymap.set

-- neoclip only ships telescope and fzf-lua pickers, so the snacks picker over
-- its yank history is hand-rolled here. The keys mirror neoclip's own
-- telescope defaults (`settings.keys.telescope`), and the on_select/on_paste
-- settings are honoured the same way its built-in pickers do.
local setup = function()
    require("neoclip").setup()

    local handlers = require("neoclip.handlers")
    local storage = require("neoclip.storage")
    local picker_utils = require("neoclip.picker_utils")
    local settings = require("neoclip.settings").get()

    -- used as the finder, so it re-reads the history on every refresh
    local function items()
        local ret = {}
        for i, entry in ipairs(storage.get().yanks) do
            ret[i] = {
                -- one line per entry: show escaped newlines, like the
                -- telescope/fzf pickers do
                text = table.concat(entry.contents, "\\n"),
                entry = entry,
                preview = {
                    text = table.concat(entry.contents, "\n"),
                    ft = entry.filetype,
                    loc = false,
                },
            }
        end
        return ret
    end

    ---@param registers string[] registers the picked entry is written to
    local function pick(registers)
        -- the paste actions run `normal!`, so they have to wait for the picker
        -- to give the focus back to the editor window
        local function after_close(fn)
            return function(picker, item)
                if not item then
                    return
                end
                picker:close()
                vim.schedule(function()
                    fn(item.entry)
                end)
            end
        end

        local function paste(op)
            return after_close(function(entry)
                if settings.on_paste.set_reg then
                    handlers.set_registers(registers, entry)
                end
                handlers.paste(entry, op)
                if settings.on_paste.move_to_front then
                    storage.set_as_most_recent("yanks", entry)
                end
            end)
        end

        Snacks.picker.pick({
            title = picker_utils.make_prompt_title(registers),
            finder = items,
            format = "text",
            preview = "preview",
            confirm = after_close(function(entry)
                handlers.set_registers(registers, entry)
                if settings.on_select.move_to_front then
                    storage.set_as_most_recent("yanks", entry)
                end
            end),
            actions = {
                neoclip_paste = paste("p"),
                neoclip_paste_behind = paste("P"),
                neoclip_delete = function(picker, item)
                    if not item then
                        return
                    end
                    handlers.delete("yanks", item.entry)
                    picker:find()
                end,
            },
            win = {
                input = {
                    keys = {
                        ["<c-p>"] = { "neoclip_paste", mode = { "i", "n" } },
                        ["<c-k>"] = { "neoclip_paste_behind", mode = { "i", "n" } },
                        ["<c-d>"] = { "neoclip_delete", mode = { "i", "n" } },
                    },
                },
                list = {
                    keys = {
                        ["p"] = "neoclip_paste",
                        ["P"] = "neoclip_paste_behind",
                        ["d"] = "neoclip_delete",
                    },
                },
            },
        })
    end

    map("n", "<leader>'", function()
        pick({ "*" })
    end, { desc = "clipboard" })
end

return { setup = setup }
