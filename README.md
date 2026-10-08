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
