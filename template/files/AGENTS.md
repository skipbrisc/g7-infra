# Project rules for coding agents

- Git: the only remote to push to is `g7`. Never push to GitHub; G7 mirrors every branch and
  tag there within about a minute, so anything committed becomes visible on GitHub.
- Never commit secrets, tokens, keys or `.env` files. `.env.example` holds names only.
- Every push is built by Jenkins on G7: a whole-history secret scan, a dependency audit and
  the tests. A red build means nothing is deployed. Do not edit `Jenkinsfile` unless asked.
- Runtime versions are pinned in `.nvmrc` or `.python-version`. Do not change them unasked.
- Never run commands on G7 as root, restart services there, or deploy, unless the user asks.
- Finish what was asked, and say plainly what was not verified.
