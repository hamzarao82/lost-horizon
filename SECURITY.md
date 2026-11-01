# Security policy

Lost Horizon: Black Site is a single-player game with no server, accounts or network features.
The only hosted parts are the static portfolio page and the web build on GitHub Pages.

## Reporting a vulnerability
Please use GitHub's private vulnerability reporting (repository **Security** tab -> **Report a vulnerability**).
Do not open a public issue for security problems. I aim to reply within 7 days.

## Scope
- The web build and portfolio site served from GitHub Pages.
- Build and release workflows (`.github/workflows`).
- Save-file parsing (`user://` JSON): crafted save files must never crash the game or write outside `user://`.

## Out of scope
Cheating in a single-player game (editing your own save, memory editing).

## Supported versions
Only the latest release receives fixes.
