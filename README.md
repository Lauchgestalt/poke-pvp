<div align="center">

# PokéPVP

**Real-time remote PvP engine for single-player Pokémon Emerald.**

Player 1 plays locally in the mGBA emulator. Player 2 connects via a modern web interface to control opposing trainers (moves, switches, ~~items~~) in real time, replacing the default game AI.

<p align="center">
  <a href="https://mgba.io/downloads.html"><img src="https://img.shields.io/badge/Emulator-mGBA_Nightly-6b5ce7?style=flat-square&logo=retroarch&logoColor=white" alt="mGBA Nightly"></a>
  <a href="https://nodejs.org/"><img src="https://img.shields.io/badge/Node.js-%3E%3D18.0-339933?style=flat-square&logo=node.js&logoColor=white" alt="Node.js"></a>
  <a href="https://svelte.dev/"><img src="https://img.shields.io/badge/Frontend-SvelteKit-ff3e00?style=flat-square&logo=svelte&logoColor=white" alt="SvelteKit"></a>
  <a href="https://tailwindcss.com/"><img src="https://img.shields.io/badge/Styling-Tailwind_CSS-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white" alt="Tailwind CSS"></a>
  <a href="#prerequisites"><img src="https://img.shields.io/badge/ROM-Emerald_(US)_BPEE-e74c3c?style=flat-square&logo=nintendo-game-boy&logoColor=white" alt="ROM Requirement"></a>
</p>

</div>

---

## Disclaimer

This is an unofficial fan project. It is not affiliated with, endorsed by, or sponsored by
Nintendo, Game Freak, Creatures Inc., or The Pokémon Company. Pokémon and all related names,
characters, and assets are trademarks and copyrights of their respective owners.

This repository does not include or distribute the mGBA emulator or any Pokémon ROM. Both are
things you need to obtain yourself, and only legally — this project assumes you already own a
legitimate copy of the game and are using it in accordance with its license. It also doesn't
include any Pokémon sprite assets directly; the web interface fetches them at runtime from
[PokeAPI's sprite repository](https://github.com/PokeAPI/sprites), which is not affiliated with
this project either.

---

## Overview

PokéPVP hooks into mGBA's execution loop via custom Lua memory manipulation. When Player 1 enters a trainer battle, the client halts the enemy AI execution, extracts active battle state (species, moves, PP, party status), and transmits it to a Node.js relay server.

Player 2 interacts with a web dashboard to select moves or switches, which are injected directly into mGBA's RAM prior to turn execution.

> **Inspiration:** This project was inspired by [SmallAnt's YouTube video](https://www.youtube.com/watch?v=S3u7gQhrWZo), where a remote player controlled enemy trainers in real time.

<p align="center">
  <a href="https://www.youtube.com/watch?v=S3u7gQhrWZo" target="_blank">
    <img src="https://img.youtube.com/vi/S3u7gQhrWZo/maxresdefault.jpg" alt="SmallAnt PvP Concept Video" width="30%" style="border-radius: 8px;">
  </a>
  <br>
</p>

---

## Key Features

**Real-Time Command Dashboard:** Activates automatically upon entering a trainer battle. Player 2 views enemy party stats, real-time HP, types, and exact move PP.
<p align="center">
<img src=".github/assets/interface.png" alt="PokéPVP Dashboard" width="600">
</p>

**Synchronized Turn Resolution:** Player 1's turn decision is hidden until Player 2 commits an action, executing both actions simultaneously in mGBA to prevent mid-turn counter-play.
<p align="center">
<img src=".github/assets/fight.gif" alt="PokéPVP Dashboard" width="600">
</p>

**Overworld Stream Preview:** Provides Player 2 with a low-framerate video stream of Player 1's game screen outside of battles.
<p align="center">
<img src=".github/assets/stream.gif" alt="PokéPVP Dashboard" width="600">
</p>

**Custom Display Name:** Player 2 can set a custom handle that replaces opposing trainer names in battle text.
<p align="center">
<img src=".github/assets/ingame.png" alt="PokéPVP Dashboard" width="600">
</p>

---

## Roadmap

| Feature | Status | Description
| --- | --- | --- |
| **Item Usage** | ![research](https://cdn.jsdelivr.net/gh/Readme-Workflows/Readme-Icons@main/icons/octicons/Repository.svg) Research | In-battle item usage (e.g., Potions, battle items) by Player 2 is currently disabled pending further reverse-engineering of item execution memory offsets. |
| **Support for more editions** | ![planned](https://cdn.jsdelivr.net/gh/Readme-Workflows/Readme-Icons@main/icons/octicons/IssueDrafted.svg) Planned | Currently, only Pokémon Emerald (US) is supported. Future work may include support for other Pokémon editions, after reverse-engineering their respective memory layouts. |
| **Improved Battle UI** | ![planned](https://cdn.jsdelivr.net/gh/Readme-Workflows/Readme-Icons@main/icons/octicons/IssueDrafted.svg) Planned | Enhancements to the web dashboard, getting the browser experience closer to the actual game. |
| **Hosted Relay Service** | ![planned](https://cdn.jsdelivr.net/gh/Readme-Workflows/Readme-Icons@main/icons/octicons/IssueDrafted.svg) Planned | A public relay service that allows players to connect without needing to host their own relay server. |
| **Twitch Integration** | ![planned](https://cdn.jsdelivr.net/gh/Readme-Workflows/Readme-Icons@main/icons/octicons/IssueDrafted.svg) Planned | Allowing Twitch viewers to vote on Player 2's actions. |

---

## Prerequisites

| Requirement | Specification | Notes |
| --- | --- | --- |
| **mGBA** | Development / Nightly Build | Requires support for `emu:setBreakpoint()`, which is unavailable in stable releases (`v0.10.x` or older). |
| **Game ROM** | Pokémon Emerald (US) | Header `BPEE`. Memory addresses are hardcoded specifically for this binary layout. |
| **Node.js** | `v18.0.0` or higher | Required for the relay server and web interface. |

> [!NOTE]
> `client.lua` checks the loaded ROM's header on startup and refuses to run at all if it isn't
> `BPEE` (logging an error in the mGBA console instead) — memory addresses are hardcoded for that
> exact binary layout, and running against any other ROM would misalign every one of them.

---

## Running It

Every setup below shares the same two building blocks:

- **The relay** (`server.js`) — serves the web interface, the WebSocket, and the screenshot
  preview, all on one port (`8766` by default). Started with `npm start` from the repo root, which
  also builds the interface first.
- **`lua/client.lua`**, loaded into mGBA — connects out to the relay at `RELAY_HOST:8765` (the one
  constant at the very top of the file, `127.0.0.1` by default).

What changes between setups is only *where* the relay runs and what address each piece points at.
Pick the section that matches.

### A. Same network (including just one machine)

Covers solo testing on one PC, *and* the common case of two people in the same house on the same
WiFi/LAN — neither needs a tunnel or any source edits, just possibly a different URL.

Whoever's hosting runs:

```bash
git clone https://github.com/Lauchgestalt/poke-pvp.git
cd poke-pvp
npm run setup   # once
npm start       # every session
```

You'll see:

```text
[relay] listening for emulator on tcp://127.0.0.1:8765
[relay] serving the interface + websocket + screenshot on http://127.0.0.1:8766
```

Then, in mGBA: **Tools → Scripting… → File → Load Script**, select `lua/client.lua`, and confirm
the console shows:

```text
[client] connected to relay
[client] PokePVP client.lua loaded (ROM: BPEE)
```

Now, which URL to open depends on whether Player 2 is on the *same* computer or a *different* one
on the same network:

- **Same computer**: open `http://localhost:8766`.
- **Different device, same WiFi/LAN**: find the host machine's local IP (Windows: `ipconfig`,
  look for `IPv4 Address`; macOS/Linux: `ifconfig` or `ip addr`, look for something like
  `192.168.x.x`), and have Player 2 open `http://<that-ip>:8766` instead. You may need to allow
  the connection through the host's firewall the first time (Windows will prompt automatically).

Either way, `RELAY_HOST` in `lua/client.lua` stays `127.0.0.1` — mGBA and the relay are still on
the same machine, only *Player 2's* address changes.

### B. Different networks, one person hosts everything

Player 1 still runs mGBA *and* the relay together as in **Setup A**; Player 2 still only ever
needs a browser. The difference is exposing the relay's port through a tunnel instead of just
sharing a local IP:

1. Do everything in **Setup A** above.
2. Expose the relay's port with a tunnel. Cloudflare's free "quick tunnel" needs no account and no
   config file:
   ```bash
   cloudflared tunnel --url http://localhost:8766
   ```
   ([install instructions](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) if you don't have `cloudflared` yet)
3. It prints a `https://<random-name>.trycloudflare.com` URL. That's the
   whole handoff for Player 2. The page derives its own WebSocket/screenshot connections from whatever address
   loaded it, so the tunnel URL just works with no further setup.

Still no source edits necessary. `RELAY_HOST` stays `127.0.0.1` because the relay and mGBA are on the same
machine, regardless of how Player 2 reaches that machine from outside.

> Port forwarding on your router is another way to make the relay reachable without a tunnel — but
> exactly how depends entirely on your specific router's admin interface, so it's outside what we
> can give instructions for here. A tunnel is the easier default for most people.

The one downside: the tunnel URL is random and changes every time you restart `cloudflared`, so
you re-share it each session.

### C. Different networks, the relay hosted separately

You can also run the relay somewhere permanent with a fixed address, instead of creating a new tunnel URL every
session, at the cost of actually maintaining a small always-on service.

1. On that separate machine: clone the repo, `npm run setup`, then start the relay with
   `EMULATOR_BIND_HOST=0.0.0.0 npm start` - the emulator port only listens on `127.0.0.1` by
   default, since normally mGBA runs on the same machine as the relay; this setup is the one
   exception, so it has to opt in explicitly. Keep it running (e.g. via `pm2` or a systemd
   service, so it survives you logging out).
2. Open its firewall / security group on `8765` and `8766`.
3. On Player 1's machine, clone the repo, edit the `RELAY_HOST` at the top of
   `lua/client.lua` to that machine's address, then load the script into mGBA as usual.
4. Player 2 opens `http://<that-machine's-address>:8766` directly. No tunnel needed; the
   address is already public.

The screen stream (`Stream` tab) travels over the same TCP link to the relay and WebSocket link
to the browser that everything else already uses, so no shared filesystem between mGBA's machine
and the relay is needed.

### Controller token (who's allowed to play)

The relay prints a random **controller token** to its console every time it starts:

```
[relay] controller token: aB3xQ... (share this with Player 2, not spectators)
```

Anyone who opens the page can watch the stream and the live battle state, but only the browser
that submits this token can actually pick moves, switch Pokémon, set a trainer name, or toggle the
screenshot stream — everyone else is a read-only spectator. Send the token to Player 2 alongside
the URL (Settings → Controller token), and don't post it anywhere public. Set `CONTROLLER_TOKEN`
in the environment before `npm start` if you want a fixed token that survives restarts instead of
a fresh random one each time.

> [!WARNING]
> The controller token is the only thing standing between "Player 2" and anyone who has the URL —
> treat it like a password. Setup B's random, private-by-obscurity tunnel URL (or a
> same-network-only local IP) is low-risk in practice even without one; a standing public IP:port
> (Setup C) is the case where it actually matters, since that address isn't secret at all.

> Making changes to the web interface itself? `npm run dev` inside `interface/` runs a normal Vite
> dev server with hot reload, instead of the built-and-served flow above.

---

## Architecture

[![](https://mermaid.ink/img/pako:eNqNUslOwzAQ_RVrTkWKspTQJWorsQkQi6q2CAnCwU2mqSGxK8dhq_rvTBwqKjiALx6P3-aR15CoFCGCRa5ekyXXhl1NYh1LRqus5pnmqyW7UgnP2UMM45y_o2YBa52r0uzF8LjF1qs4OzokUL2x06LKuVF6MNfeaFCbjPKKe0kuUBqXyoFnmzsSKNO6_OU-Rf1CpqQ8QfJnpzITEn942yuC3JCo-1R-kXbcS9vwmo0Q__efYKEM7jy_zVpN7-cA7nB-e0G46QvmBi-FYRfSoF7wBHeSiG3P-zODHeVgOGQxzI7HrDU1nJJ47DAxQklSf0JbURA2HI6aKWzJzbQaNiWbquQZDZHPZ7PxF94GBgcyLVKIjK7QgQJ1wesjrGudGMwSCxp3RGXK9XMMsdwQZ8XlvVLFlqZVlS0hWvC8pFO1SinpieA0wm8IvQ71saqkgagdWgmI1vAGUbjvHvi-HwRhGPr9oOfAO0TdwO36vU7QCzqh32kfbBz4sI6-2-tauE_X_e5-v-0ApoK-23XzmxMlFyKDzSdizeeI?type=png)](https://mermaid.live/edit#pako:eNqNUFlPwkAQ_iubecKE9IByNZTEK2I0hgDGROvD0g5QbXfJdqsi4b873UJs9EH3ZWdmv2tnB5GMEXxYpvI9WnOl2e00VKFgdPJisVJ8s2a3MuIpewphkvItKuayxljm-iSE5yO2PNnV2SmByotdZkXKtVTDhbJHw9JklBbcjtIEhbaoHNpmWJNAEZflL_cZqjcyJeUpkj-7FKtE4A9v80SQOxK1XvIDqeaem4FdXYT4v_8UM6mx9v0Wa1Sznwt4wMX9NeFmb5hqvEk0uxYa1ZJHWEuSHGf2nxnMKodBwEKYn09YY6Y5JbHZaaQTKUj9BU1FQVgQjKotHMnVtio2JZvJ6BU1kcfz-eSAN4GhCSuVxOBrVWATMlQZL1vYlToh6DVmtG6fypir1xBCsSfOhotHKbMjTclitQZ_ydOcumITU9KLhNMKvyH0O1TnshAa_FbbSIC_gw_wvbbVcRzHdT3PcwZuvwlb8Huu1XP6Xbfvdj2n2-rsm_BpHB2r3zNwh54Hvfagtf8CzXXgFw)

| Subsystem | Stack | Responsibility |
| --- | --- | --- |
| **Emulator Hook** | `Lua` | Intercepts turn decisions via breakpoints, reads battle state, and writes injected commands into RAM. |
| **Relay Server** | `Node.js` | TCP↔WebSocket bridge, plus serves the built interface and the screenshot preview — all three over one port. |
| **Web Dashboard** | `SvelteKit` / `Tailwind` | Remote interface for Player 2 featuring active party management, move selection, and live logs. |

---

## Repository Structure

```text
pokepvp/
├── package.json             # root-level setup/build/start scripts
├── lua/
│   └── client.lua           # mGBA Lua RAM hooks, state extraction & turn injection
├── server/
│   └── server.js            # relay: TCP <-> WebSocket, serves the built interface + screenshot
└── interface/                # SvelteKit + Tailwind web application (built to interface/build)
    └── src/
        ├── lib/             # State management, socket adapters, and UI components
        └── routes/          # Layouts, dashboard views, and routing logic

```

---

## Development & Acknowledgments

Built in collaboration with **Claude Code** (Anthropic). AI capabilities were leveraged for:

* Cross-referencing public symbol tables from the [pret/pokeemerald](https://github.com/pret/pokeemerald) decompilation project to map GBA memory offsets.
* Proposing and validating state-handling architecture for WebSocket synchronization.
* Generating static data registries for species, move indexes, and battle metadata (`interface/src/lib/data/`).