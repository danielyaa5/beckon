# Beckon project instructions

macOS menu-bar app and widgets, originally named Find My Ring. Read `README.md`, `Package.swift`, `project.yml`, and the affected files in `App/`, `Widget/`, `Shared/`, or `Sources/`.

- Preserve the ringing and availability scope: background availability checks are authorized; do not add location, battery, or place collection without the user's approval. Keep unknown and stale availability distinct from offline, using "Needs refresh".
- The existing bundle/app-group identifiers are compatibility boundaries. Do not rename them just because the customer-facing app name changed.
- Swift package validation starts with `swift test`; native app/widget builds require Xcode and configured signing. Tests do not prove a device physically rang.
- Verify the real app/widget interaction when authorized and available. Separate Apple-device ringing from AirTag automation through Find My and its permissions.
- Use fictional devices in public screenshots. Keep Apple Account details, device lists, credentials, and diagnostics private.

## Working rules

- Preserve unrelated changes and use the repository's existing conventions.
- Test changes through the real user flow before saying they work. State what could not be tested and why. A passing build or a saved setting is not end-to-end verification.
- Run browser tests headlessly when no visible interaction is needed. Close only the windows/tabs you opened and stop only the temporary servers you started.
- Never send email on the user's behalf without showing the complete draft and receiving approval of that exact version. Changes to the draft require renewed approval.
- Do not add AI attribution, AI co-author trailers, or session links to commits, PRs, issues, releases, or comments. Use the repository owner's configured Git identity; never invent an identity.
- Before starting a new product or tool, research existing solutions, compare their fit/cost/limitations, and wait for the user's choice. Routine fixes, additions to existing projects, and throwaway scripts do not require that step.
- Give progress updates during long work. Do not stop or restart a slow job the user is waiting on without asking.
- Keep credentials, personal identifiers, account details, private hostnames, and private notebooks out of repository instructions and public artifacts. Use fictional test data and repo-relative paths.
- Keep durable public project knowledge in this file or focused project docs. Private notes belong in the agent's configured private context store, if available; a cloud task must work from this repo without access to private files.
