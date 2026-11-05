---
name: nvim-cursor-context
description: Resolve deictic references to code ("this line", "this function", "this fragment", "here", "ta linijka", "ten fragment", "ta funkcja", "tutaj", "to") to what the user is actually pointing at in Neovim — the visual selection range for a fragment, the cursor position for a single spot — via the nvim MCP server. Use BEFORE searching the repo whenever a request points at code without naming a file, symbol or line number.
---

# What the user is pointing at in Neovim

The user drives an editor you can query. When they say "this" about code, they
mean **where their cursor or selection is right now** — not something you should
guess from the conversation or find by grepping.

## Trigger

Any request that points at code without naming it. English or Polish:

- "what does **this line** do?", "fix **this**", "refactor **this function**",
  "why is **this fragment** slow?", "add a test for **this**", "**here** it
  returns nil"
- "co robi **ta linijka**?", "popraw **to**", "zrefaktoruj **tę funkcję**",
  "wytłumacz **ten fragment**", "**tutaj** się sypie"

Also triggers when the pointer is implicit: "add a docstring" / "rename it" with
no target given.

**Does not** trigger when the user names the target (`foo.nix:42`, "the
`mkHost` function", "in `flake.nix`") — then use what they named.

## Procedure

1. **Find the connection.** Read the `nvim-connections://` resource and take the
   `id` of the connection for the current project. The server runs with
   `--connect auto`, so it is already connected; every other tool needs that
   `connection_id`. More than one connection and no obvious match → ask, do not
   pick at random.

2. **"fragment" / a region → check the selection range first.** Get the last
   visual selection via `exec_lua`:

   ```lua
   local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
   local cur = vim.api.nvim_win_get_cursor(0)
   return {
     buf = vim.api.nvim_get_current_buf(),
     name = vim.api.nvim_buf_get_name(0),
     mode = vim.fn.mode(),
     -- 1-based rows, as in the file; 0 means "no selection in this buffer"
     sel_start_row = s[2], sel_start_col = s[3],
     sel_end_row = e[2], sel_end_col = e[3],
     cursor_row = cur[1],
   }
   ```

   `'<` / `'>` are per-buffer and **survive the selection** — they can be stale.
   Trust the range only when it is non-degenerate (`sel_start_row > 0` and
   `sel_end_row >= sel_start_row`) and it contains `cursor_row`. Otherwise fall
   back to step 3.

3. **A single spot → cursor position.** Call `cursor_position`; it returns
   `buffer_name`, `buffer_id`, `row` and `col`, **zero-based**. The file line
   number the user sees is `row + 1` — convert before quoting a line or editing.

4. **Widen to what they actually mean.** "This line" is literally the line;
   "this function" / "this fragment" (with no usable selection) is the enclosing
   symbol — get its range from `lsp_document_symbols` for that document and pick
   the innermost symbol containing the cursor. Then `read` the buffer
   (`{"buffer_id": N}`) over that range plus a few lines of context.

   Read from the **buffer**, not the file on disk: unsaved edits are exactly the
   state the question is about.

5. **Say what you resolved, in one line**, before answering — e.g.
   `modules/hm/nvim-mcp/default.nix:34-41 (fn mkPlugin)`. A wrong guess is then
   one word to correct instead of a wasted answer.

6. **Editing** still goes through the normal file tools (Edit/Write) on the path
   from `buffer_name`; `lsp_apply_edit` is for applying LSP code actions, not for
   your own edits. Mention it if the buffer is modified — the user may want to
   `:w` first.

## When Neovim is not reachable

No connections, or the tool call fails: say so and ask which line/file they mean.
Do **not** quietly fall back to grepping the repo for a plausible candidate —
answering about the wrong code is worse than one short question. (Useful check:
the plugin only opens a socket for non-transient instances, so a commit-message
buffer never appears here.)
