# Drop into THIS folder

Copy from:
`...\cyber_engine_tweaks\mods\MANUAL TRANSMISSION V10\`

## Root files - 3 only

```
init.lua              <- ~1900 lines. All of 2026-08-04's fixes.
config.json           <- your bindings. NumPad "." cycle, NumPad7 reverse.
vehicle_modes.json    <- per-vehicle Manual/Auto memory
```

**Take `init.lua` ONLY.** Not `init.luaback`, not
`init - Copy.lua_V12Command_Module`, not
`FreshhandoffNoshiftmodeswitchinit - Copy.lua`. Three files in that folder are
named like the real one and none of them are.

Skip: `db.sqlite3`, `*.log`, `config.json_bak`, `__folder_managed_by_vortex`,
`V12_DF_DE\`, `Chat history post DF initiation.rtf`.

`menu_debug.txt` and `red_debug.txt` are optional - they regenerate.

## Then the modules folder

See `modules\_DROP_HERE.md`.

Delete this file before zipping.
