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

The interface uses local system fonts and explicit status labels. Its paper-and-ink
light palette switches automatically to a dark ink-room palette when your system
prefers dark mode, including native form controls. There is no separate theme
toggle or saved preference. Navigation, forms, and controls support keyboard focus;
long repository names, logs, and keys wrap, and destination tables scroll on small
screens.

## Credential encryption upgrade

The preparation release adds Fields without changing credential storage. Before
deploying it, add `ENCRYPTION_KEYS` to the service environment with exactly the
existing `CLOAK_KEY` value, and retain `CLOAK_KEY`. Do not generate a replacement
key for existing data.

The cutover release will convert credentials automatically at boot, before
workers and HTTP serving start. Stop the old service and take a consistent SQLite
backup before deploying that release. Both commits may be deployed together.
