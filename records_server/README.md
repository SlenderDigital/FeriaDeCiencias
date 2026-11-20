# Shapes & Beams — Live Records Server

Standalone, zero-dependency, strictly **read-only** HTTP + Server-Sent Events (SSE) server that displays a live-updating replica of the **Shapes & Beams** Main Menu **Records** screen (`RANKING & RECORDS`).

- **Read-only by design**: reads Godot's `save_data.tres` from disk without modifying any game files or communicating back to the game (`POST`, `PUT`, `PATCH`, `DELETE` return `405 Method Not Allowed`).
- **Live updates**: watches `save_data.tres` for changes and pushes updated leaderboards immediately over `/events` (SSE), while keeping your currently selected category tab and scroll position.
- **100% offline & zero dependencies**: runs on Python 3 standard library only, with no external font or script CDNs.

## Quick Start

From the repository root:

```bash
python3 records_server/server.py
```

The server binds to `0.0.0.0:8080` by default and prints both local and LAN URLs:

```text
Shapes & Beams — Live Records Server (read-only)
  Local:    http://localhost:8080
  Network:  http://192.168.1.42:8080
  Watching: /home/user/.local/share/godot/app_userdata/Juego/save_data.tres
```

Open `http://localhost:8080` on the same machine or the `Network` URL from any laptop, tablet, or second-screen browser on the same Wi-Fi/LAN.

## Controls (Webpage)

- Click **GLOBAL**, **EASY**, **NORMAL**, **HARD**, or **BOSS** (or press keys `1`–`5` / `←` / `→`) to switch leaderboard categories locally.

## Configuration

| CLI Flag | Environment Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `--host` | `RECORDS_HOST` | `0.0.0.0` | Address to bind (`127.0.0.1` for local-only) |
| `--port` | `RECORDS_PORT` | `8080` | HTTP port |
| `--save-file` | `RECORDS_SAVE_FILE` | Auto-detect | Explicit path to `save_data.tres` (auto-detect picks newest between Godot `user://save_data.tres` and `juego/data/save_data.tres`) |
| `--poll-interval` | `RECORDS_POLL_INTERVAL` | `0.4` | Save file polling interval in seconds |

## Endpoints

- `GET /` — Records screen HTML page
- `GET /static/*` — Monochrome stylesheet and client script
- `GET /api/records` — Current leaderboard snapshot JSON
- `GET /events` — SSE stream (`event: records`) pushing updates whenever `save_data.tres` changes
- `GET /health` — Server status and watched save file status

## Running Tests

```bash
python3 -m unittest discover -s records_server/tests -v
```
