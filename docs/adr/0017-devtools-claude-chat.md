# ADR 0017: The devtools hub hosts a Claude Code chat; a backlog task starts `/implement-task` from a button

- **Status**: accepted
- **Date**: 2026-10-30

## Context

Tasks are implemented by running `/implement-task TASK-NNN` in Claude Code. The human wanted to start that from the backlog view in the devtools hub with one button, then follow and answer the agent in the browser. The browser chat should behave like the Claude Code session in their editor, so they don't have to switch windows. ADR 0008 already lets a local web tool run Claude Code headless, but only as one-shot jobs with a narrow allow-list.

## Decision

- **A chat session is one long-lived Claude Code process, driven the way the Agent SDK drives it** (`tools/devtools/chat.py`). The command is `claude -p --input-format stream-json --output-format stream-json --verbose --permission-mode auto --permission-prompt-tool stdio`. One pair of pipes carries both the conversation and the control protocol:
  - **Messages** go to stdin as stream-json user messages. That includes messages sent while a turn runs, which the CLI folds into the work as the IDE does, and slash commands such as `/compact`.
  - **`initialize`** answers with the session's slash commands, which the composer suggests after `/`.
  - **`can_use_tool`** requests are permission prompts and `AskUserQuestion`. The chat shows them as cards: Allow / Always allow (adds the CLI's suggested rule) / Deny with a note, or the question's options plus "Other". The answer goes back as a `control_response`.
  - **`interrupt`** is Stop or Esc. The turn ends and the process stays. If the turn doesn't end within a few seconds, the process is killed.

  A turn can also start without a message, for example when a background task finishes. The hub therefore takes "working" from the stream (every turn opens with a `system init`), not from its own sends.
- **Same behaviour as the IDE session**: `auto` permission mode plus the human's own settings, with no extra allow- or deny-list and no appended system prompt. Several chats may work at once, next to the human's other sessions and unit catalog jobs. They all share the working tree, as parallel IDE sessions do. At most four idle processes stay alive; older ones stop and resume (`--resume <session id>`) on their next message. A devtools restart or a crash is handled the same way. The session id is validated and can't start with `-`.
- **Two ways to start a session**: from the backlog, or a free chat that starts with the human's text. The backlog way sends the fixed prompt `/implement-task <TASK-ID>`; the id must match `TASK-\d+[a-z]?` and be a BACKLOG.md row that is not `done`, `merged` or `idea`. A second "Implement" on the same task opens the existing chat instead of starting another.
- **Backlog ↔ hub over `postMessage`.** The backlog runs in an iframe on another port. When embedded, it says hello to its parent page. The hub answers with the tasks that have chats, and the task panel then shows "▶ Implement with Claude" (for `ready` / `in progress` / `to playtest` tasks with a task file) or "Open chat". The click posts only the task id. The hub accepts it only from the backlog frame's window and origin, asks the human to confirm, then calls its own API.
- **The chat log shows what the IDE shows**:
  - tool calls fold open to their input (a diff for `Edit` / `Write`, the command for `Bash`, the list for `TodoWrite`) and their result;
  - permission refusals are one line;
  - after every turn, the `git status` changes;
  - a session waiting for the human is marked "needs you" in the sidebar, the session list and the page title, with a toast.
  - a strip above the log lists running subagents and background tasks, with type, description, current activity, tool uses, tokens and time. It comes from the CLI's `task_started` / `task_progress` / `task_updated` / `task_notification` events, and a finished task stays there for 30 s. A background subagent can outlive its turn, so the strip doesn't depend on the session's state;
  - "↓ Latest" (or End) jumps to the newest message and counts the ones that arrived while the log was scrolled up.
- **Usage is shown live from the stream.** The CLI sends a `rate_limit_event` with the subscription's usage windows (5-hour and weekly utilization, reset times) on every API call. The hub keeps the latest one, saves it with the history, and the sidebar shows it as bars ("live" while a chat works, otherwise "as of …"). The main agent's `usage` on each assistant message gives the session's context size; the turn's `modelUsage` gives the context window. There is no API to poll usage while nothing runs.
- **History and one owner.** History, the last usage and the slash commands are saved to `.devtools/chats.json` (git-ignored). An flock on `.devtools/chats.json.lock` guards the file. A second devtools instance can't take it and turns its chat off; otherwise two hubs would overwrite each other's history.
- **Shared code.** The binary is found via `$DEVTOOLS_CLAUDE`, then `PATH`, then the VS Code extension's bundled binary. The lookup and the stream-json parser (with a detail mode for the chat) are shared with the unit catalog in `tools/web_ui/claude_cli.py`.
- **The hub's POST routes check CSRF like the catalog's**: they need `Content-Type: application/json` and, if an Origin is sent, the hub's own origin. Every route refuses a foreign `Host` (DNS rebinding).

History: on the first day the chat went through three permission setups.
1. `dontAsk` with a fixed allow-list and no commits. It refused too much for `/implement-task`, such as one-off scripts.
2. `auto` with that allow-list plus a deny-list, and commits allowed on request.
3. The current setup: `auto` with the human's settings and prompts answered in the browser. The human wanted the chat to be the same as their IDE session.

The one-working-chat lock and the chat ↔ catalog lock were dropped along the way, because parallel sessions on the shared tree are the human's normal way of working.

## Consequences

- (+) A task goes from the backlog to a running implementation in two clicks. The human follows, answers and steers it in the same page as the other dev tools, and can take over in a terminal with `claude --resume <id>` at any time.
- (−) There is no IDE context (editor selection, diagnostics, clickable file links), and images in tool results are not shown.
- (−) Auto mode limits mistakes; it is not a sandbox. The classifier can misjudge an action, and the agent can run code it writes, exactly as in the IDE. The hub binds to 127.0.0.1, checks Host and Origin, and accepts nothing but fixed templates, message text and prompt answers.
- (−) Sessions use the human's Claude subscription. `/implement-task` on a large task is long and costly, which is why the button asks for confirmation. A resumed process pays again to re-read its cached context.
- (−) Parallel sessions edit one working tree. A commit must stage only the session's own files; the agents know this from the project memory, not from the hub.

## Amendment (2026-10-31): the task orchestrator runs on Sonnet

A task session is started with `--model sonnet` (also when resumed), and the `/implement-task` skill declares `model: sonnet`, so the IDE runs it on Sonnet too. The orchestrator plans, delegates, verifies and wraps up; it does not need Opus, yet with the human's default (`opus`) it ran on Opus in 52 of the 76 past task sessions. A task whose **Model** line is `opus` is therefore never implemented by the orchestrator itself: its implementation always goes to agents started with `model: opus` (skill step 4). Free chats keep the human's default model. This also makes task costs comparable for the usage forecast (TASK-109).
