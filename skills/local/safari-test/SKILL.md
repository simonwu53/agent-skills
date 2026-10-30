---
name: safari-test
description: Test or debug web pages in real Safari (WebKit) through Safari's built-in MCP server, run on demand. Use only when the user asks for Safari or WebKit testing, or types /safari-test. Not for everyday browsing or signed-in tasks; those use the built-in browser.
---

# Safari testing

Drives real Safari through `safaridriver --mcp`, started on demand by the bridge
script `safari_mcp.py` in this skill's folder. No MCP server is configured; nothing
runs until you start it.

## Before starting

- Safari > Settings > Developer > "Allow remote automation and external agents" must
  be on. The user turns it on; never change Safari settings yourself. If calls fail
  with an automation or permission error, ask the user to check this box.
- Safari runs the session in a separate automation window: a clean profile with no
  cookies, history or sign-ins. Never sign in or enter credentials there. Leave
  cookie banners alone unless the user asks, and then pick the most private option.
- While the session runs, Safari covers the window with a glass pane, so the user
  can't click or scroll it. If the user breaks the glass pane, the session ends:
  `stop`, then `start` again.

## Workflow

The script path below is relative to this skill's folder.

1. `python3 safari_mcp.py start` starts one persistent session.
2. `python3 safari_mcp.py call '<json>'` runs tool calls in order, for example:
   ```
   python3 safari_mcp.py call '[["navigate_to_url", {"url": "http://localhost:4321"}], ["browser_console_messages", {"level_filter": ["error", "warn"]}]]'
   ```
   The session (tabs, page state) persists between `call`s, so test step by step.
   Begin with `navigate_to_url` or `create_tab`; other tools may fail before a
   page is open.
3. `python3 safari_mcp.py stop` when the user says testing is done, or when the
   task ends. Do not leave it running. As a safety net, the server also exits after
   one hour without a request.

`status` says whether it is running; `tools` prints every tool with its arguments.

## Tools worth knowing

- `get_page_content`: page text. Defaults to the visible viewport; pass
  `"region": "entire_page"` for the whole page, `"format": "markdown"` for prose.
  The default `textTree` format gives elements `uid=N` ids for interactions.
- `page_interactions`: click, type, scroll, hover, keyPress, given as a list.
  Target by `node` (a uid) or by `text`; use `point` only as a last resort.
  Each step needs a `purpose`.
- `screenshot`: always pass `savePath` inside the session's scratchpad directory,
  then view the PNG with the Read tool.
- `browser_console_messages`, `list_network_requests`, `get_network_request`: debugging.
- `set_viewport_size`, `set_emulated_media`: responsive and print checks.
- `evaluate_javascript`: a function body; use `return` to get a value back.

Delete screenshots once they are no longer needed, and tell the user where any kept
files are.
