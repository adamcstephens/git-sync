# GitSync

Mirror repositories between Forgejo, GitHub, Tangled, and Pushin.eu periodically, with push webhooks where supported.

## Pushin.eu

On **Connections**, save a personal access token in the **Pushin.eu** form. The token is stored encrypted and used for both API access and HTTPS Git transfers. Replace or disconnect it from the same page.

Create the destination repository on Pushin.eu first, then select Pushin in the source or destination repository picker. The token must have access to the source and permission to push to the destination.

API requests use `https://pushin.eu/api/v1`; Git transfers use `https://git.pushin.eu/owner/repo.git` with username `git` and the token as password. Pushin sources use periodic synchronization; this integration does not register webhooks or refresh personal access tokens.
