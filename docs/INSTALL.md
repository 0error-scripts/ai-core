# Installing Aicore

## Requirements

- FiveM server (latest recommended artifacts)
- MariaDB / MySQL database
- [ox_lib](https://github.com/overextended/ox_lib) (latest)
- [oxmysql](https://github.com/overextended/oxmysql) (latest)
- OneSync Infinity enabled

## Steps

1. Copy `resources/aicore` (and optionally `resources/aicore_bridge`) into your server's `resources/` folder.
2. Create the database from `sql/aicore.sql` (or let the core create tables on first start — `ensureSchema` runs automatically).
3. Copy `server.cfg.example` to your server data folder as a starting point and edit:
   - `mysql_connection_string` — your database credentials
   - `sv_hostname`, `sv_maxclients`
4. Grant admin: `add_ace group.admin aicore.admin allow` (or give specific users `add_principal identifier.steam:<hex> group.admin`).
5. Start the server. First join auto-creates a character — no UI needed for v0.1.

## server.cfg essentials

```cfg
set onesync on
setr sv_stateBagStrictMode true
set mysql_connection_string "mysql://aicore:secret@localhost/aicore?charset=utf8mb4"

ensure ox_lib
ensure oxmysql
ensure aicore
# ensure aicore_bridge  # optional: QBox/QBCore script compatibility
```

See `server.cfg.example` for the full annotated file.
