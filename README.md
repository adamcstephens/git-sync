# GitSync

Wire up git repos to sync both periodically and through webooks.

Sources:

- Forgejo

Destinations:

- GitHub.com
- Tangled.org
- Pushin.eu

## Interface

The responsive workspace has an Overview of real source and destination totals,
source status, latest run timestamps, and recent sync activity. Sources provides
repository configuration, destination controls, and live run results and logs.
Connections manages forge credentials, connection health, Tangled knot host keys,
and the complete public SSH key. Setup and sign-in remain available before
authentication.

The interface uses local system fonts and explicit status labels. Its lavender-paper
and purple-ink light palette switches automatically to the matching dark purple
palette when your system prefers dark mode, including native form controls. Green
is reserved for healthy, enabled, and success indicators; dark success badges use
purple backgrounds. Primary actions and links are purple in both modes.
There is no separate theme toggle or saved preference. Navigation, forms, and
controls support keyboard focus; long repository names, logs, and keys wrap, and
destination tables scroll on small screens.

## Credential encryption upgrade

Two commits separate preparation from cutover; they may be deployed together.

1. Stop the old service and take a consistent SQLite backup, including its WAL
   state. Preserve the old release and encryption key with the backup.
2. Set `ENCRYPTION_KEYS` in the service environment to exactly the existing
   `CLOAK_KEY` value. Do not generate a new key for existing data.
3. Deploy the preparation commit if desired. It still requires `CLOAK_KEY` and
   continues writing Cloak credentials.
4. Deploy the cutover commit and start the service. It no longer requires
   `CLOAK_KEY`; remove that variable after cutover.

The cutover converts `connections.token`, `refresh_token`, `ssh_key`,
`client_secret`, and `sources.webhook_secret` automatically on application boot,
before webhook reconciliation, sync workers, and HTTP serving start. It replaces
the ciphertext header while preserving the encrypted payload and authenticates
every non-null value using key index zero. Nulls remain null.

Conversion runs in one SQLite migration transaction, reading batches of 100 rows.
A wrong key, failed authentication, or unexpected format aborts startup and rolls
back all updates. Correct the problem and restart; failed migrations are not
recorded. Successful migrations are recorded and are not repeated on restart.
Only one service instance may access the database during cutover.

Rollback requires stopping the service and restoring the pre-upgrade backup
together with the old release and key. Starting the old binary against converted
data is not supported. Restoring the backup discards writes made after cutover.

After migration, `ENCRYPTION_KEYS` may contain comma-separated Base64-encoded
32-byte keys. Fields encrypts with the last key and stores its numeric index.
Append keys to rotate; never reorder or remove keys still needed by stored data
or retained backups. Do not combine rotation with this upgrade.
