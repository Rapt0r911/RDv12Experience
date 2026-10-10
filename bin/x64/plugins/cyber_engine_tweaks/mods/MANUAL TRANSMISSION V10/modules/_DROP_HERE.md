# Drop into THIS folder

Copy from:
`...\mods\MANUAL TRANSMISSION V10\modules\`

## The 9 .lua files

```
clutch.lua           gearbox.lua *        gearboxFeel.lua
gui.lua              introsequence.lua    shiftModes.lua *
thermalV12.lua       utils.lua            voicesystem.lua
```

`*` = edited 2026-08-04. `gearbox.lua` got the lazy blackboard resolver;
`shiftModes.lua` got Red gear engagement, the reverse gate and red_debug logging.
If either looks like an older copy, you grabbed the wrong one.

(`gui.lua` is an empty stub nothing requires. Harmless. Delete it if you like.)

## The 3 subfolders - all required

```
keanuWheeze\    inputManager.lua, config.lua   <- input layer. Mod is dead without it.
psiberx\        GameUI.lua                     <- UI hooks
utils\          cron.lua
```

Skip the `__folder_managed_by_vortex` markers inside them.

## DO NOT copy these

```
back up\
Full solid build, first video addded\
V12 Command Beta Solid Build Audio\
Devloader\
Voice trigger\
NCPDPPE\
```

Every one holds an old `gearbox.lua` or `init.lua`. Copying them forward is how
this project ended up unable to tell which file was live.

## Final check

9 .lua files, 3 folders. Nothing else. Delete this file before zipping.
