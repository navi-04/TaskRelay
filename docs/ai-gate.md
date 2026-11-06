# Claude Desktop gate

Goal: find out what Claude Desktop can actually do with the AI link, **before** the phone app is built on top of it.
Claude's built-in URL fetch only opens URLs that already appeared in the conversation, so reading may work in plain chat while writing may not. With "Create and edit files" (code execution) on, it can send real requests if your domain is allowed in its network settings.

Do this against the **deployed** site (Claude cannot reach `localhost`). Replace `https://YOUR-APP.vercel.app` below.

## Setup (once)
1. Open the web app, sign in, go to **Profile -> Claude access**.
2. Make sure the switch is **On**. Tap **Copy prompt for Claude**.
3. Add a few tasks on **Today** (one for today, one overdue, one daily-repeating) so there is something to see.

## Test A: chat only (no code execution)
Turn "Create and edit files" **off** in Claude Desktop (Settings -> Capabilities). New chat, paste the copied prompt, then ask:

| # | Ask Claude | Pass if | Result |
|---|---|---|---|
| A1 | "What's on my list today?" | It opens the pasted link and lists your tasks | |
| A2 | "What about tomorrow?" | It gets tomorrow's tasks (it may use `?date=tomorrow`) | |
| A3 | "Add a task 'Buy milk' for tomorrow" | A task appears in the app | |
| A4 | "Mark <a today task> as done" | The task is checked in the app | |

Note which of A2-A4 fail and the exact message Claude gives.

## Test B: with code execution
Turn "Create and edit files" **on**. If you are on a Team/Enterprise plan, an owner must allow your domain under network access. New chat, paste the prompt again:

| # | Ask Claude | Pass if | Result |
|---|---|---|---|
| B1 | "Add 'Buy milk' for tomorrow, 10 minutes, high priority" | Task appears with the right day and priority | |
| B2 | "Move all my overdue tasks to today" | They move (check Today) | |
| B3 | "Mark the daily task done for today" | Checked in the app | |
| B4 | "Delete 'Buy milk'" | It asks you first, then it disappears | |

## Safety checks
- After the tests, **Profile -> Claude access** should show "Last used <time>". 
- Tap **Regenerate**, then ask Claude the same question again with the *old* link: it must fail.
- Switch the toggle **Off**: the link must stop working immediately.

## What the result decides
- A1-A2 pass, A3-A4 fail, B passes: chat can read; to write, Claude needs code execution on. Tell users that in the Profile copy.
- A and B both fail on writes: add pre-built action links to the AI responses (complete, move to tomorrow) and a "paste changes" box in the web UI.
- Everything passes: nothing more to build for the AI link.

Record the outcome here (date, Claude Desktop version, plan type, which tests passed) when done.
