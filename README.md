# lsrp_mugshots

`lsrp_mugshots` is a lightweight FiveM resource for roleplay servers that captures a player's mugshot on character load, converts it to Base64 through the `MugShotBase64` dependency, and stores it in MySQL for later use.

It is designed for QB/Qbox-based servers and includes character-aware saving so a player who uses `/logout` and switches to another character gets a fresh mugshot instead of reusing the previous character's image.

## Features

- Captures a player's mugshot automatically after the character finishes loading.
- Stores mugshots in MySQL as Base64 text for later usage in MDTs, police systems, UIs, or exports.
- Uses character-based identifiers when available instead of account-only identifiers.
- Supports character switching without requiring a full game restart.
- Re-captures after common clothing/appearance reload events.
- Automatically creates the `player_mugshots` table on resource start.

## Dependencies

This resource depends on:

- `oxmysql`
- `MugShotBase64`
- `qb-core` in the current `fxmanifest.lua`

Server-side character identification also supports `qbx_core` if it is running, but note that the current manifest explicitly declares `qb-core` as a dependency. If your server is pure Qbox and does not run QB Core, update the manifest accordingly.

## How It Works

### Client flow

The client waits for the player/character to fully load, then requests a mugshot from `MugShotBase64` using the current player ped.

To avoid saving the wrong face during character switching, the client:

- resets pending captures on logout/unload
- waits for the ped appearance to stabilize
- listens for character load and common appearance/clothing reload events
- sends the finished Base64 image to the server only after the correct character model has loaded

### Server flow

When the server receives `mugshot:save`, it resolves a stable identifier for the current player:

1. `char:<citizenid>` from `qbx_core` when available
2. `char:<citizenid>` from `qb-core` when available
3. fallback to `license2:`
4. fallback to `license:`

That identifier is then used as the unique key in the database so each character keeps its own saved mugshot.

## Installation

1. Put the resource in your server resources folder.
2. Make sure `oxmysql` is installed and working.
3. Make sure `MugShotBase64` is installed and starts before this resource.
4. Ensure your core and clothing/appearance resources are already working normally.
5. Add the resource to your server start order.

Example `server.cfg` order:

```cfg
ensure oxmysql
ensure qb-core
ensure MugShotBase64
ensure lsrp_mugshots
```

If you use Qbox, keep the same principle: your core must be running before this resource, and `MugShotBase64` must start before `lsrp_mugshots`.

## Database

The resource automatically creates this table on startup:

```sql
CREATE TABLE IF NOT EXISTS player_mugshots (
    id INT AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(64) NOT NULL UNIQUE,
    mugshot LONGTEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

### Table notes

- `identifier`: unique character or license identifier
- `mugshot`: Base64-encoded mugshot image
- `created_at`: first insert time
- `updated_at`: last time the mugshot was replaced

When the same character logs in again, the existing row is updated instead of creating duplicates.

## Character Switching Support

This resource was built to handle the common RP flow where a player:

1. logs into one character
2. uses `/logout`
3. selects another character without restarting the game

Without character-aware timing, FiveM can still briefly expose the old ped appearance during the next load, which can result in the wrong mugshot being saved. This resource avoids that by waiting for appearance changes and re-triggering capture when clothing/skin events fire.

Supported events currently include:

- `QBCore:Client:OnPlayerLoaded`
- `QBCore:Client:OnPlayerUnload`
- `qbx_core:client:onPlayerLoaded`
- `qbx_core:client:onPlayerUnload`
- `playerSpawned`
- `qb-clothing:client:loadPlayerClothing`
- `qb-clothes:client:loadPlayerClothing`
- `illenium-appearance:client:reloadSkin`

If your server uses a different appearance system, add its client-side skin/clothing load event so the mugshot capture runs after appearance is applied.

## Usage

This resource does not expose a public API by itself. Its job is to populate and maintain the `player_mugshots` table automatically.

Other resources can then query the database and use the stored Base64 image wherever needed.

Example server-side query:

```lua
local identifier = ('char:%s'):format(citizenId)

MySQL.single('SELECT mugshot FROM player_mugshots WHERE identifier = ?', { identifier }, function(row)
    if row and row.mugshot then
        print(('Found mugshot for %s'):format(identifier))
        -- send row.mugshot to your UI, MDT, profile card, etc.
    end
end)
```

## Logging

The resource prints simple debug messages with the `^5[MUGSHOT]^7` prefix, including:

- resource start/stop
- database initialization status
- mugshot save attempts
- missing identifier or missing mugshot cases

## Notes and Limitations

- Image quality depends mostly on the `MugShotBase64` resource and GTA/FiveM ped headshot natives.
- Mugshots are stored as Base64 text, which is convenient but larger than storing file paths or binary blobs.
- The current resource only saves mugshots. It does not include a viewer UI, export, or retrieval callback.
- The current manifest declares `qb-core` as a dependency even though the server code can also resolve characters through `qbx_core`.

## Troubleshooting

### No mugshot is being saved

Check the following:

- `oxmysql` is running correctly
- `MugShotBase64` is installed and started before this resource
- your database credentials are valid
- the player actually reaches a full loaded/spawned appearance state

### The wrong mugshot is saved after switching characters

This usually means your appearance resource applies the skin through an event that is not currently being listened to. Add your appearance event to the client script so capture happens after the new character appearance is fully applied.

### The table is not created

Make sure `@oxmysql/lib/MySQL.lua` loads correctly and check server console output for the database startup message.

## File Overview

- `client.lua`: handles capture timing and character-switch-safe mugshot requests
- `server.lua`: creates the database table and stores mugshots by character identifier
- `fxmanifest.lua`: declares resource metadata and dependencies

## Intended Use Cases

- police MDT systems
- booking/mugshot history
- character profile UIs
- dispatch or law enforcement panels
- admin tools that need a stored player portrait

## Credits

- Resource author: Matyas
- Mugshot generation provided by the `MugShotBase64` dependency