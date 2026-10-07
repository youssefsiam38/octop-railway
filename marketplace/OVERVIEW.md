# Deploy and Host Octop on Railway

Octop is an open-source, self-hosted AI assistant for individuals and teams. It supports multiple users and multiple
agents, each with its own skills, knowledge bases, MCP tools and scheduled tasks, and it works with the LLM provider
of your choice. This template deploys Octop with an admin account created from generated variables and its
first-run setup API closed to the public. It is a community-maintained template based on Octop. It is not
affiliated with, endorsed by, or an official offering of the Octop project or Tencent Cloud, and it does not use the
Octop logo.

## About Hosting Octop

Octop is a Python (FastAPI) server with a built-in React web app. It stores users, agents, conversations and
settings in SQLite and keeps agent workspaces and uploads on disk. Normally a web setup wizard creates the first
admin. However, the wizard's API stays reachable without authentication while the instance has a single user, and
it can be used to register an LLM provider and make it the active model. This template creates the admin from
environment variables on first boot and runs the official Octop image unmodified behind a small Caddy front door
that refuses the setup API. Octop's own login protects everything else.

This template runs Octop on Railway with a generated admin password, its data on a persistent volume, and the port
and health check wired. On first boot it also creates Octop's default assistant and sets the admin's language.

## Common Use Cases

- A private ChatGPT-style assistant for you or your team, on your own infrastructure and your own model keys.
- Building specialised agents with skills, knowledge bases (RAG), MCP tools and scheduled tasks.
- A multi-user AI workspace where an admin manages accounts, roles and shared agents.

## Dependencies for Octop Hosting

- Nothing external is required to run it: the database is embedded (SQLite on the volume).
- To chat, you provide your own LLM provider and API key (OpenAI or any OpenAI-compatible endpoint, Anthropic,
  DeepSeek, Qwen, Ollama and others), entered in Octop's Settings.

### Deployment Dependencies

- Octop: https://github.com/TencentCloud/Octop (MIT)
- Template repository and tests: https://github.com/youssefsiam38/octop-railway

### Implementation Details

The template runs the official `ghcr.io/tencentcloud/octop` image, pinned by digest and unmodified, packaged in one
container with a Caddy front door. Caddy is the only public listener; Octop listens on loopback. Caddy returns `403`
for Octop's setup-wizard API (`/api/setup/*`, except the read-only `status` and `presets` GETs) and proxies
everything else, including chat WebSockets. The admin is created on first boot from `OCTOP_ADMIN_USERNAME` (default
`admin`) and a generated `OCTOP_DEFAULT_PASSWORD`. A one-shot bootstrap then sets the admin's language
(`OCTOP_ADMIN_LOCALE`, default `en`) and creates the default assistant. `HOME=/data` keeps all data on the volume.
Railway's health check hits `/api/health`.

Tested in CI and on a live deployment of this template: the setup API is refused (including path-normalisation
bypass attempts), the API requires a token, a wrong password is rejected, and the admin signs in with the generated
password. An LLM provider is then registered and passes its connectivity test, an agent is created, and a chat turn
over the WebSocket returns the model's reply and is stored in the thread history. All of it survives a redeploy.

After deploying, copy `OCTOP_DEFAULT_PASSWORD` from the service's variables, open the public domain and sign in as
`admin`. Then change the password and add your LLM provider in Settings → Models.

## Why Deploy Octop on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you
don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Octop on Railway, you are one step closer to supporting a complete full-stack application with minimal
burden. Host your servers, databases, AI agents, and more on Railway.
