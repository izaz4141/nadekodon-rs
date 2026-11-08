# Nadeko~don persistence redesign

## Goal

Stop the 5-second database loop from snapshotting and rewriting every download.
Only ongoing workers are persisted periodically, and only their progress bytes.
Every other change is committed immediately when the action happens.

## Architecture

```
Action / worker / event
        │
        └── ctx.db()  ──►  DatabaseManager method
                              │
                              ├─ write_gate: Mutex<()>   (one write at a time)
                              ├─ outbox: failed writes / deletes
                              └─ last_saved: progress checkpoints

run_loop (separate task)
  ├─ 5s timer: retry outbox, then save active progress
  └─ shutdown: retry, final progress, categories, notify
```

- No writer task, no mpsc channel, no acks.
- Every write goes through `AppContext::db()`; a missing DB panics.
- `write_gate` makes read-worker-then-write atomic.
- Lock order: **gate → worker/category locks**.
  Never hold the workers map or categories lock while acquiring the gate.

## Write paths

### 1. Periodic tick — every 5 seconds

Source: `DownloadManager.ongoing` only:

- `Running`
- `Seeding`
- `StalledDL`
- `StalledUP`

Processing:

1. Gather ongoing IDs.
2. Process in chunks of 64.
3. Per chunk: lock gate, read each worker's latest progress, write one
   transaction, release.
4. Columns:
   - `downloaded` changed:
     `downloaded, uploaded, state, parts, updated_at`
   - only `uploaded` / `state` changed:
     `uploaded, state, updated_at` (no `parts` JSON)
5. If `UPDATE` affects 0 rows, fall back to a full upsert for that ID.
6. Skip IDs whose checkpoint is unchanged.
7. Prune `last_saved` to the current ongoing IDs.
8. An empty ongoing set still runs the outbox retry.

### 2. Action write — full-row upsert

Inline await under the gate. Triggered by:

- `add_download`
- `pause`, `resume`, `cancel`, `update_download_url`
- `set_category`, `clear_category`, `set_seeding_limits`
- `Completed`, `Error`, `Cancelled`, `Stalled`, `SeedingStarted` events
- YTDLP merge result
- metadata established during `start()`
- startup reconciliation for rows reset to `Paused`

`updated_at` is set to now at write time.

### 3. Delete — immediate

- `delete_worker`: cancel → remove worker → remove from `ongoing` →
  `ctx.db().delete_download(id)`.
- `load_snapshot` orphan: collect IDs, drop the workers lock, then delete.
- `pending_deletions`, `drain_pending_deletions`, and
  `requeue_pending_deletions` are removed.
- Failed deletes go into the outbox, never a delayed queue.

### 4. Categories

- Full reconciliation in one gate-held transaction:
  - upsert current categories,
  - delete rows not present.
- Called inline and awaited from `create_category` / `update_categories`.
- Failure sets a dirty flag retried on the next tick.
- The categories lock must be dropped before calling `save_categories`.

### 5. Retry outbox

- Single `HashMap<Uuid, PendingOp>`, last-op-wins.
- `Delete` supersedes `Upsert`.
- Retried every tick and on shutdown.
- Logging rate-limited to once per ID until success.
- Post-init SQLite errors are logged and retried; only a missing DB is
  catastrophic.

## `ongoing` set

- **Insert:**
  - `DownloadManager::start()`
  - seeding resume in `controls::resume()`
  - stalled resume in `process_queue()`
  - defensive insert on `SeedingStarted`
- **Keep:**
  - `Stalled`
  - `ProgressResumed`
- **Remove:**
  - public pause
  - over-limit pause in `process_queue`
  - cancel
  - `Completed`
  - `Error`
  - `Queued`
  - delete

`active` remains the concurrency-slot set and is unchanged.

## Races eliminated

- **Delete vs. save:** `delete_worker` removes the worker before deleting.
  `save_download` reads the worker under the gate.
  - save wins gate → writes, then delete removes;
  - delete wins gate → save finds no worker and no-ops.
  No tombstone needed.
- **Stale full save:** every full save reads the latest worker state under the
  gate.
- **Stale tick state:** each chunk reads worker progress under the gate, so a
  pause/cancel cannot be overwritten by an older tick snapshot.

## Metadata timing

- Normal/HLS: one full save at the end of `start()` after type, size, and parts
  are known.
- Torrent: one full save inside `download_torrent_task` after `dest`,
  `torrent_hash`, `parts`, and `total_size` are populated.
- Periodic tick never writes metadata.

## Startup

Split `start_database_manager` into:

- `init_database(path)` — create pool, set `ctx.db`, wait for torrent
  pre-clean, load categories/downloads.
- `run_loop()` — the 5-second timer + shutdown.

Then:

- Server awaits `init_database` before serving.
- Hub awaits it before sending `InitDatabaseResponse { success: true }`.
- Startup may wait up to the existing 10-second torrent pre-clean timeout.
  Accepted.
- No pre-DB drop/log path; `ctx.db()` is always present.

## SQLite

- `max_connections(4)`.
- Per connection: WAL, `busy_timeout=5000`, `foreign_keys=ON`, add
  `synchronous=NORMAL`.
- Tick chunks use one transaction per chunk.

## File-level changes

- `native/core/src/utils/database.rs`
  - gate, outbox, chunked progress, full upsert, delete, category
    reconciliation, retry logic.
  - remove `save_downloads`.
- `native/core/src/utils/types.rs`
  - add `DownloadProgress`.
- `native/core/src/app_context.rs`
  - `init_database` / `run_loop` split; no `db_opt`.
- `native/core/src/downloader/manager/mod.rs`
  - add `ongoing`; remove `pending_deletions`.
- `native/core/src/downloader/manager/downloads.rs`
  - persist on add, ongoing transitions, immediate delete, orphan handling,
    merged result persist.
- `native/core/src/downloader/manager/controls.rs`
  - persist on pause/resume/cancel/URL update; ongoing transitions.
- `native/core/src/downloader/manager/core.rs`
  - event persistence, ongoing maintenance in `process_queue` /
    `handle_event`.
- `native/core/src/downloader/manager/queries.rs`
  - ongoing IDs, lock-scope fixes for `list_all` / `list_torrents`.
- `native/core/src/downloader/manager/settings.rs`
  - remove pending-deletion methods.
- `native/core/src/downloader/manager/categories.rs`
  - await category saves; drop categories lock first.
- `native/core/src/downloader/worker/info.rs`
  - `progress_snapshot`, no history clone, persist hooks for category and
    seeding limits.
- `native/core/src/downloader/worker/start.rs`
  - persist metadata once.
- `native/core/src/downloader/worker/torrent.rs`
  - persist metadata once after torrent setup.
- `native/core/src/downloader/mod.rs`
  - persist merged YTDLP result.
- `native/server/src/main.rs`
  - await `init_database` before serving; spawn `run_loop`.
- `native/hub/src/utils/database.rs`
  - await `init_database` before replying success; spawn `run_loop`.

## Verification

- `cargo check` only.
- No `cargo test`, no `cargo build`, no new tests.

## Implementation checklist

1. [x] Add `DownloadProgress` and worker progress/persist methods.
2. [x] Add `ongoing` set and manager helpers.
3. [x] Rework `DatabaseManager` write paths and `run_loop`.
4. [x] Wire action, event, delete, category, and metadata persistence.
5. [x] Split startup and update server/hub.
6. [x] Fix lock scopes (`list_all`, `load_snapshot`, categories).
7. [x] Run `cargo check` and fix errors.
