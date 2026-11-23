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

2. **Ask the editor where they are pointing.** One `exec_lua` call — the editor
   owns this answer, so do *not* re-derive it:

   ```lua
   return NvimMcpPointer.resolve()
   ```

   It returns `kind`, `buffer_id`, `buffer_name`, `modified`, `mode`,
   `cursor_row`, `cursor_col`, plus `start_row`/`start_col`, `end_row`/`end_col`
   and `linewise` when `kind == "selection"`. **Every row and column is
   1-based**, as the file shows them.

   - `kind == "selection"` — the user is holding a selection right now (visual
     mode is live; switching panes does not end it). That range *is* "this
     fragment"; use it as given and do not widen it. If they expected a
     selection and got `"cursor"`, they pressed `<Esc>` before switching — say
     so, and that leaving the selection up is what hands it over.
   - `kind == "cursor"` — a single spot, nothing selected. Widen per step 3.

   Never read `'<` / `'>` yourself. They outlive the selection by design, and
   leaving visual mode parks the cursor *at* the range end — so every "are the
   marks still current?" heuristic ends up answering about a long-dead range
   instead of the cursor line. `resolve()` is the only source; the editor paints
   what it returns when focus leaves the pane (`pointer.lua`), so the user can
   see what you are about to answer about, and a second implementation of the
   rule would mean the screen lying about what you got.

   `NvimMcpPointer` nil → an editor older than this helper: fall back to
   `cursor_position` (`row`/`col` **zero-based** there — the user's line number
   is `row + 1`) and say the selection could not be checked.

3. **Widen to what they actually mean.** "This line" is literally the line;
   "this function" / "this fragment" with `kind == "cursor"` is the enclosing
   symbol — get its range from `lsp_document_symbols` for that document and pick
   the innermost symbol containing the cursor. Then `read` the buffer
   (`{"buffer_id": N}`) over that range plus a few lines of context.

   Read from the **buffer**, not the file on disk: unsaved edits are exactly the
   state the question is about.

4. **Say what you resolved, in one line**, before answering — e.g.
   `modules/hm/nvim-mcp/default.nix:34-41 (fn mkPlugin)`. A wrong guess is then
   one word to correct instead of a wasted answer.

5. **Editing** still goes through the normal file tools (Edit/Write) on the path
   from `buffer_name`; `lsp_apply_edit` is for applying LSP code actions, not for
   your own edits. Mention it if the buffer is `modified` — the user may want to
   `:w` first.

## When Neovim is not reachable

No connections, or the tool call fails: say so and ask which line/file they mean.
Do **not** quietly fall back to grepping the repo for a plausible candidate —
answering about the wrong code is worse than one short question. (Useful check:
the plugin only opens a socket for non-transient instances, so a commit-message
buffer never appears here.)
