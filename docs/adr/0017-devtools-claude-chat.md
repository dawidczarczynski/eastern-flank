# ADR 0017: The devtools hub hosts a Claude Code chat; a backlog task starts `/implement-task` from a button

- **Status**: accepted
- **Date**: 2026-10-30

## Context

Tasks are implemented by running `/implement-task TASK-NNN` in Claude Code. The human wanted to start that from the backlog view in the devtools hub with one button, then follow and answer the agent in the browser. ADR 0008 already lets a local web tool run Claude Code headless, but only as one-shot jobs with a narrow allow-list. Implementing a task needs a conversation: the agent asks questions, the human answers. It also needs much wider permissions: edits anywhere in the repository, the project scripts and subagents.

## Decision

- **A chat session is one long-lived `claude -p --input-format stream-json --output-format stream-json` process** (`tools/devtools/chat.py`). Every message goes to its stdin as a stream-json user message, so the agent keeps its context between turns. When the process is gone (Stop, a devtools restart, a crash), the next message starts a new one with `--resume <session id>`. The session id is validated and can't start with `-`. History is saved to `.devtools/chats.json` (git-ignored). The binary is found via `$DEVTOOLS_CLAUDE`, then `PATH`, then the VS Code extension's bundled binary. The lookup and the stream-json parser are shared with the catalog in `tools/web_ui/claude_cli.py`.
- **Two ways to start a session**: from the backlog (the fixed prompt `/implement-task <TASK-ID>`, where the id must match `TASK-\d+[a-z]?` and be a BACKLOG.md row that is not `done`, `merged` or `idea`), or a free chat that starts with the human's text. A second "Implement" on the same task opens the existing chat instead of starting another.
- **Permissions: Claude Code's `auto` mode (`--permission-mode auto --permission-prompts none`).** A classifier approves safe actions, such as one-off scripts, `touch` or builds, and blocks risky ones: data exfiltration, destructive commands, actions outside the task. Nobody can answer a prompt, so a blocked action is refused, and the agent tells the human what it needed. The chat log shows refusals in one line (`blocked by the auto mode classifier: <reason>` / `denied: <tool> (deny rule)`). A pre-approved allow-list skips the classifier:
  - `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, `Skill`, `Agent`, `SendMessage` and `TodoWrite`;
  - `Edit(//<repo>/**)`. The rule is absolute because a `cd` in the agent's shell moves the base of relative rules;
  - `Bash` for the project scripts (`tools/check.sh`, `test.sh`, `lint.sh`, `backlog.py`, `screenshot.sh`, `readme_screenshot.sh`, `render_unit.sh`, `simulate.sh`), `godot --headless` and read-only git (`status`, `diff`, `log`, `show`).

  A deny-list wins over both. It blocks `git commit`, `push`, `reset`, `clean`, `rebase` and `stash` (history and the human's uncommitted work), edits in `.git/`, `.godot/` and `*.import`, and `AskUserQuestion` (questions come as text at the end of a turn). An appended system prompt tells the agent all this and forbids commits. The first version used `dontAsk` with only the allow-list. It refused too much for `/implement-task` (`python3 -c`, `touch`, one-off scripts) and was replaced on the same day.
- **One working session at a time, one live process.** Starting a turn is refused while another chat is working, and while the unit catalog has a queued or running job. The two tools check each other over `GET /api/chat/busy` and `GET /api/jobs` on their fixed localhost ports. Starting a process stops the idle process of any other chat, which resumes on its next message.
- **Backlog ↔ hub over `postMessage`.** The backlog runs in an iframe on another port. When embedded, it says hello to its parent page. The hub answers with the tasks that have chats, and the task panel then shows "▶ Implement with Claude" (for `ready` / `in progress` / `to playtest` tasks with a task file) or "Open chat". The click posts only the task id. The hub accepts it only from the backlog frame's window and origin, asks the human to confirm, then calls its own API.
- **Usage is shown live from the stream.** The CLI sends a `rate_limit_event` with the subscription's usage windows (5-hour and weekly utilization, reset times) on every API call. The hub keeps the latest one, saves it with the history, and the sidebar shows it as bars ("live" while a chat works, otherwise "as of …"). The main agent's `usage` on each assistant message gives the session's context size; the turn's `modelUsage` gives the context window. Subagent calls are not counted. There is no API to poll usage while nothing runs.
- **One hub owns the chat.** The history file is guarded by an flock on `.devtools/chats.json.lock`. A second devtools instance can't take it and turns its chat off. Otherwise two hubs would overwrite each other's history and miss each other's working session.
- **The hub's POST routes now check CSRF like the catalog's**: they need `Content-Type: application/json` and, if an Origin is sent, the hub's own origin. Every route refuses a foreign `Host` (DNS rebinding).

## Consequences

- (+) A task goes from the backlog to a running implementation in two clicks. The human answers the agent's questions in the same page, and can take over in a terminal with `claude --resume <id>` at any time.
- (−) Auto mode and the deny-list limit mistakes; they are not a sandbox. The classifier can misjudge an action, and the agent can run code it writes. The hub binds to 127.0.0.1, checks Host and Origin, and accepts nothing but fixed templates and message text. A human in the loop and the absence of commit rights are the real safeguards.
- (−) Sessions use the human's Claude subscription. `/implement-task` on a large task is long and costly, which is why the button asks for confirmation. A resumed process pays again to re-read its cached context.
- (−) A session edits the working tree while the human may be editing too. Nothing is committed, and the chat lists the `git status` changes after every turn.
