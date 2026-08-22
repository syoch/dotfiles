---
name: db-session-history-query
description: Use when querying opencode session history from the SQLite DB (~/.local/share/opencode/opencode-stable.db) to extract past conversations, user prompts, or assistant outputs. Trigger keywords: opencode sqlite, query session history, opencode-stable.db, extract conversation, session message part table, recover past session prompts, analyze previous session, message data json_extract, part table text content.
---

# Query opencode session history from SQLite DB

Use when you need to extract conversations, user prompts, or assistant outputs from past opencode sessions stored in `~/.local/share/opencode/opencode-stable.db` — for analyzing what happened in a previous session, recovering context, or debugging opencode's own data storage.

## When to use
- Recover what was asked/done in a past session (title, directory, prompts, responses)
- Understand a session's timeline or message flow
- Analyze opencode data storage layout

## Procedure

1. **Locate the DB** (this is the stable channel path):
   ```
   ls -la ~/.local/share/opencode/
   ```

2. **sqlite3 CLI is often unavailable** (e.g. NixOS). Check and fall back to Python:
   ```
   which sqlite3 python3
   python3 -c "import sqlite3; print('ok')"
   ```

3. **Introspect the schema first** — table shapes are non-obvious and change between versions:
   ```
   SELECT sql FROM sqlite_master WHERE name IN ('session','message','part');
   ```
   - `session`: id, parent_id, title, directory, time_created, time_updated
   - `message`: id, session_id, time_created, data (JSON blob with role etc.)
   - `part`: message_id, time_created, data (JSON; type=='text' holds the actual text)

4. **Find the session** by id or directory:
   ```
   SELECT id, parent_id, title, directory FROM session WHERE directory='<cwd>'
   ```

5. **List user messages**, filtering via JSON extraction on the `data` column:
   ```
   SELECT id, time_created, data FROM message
   WHERE session_id='...' AND json_extract(data,'$.role')='user' ORDER BY time_created;
   ```

6. **Get the actual text** — the message `data` is metadata; text lives in `part`:
   ```python
   for (pdata,) in cur.execute("SELECT data FROM part WHERE message_id=? ORDER BY time_created", (mid,)):
       p = json.loads(pdata)
       if p.get('type')=='text': texts.append(p.get('text',''))
   ```

7. **Timestamps are epoch milliseconds** — convert with `datetime.fromtimestamp(ts/1000)`.

8. For quick previews use `substr(data,1,200)`; for full messages load `data` fully (truncation hides fields).

## Pitfalls
- Message `data` is a JSON string; always `json.loads` it before reading `role`/`time`.
- `part` rows are keyed by `message_id` (not the message PK) and each has its own `time_created`.
- Real sessions can have 5000+ messages and many parts — paginate, filter by `time_created >= <ms>`, or limit your `part` query per message to avoid dumping entire transcripts.
- `json_extract(data,'$.role')` is convenient but some builds store role under a nested `time` object; inspect one row's JSON before writing complex queries.
- A `time_created` filter beyond the last activity returns 0 rows — widen the range before concluding data is missing.

## Verification
- Confirm the schema query returns tables (proves sqlite3 Python module works).
- A known session id yields a row with the expected title/directory.
- Extracted user text lines up with the timestamps in chronological order.
