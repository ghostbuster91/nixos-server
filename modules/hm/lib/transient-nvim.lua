-- Is this Neovim one of git's throwaway instances?
--
-- git spawns a Neovim to edit a commit/merge/rebase message and exits it right
-- after. Those load the same config, so without this check every one of them
-- announces itself as an editor for its git root -- and both bridges to Claude
-- resolve a root to exactly one editor: `nvim-mcp --connect auto` picks a
-- socket, `claude --ide` picks a lockfile. Either can land on the instance that
-- is about to exit.
--
-- A global rather than a `return`, for the same reason as pointer.lua's: this
-- file is inlined into a shared Lua chunk, where a `return` would cut the rest
-- of it off. Every bridge module inlines it, so the assignment runs more than
-- once -- it is a pure function, so that costs nothing.
_G.ClaudeNvimTransient = function()
  for _, arg in ipairs(vim.fn.argv()) do
    if
      arg:match("COMMIT_EDITMSG$")
      or arg:match("MERGE_MSG$")
      or arg:match("git%-rebase%-todo$")
      or arg:match("TAG_EDITMSG$")
    then
      return true
    end
  end
  return false
end
