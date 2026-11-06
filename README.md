<p align="center"><img src="Resources/AppIcon.png" width="140" alt="Claudinho icon"></p>

# Claudinho

A small macOS menu bar app that shows how much of your **Claude** and **Codex** usage limits you've burned, without opening a browser or typing `/usage`.

I kept getting cut off mid-task by the 5-hour limit with no idea I was close. Claudinho puts the numbers next to the clock, so you can see at a glance whether you have room for one more big refactor or should wait for the reset.

> UI is currently in Portuguese (pt-BR). English localization is welcome.

## What it shows

- **Every Claude limit on your plan**: the 5-hour session, the weekly limit across all models and the per-model weekly limits (e.g. Opus), each with a progress bar and a reset countdown
- **A pace marker** on each bar: where you'd be if you spread your usage evenly until the reset. Bar past the marker means you're going faster than the limit allows
- **Extra usage credits** spent this month, when enabled on your account
- **Codex limits** (session and weekly, plus your ChatGPT plan), if you use the Codex CLI
- **Menu bar text** you can pick: session + weekly, every limit, only the highest one, or just the icon. It turns red at 90%

It refreshes every minute and again when you open the popover. If the API rate-limits it, it backs off for as long as the server asks.

## Connecting your accounts

Claudinho has no login screen of its own. It reads the session the official CLIs already keep on your Mac, so connecting an account just means logging in to that CLI once.

### Claude

1. Install [Claude Code](https://docs.anthropic.com/en/docs/claude-code/setup) if you don't have it: `npm install -g @anthropic-ai/claude-code`
2. Run `claude` in a terminal and pick **log in with your Claude account** (Pro or Max). The browser opens, you approve, done.
3. Open Claudinho. Your limits show up within a few seconds.

Already using Claude Code? You're done, there's nothing else to do. To switch accounts, run `/login` inside Claude Code and Claudinho follows on the next refresh.

> Usage limits only exist on Claude subscriptions. If Claude Code is logged in with an Anthropic Console API key, there are no limits for Claudinho to show.

### Codex (optional)

1. Install the [Codex CLI](https://github.com/openai/codex): `npm install -g @openai/codex`
2. Run `codex` and pick **Sign in with ChatGPT**.
3. The Codex section appears in the popover on the next refresh. To see it in the menu bar too, turn on **Mostrar Codex na barra** in the gear menu.

If Codex isn't logged in (or is using an API key), its section stays hidden.

### Where the logins come from

| Service | Read from |
|---|---|
| Claude | macOS Keychain item `Claude Code-credentials`, falling back to `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json` |

Claudinho never writes to these and never refreshes tokens itself. The CLIs refresh them whenever you use them.

### Troubleshooting

| Popover says | What to do |
|---|---|
| *Login do Claude Code não encontrado* | Claude Code isn't logged in on this Mac. Run `claude` and log in with your Claude account. |
| *Token expirou* | Open `claude` in any terminal. It renews the token on startup and Claudinho picks it up within a minute. |
| *Token do Codex expirou* | Same thing: open `codex` once. |
| *Muitas consultas, tentando de novo já já* | The API rate-limited the request. Claudinho waits as long as the server asks and retries on its own. |
| *Resposta da API em formato inesperado* | The usage endpoint changed. Please open an issue. |

## Install

Requires macOS 14+, an Apple Silicon Mac and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/phmucelin/claudinho.git
cd claudinho
./build.sh install   # builds, copies to /Applications and launches
```

`./build.sh` alone just builds `build/Claudinho.app`. Turn on **Abrir ao iniciar o Mac** in the gear menu to start it at login.

## Privacy

- Your tokens are read locally and sent only to the provider that issued them (Anthropic for Claude, OpenAI for Codex), over HTTPS.
- No analytics, no third-party servers, no network calls other than the two below.
- The only thing Claudinho stores is your menu bar preferences, in `UserDefaults`.

## How it works

- Claude: `GET https://api.anthropic.com/api/oauth/usage` with the Claude Code OAuth token. The keychain is read through `/usr/bin/security`, the same tool Claude Code uses to write it, so there's no extra permission prompt.
- Codex: `GET https://chatgpt.com/backend-api/wham/usage`, the endpoint the Codex CLI uses for `/status`.
- Plain Swift + SwiftUI, no dependencies, no Xcode project. `build.sh` compiles with `swiftc`, draws the icon programmatically and ad-hoc signs the bundle.

```
Sources/
  main.swift        menu bar item and popover
  UsageStore.swift  polling, backoff, preferences
  UsageAPI.swift    Claude endpoint + credential lookup
  CodexAPI.swift    Codex endpoint
  UsageView.swift   popover UI
  Clawd.swift       pixel-art icon
tools/makeicon/     renders the app icon at build time
```

## Disclaimer

This is a personal project, not affiliated with or endorsed by Anthropic or OpenAI. Both usage endpoints are undocumented and can change or disappear without notice; if the popover shows "Resposta da API em formato inesperado", that's probably what happened. Please open an issue.

## License

[MIT](LICENSE)
