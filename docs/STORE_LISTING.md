# Play Store Listing — TaskRelay 2.0

Everything here must stay true to the live privacy policy (`/privacy`) and to the app. Change them together.

---

## Short Description
*(Max 80 characters — shown under the app name in search results)*

```
Plan your day with a Top 3, lock-screen alarms, habit streaks and an AI link.
```

---

## Full Description
*(Max 4000 characters — shown on the app's store page)*

```
TaskRelay is a calm, black-and-white task planner. Decide what matters today, get an alarm when it is time, and keep your habits going.

───────────────────────────────────────
 PLAN YOUR DAY
───────────────────────────────────────
• Today's Top 3: star up to three tasks that must happen today.
• Give every task a duration and set a daily limit by time or by count. TaskRelay tells you in words when you have planned too much.
• Repeat a task every day or on the weekdays you choose, for example Mon, Wed and Fri.
• Anything unfinished shows up as Overdue, with one tap to move it to today.
• Undo a delete, and search all your tasks and notes.
• Organise with your own types and priorities.

───────────────────────────────────────
 ALARMS YOU CAN TRUST
───────────────────────────────────────
• Alarms ring over the lock screen with Complete, Snooze 10 min and Dismiss.
• Once synced, your alarms are stored on your phone, so they ring even with no connection, and they are re-armed after a restart.
• Change a task on the web or through an AI assistant and your phone's alarms follow shortly after.
• Add a task from any app with Share, and tick tasks off from the home-screen widget.

───────────────────────────────────────
 STREAKS AND WEEKLY REVIEW
───────────────────────────────────────
• A month calendar shows every day as done, partly done or missed, using symbols as well as shading.
• A streak for each repeating task, plus your overall streak.
• A weekly review: what you finished, your best hours, and what keeps slipping.

───────────────────────────────────────
 AN OPTIONAL AI LINK
───────────────────────────────────────
• Give your private TaskRelay link to an AI assistant such as Claude and it can read and update your tasks while you chat.
• Changes it makes are marked "Claude", listed in Profile, and easy to undo.
• Turn the link off or replace it at any time. TaskRelay never sends your data to an AI company by itself.

───────────────────────────────────────
 YOUR ACCOUNT, YOUR DATA
───────────────────────────────────────
• Sign in with email and password, and use the same tasks on your phone and on the web.
• Download all of your data, or delete your account and everything in it, from Profile.
• No ads. No tracking.

───────────────────────────────────────
 BLACK AND WHITE
───────────────────────────────────────
• Choose White, Black, or follow your phone. Nothing relies on colour alone, so it stays easy to read.

Start each day knowing exactly what needs to get done.
```

---

## Supporting Details

| Field | Value |
|---|---|
| App name | TaskRelay |
| Category | Productivity |
| Content rating | Everyone |
| Target audience | 13 and over (not directed at children) |
| Monetisation | Free |
| Requires internet | Yes (alarms that have already synced still ring offline) |
| Account required | Yes (email + password) |
| In-app purchases | No |
| Ads | No |
| Privacy policy URL | https://taskrelay.vercel.app/privacy |
| Account deletion URL | https://taskrelay.vercel.app/account-deletion |

---

## What's New (2.0.0)
*(Shown on the "What's new" section of the store page)*

```
TaskRelay 2.0 keeps your tasks in your own account, so they follow you to the web.

• Today's Top 3, weekday repeats, undo and search
• Habit streaks and a weekly review
• Snooze alarms 10 min, add tasks with Share, home-screen widget
• Optional private link so an AI assistant such as Claude can help
• New black-and-white design: White, Black or Device

Note: tasks saved in 1.x are not carried over. Start fresh in 2.0.
```

---

## Data safety (draft answers — check every row against the current Play form before submitting)

Declare these under *Data safety*. TaskRelay has no ads, no analytics SDK and no third-party tracking.

| Data type | Collected | Shared | Required | Purpose |
|---|---|---|---|---|
| Email address (Personal info) | Yes | No | Yes | Account management |
| Password | Yes (stored only as a salted hash) | No | Yes | Account management (Play lists it as credentials under Personal info) |
| Tasks, notes, repeat and reminder settings (User-generated content) | Yes | No | Yes | App functionality |
| Time zone | Yes | No | Yes | App functionality (so "today" is right). Not location. |
| AI change log (last 200 changes, only if the AI link is used) | Yes | No | No | App functionality |
| Sign-in sessions | Yes | No | Yes | App functionality / security |

Answers to the general questions:

- **Data encrypted in transit:** Yes (HTTPS everywhere).
- **Users can request deletion:** Yes — in the app (Profile → Delete my account) and on the web (`/account-deletion`). Deleted tasks are kept 30 days for undo, then removed; deleting the account removes everything immediately.
- **Data shared with third parties:** No. The database host (Turso) and web host (Vercel) process data on TaskRelay's behalf.
- **Location, contacts, photos, advertising ID:** Not collected.

Open point to decide before submitting: Vercel keeps standard request logs (IP address and time) under its own policy. Play treats data collected by your service providers on your behalf as collected by you, so decide whether to also declare *IP address*. The privacy policy already mentions these logs.

---

## Play Console checklist (developer actions — not done by the build)

1. **App access:** the app needs a sign-in, so create a demo account and give the reviewers its email and password under *App access*.
2. **Permissions declarations:** paste the texts from [PERMISSIONS.md](PERMISSIONS.md) into *Full-screen intent*, *Foreground service (media playback)* and *Exact alarms*.
3. **Data safety, privacy policy URL, account deletion URL:** use the tables above.
4. **Target audience:** 13+; not a Families app.
5. **Release notes:** use *What's new*, including the line that 1.x data is not carried over.
6. **Bundle:** `flutter build appbundle` with the upload keystore (`version: 2.0.0+4`).
