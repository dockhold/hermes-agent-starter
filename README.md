# Hermes Agent on Dockhold

[Hermes Agent](https://github.com/NousResearch/hermes-agent) by [Nous Research](https://nousresearch.com/) is an AI agent that runs on a server, connects to Telegram, Discord, Slack and other chat apps, and keeps its memory and skills between conversations. This repository is the [Hermes Agent template by praveen-ks-2001](https://github.com/praveen-ks-2001/hermes-agent-template), set up to run on [Dockhold](https://dockhold.eu): an always-on HTTPS address, its data kept on App storage across restarts and deploys, and the admin password kept in Dockhold's Secrets. The admin panel, the Hermes dashboard and the setup wizard are the template's own.

[![Deploy on Dockhold](https://dockhold.eu/button.svg)](https://app.dockhold.eu/new?repo=https://github.com/dockhold/hermes-agent-starter&name=hermes-agent-starter&ref=button-hermes-agent)

## Deploy on Dockhold

1. Open the [Deploy link](https://app.dockhold.eu/new?repo=https://github.com/dockhold/hermes-agent-starter&name=hermes-agent-starter&ref=button-hermes-agent) and sign in if asked.
2. Under **App size**, pick **1 GB**. Under **App storage**, pick **10 GB**. This app needs a paid plan: its image is larger than the free plan allows, and Hermes uses about half a gigabyte of memory before its first message. See [pricing](https://dockhold.eu/pricing).
3. Under **Environment**, in the **Secrets** list, click **New secret**. Give it a name that belongs to this app, for example `hermes-agent-admin-password`, and a password of at least 12 characters. Tick it and set its **Env var name** to `ADMIN_PASSWORD`. Secrets are shared across your apps by name, so a name of its own keeps this password separate from your other apps.
4. Click **Deploy** and wait until the app shows as running.
5. Open the app's URL and sign in as `admin` with that password. The setup page opens.
6. Pick a model provider, paste its API key and enter a model ([OpenRouter](https://openrouter.ai/) has free models). Tick **Telegram**, paste the bot token from [@BotFather](https://t.me/BotFather), and click **Save & Start**.
7. Send your bot a message. It replies with a pairing code, and the request appears under **Users** in the admin panel. Click **Approve**, and the bot answers you from then on.

If the app refuses to start, its logs on the app's **Activity** tab show one line saying what is missing. App storage is on the app's **Size** tab. Secrets are attached on its **Variables** tab, and their values are edited under **Secrets** in the dashboard sidebar. Fix it and click **Restart**.

Free models are often rate-limited by their provider. If the bot goes quiet, check the Logs panel in the admin panel, and pick another model in the setup page if you see a rate-limit error.

## What you get

- **Setup wizard** at `/setup`: pick a provider and model, tick chat channels and tools, no config files to edit.
- **The Hermes dashboard** (Chat, Keys, Skills, Kanban, Analytics, Console) at `/`, behind the same login.
- **Gateway control**: start, stop and restart the agent from the browser. It is restarted automatically if it crashes.
- **Status and logs**: gateway state, uptime, model, pending pairing requests, and a live log viewer.
- **User pairing**: approve or deny people who message your bot, and remove approvals later.
- **Backup and restore**: download a zip of the agent's config, credentials, chat history and skills, and restore it later.

Providers in the setup wizard include OpenRouter, Anthropic, Google AI Studio, xAI, DeepSeek, Qwen, GLM, Kimi, MiniMax, NVIDIA NIM, Fireworks, Hugging Face, GitHub Copilot, AWS Bedrock, Azure Foundry and any OpenAI-compatible endpoint. Every other provider Hermes supports can be set in the Hermes dashboard's **Keys** tab. Channels: Telegram, Discord, Slack, WhatsApp, Email, Mattermost, Matrix.

## How it runs

One process listens on `PORT` and is the only public surface. It serves the login, `/health`, the setup wizard and its API, and passes everything else to the Hermes dashboard, which listens only inside the app. It also supervises the Hermes gateway, the part that talks to your chat apps.

Everything Hermes keeps is under `/data/.hermes`, which is App storage: config, pairings, chat history, skills and memory survive restarts and deploys. A deploy stops the running app before it starts the new one, so the bot is offline for a few seconds. App storage is not backed up. Download a backup from the admin panel before an upgrade.

`dockhold/entrypoint.sh` runs first. It refuses to start without App storage. It refuses a missing or short `ADMIN_PASSWORD`, where the template would generate one and print it to the log. And it passes the app's own address (`DOCKHOLD_APP_HOSTNAME`) to Hermes, so MCP tool sign-ins return to the app.

## Two ways to use it

**Run it as it is.** Deploy this repository with the button above. The app stays on the version it was built with; **Restart** starts the same build again.

**Run your own copy.** Click **Use this template** on GitHub, connect your copy in Dockhold and deploy it. From then on every push builds and starts the new version. `dockhold/smoke.sh` tests the image the way Dockhold runs it.

## Upgrading Hermes

The `Dockerfile` pins one Hermes Agent release (`ARG HERMES_REF`). Upgrades come from the upstream template, which ships a release branch per Hermes version with the changes that version needs. This starter merges them in; the weekly check in `.github/workflows/dockhold-upstream.yml` opens an issue when there is a new one, and `dockhold/CHANGELOG.md` records each version this starter moves to. Before upgrading an existing install, download a backup.

The "Update" button inside the Hermes dashboard does nothing here on purpose: the image is fixed, so a runtime update would not survive a redeploy.

## Running locally

```bash
docker build -t hermes-agent-starter .
docker volume create hermes-data
docker run --rm -it -p 8080:8080 -e PORT=8080 -e DATA_DIR=/data \
  -e ADMIN_PASSWORD=change-me-please -v hermes-data:/data:nocopy hermes-agent-starter
```

Open `http://localhost:8080` and sign in as `admin`.

## Credits

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) by [Nous Research](https://nousresearch.com/)
- [Hermes Agent template](https://github.com/praveen-ks-2001/hermes-agent-template) by praveen-ks-2001: the admin panel, setup wizard and everything else here. See its README for the full details of each feature.
