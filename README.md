# rsg-goldclaim

A combined gold claim + smelter system for RedM (rsg-core). Players can place gold rockers, process paydirt and water into gold nuggets, manage licensed/unlicensed claims, place portable smelters to refine nuggets/ore into bars, and sell or smelt their findings at Gold Agent NPCs. All menus and dialogs use a custom RDR2 leather & gold themed NUI.

This resource merges the former `mack-goldclaim` and `mack-smelter` scripts into a single resource, renaming every event/callback under one `rsg-goldclaim:` prefix.

## Features

### Gold Claim / Rocker
- **Placeable Gold Rocker** â€” Place `p_goldcradlestand01x` anywhere (or restricted areas). Persists across restarts.
- **Licensed & Unlicensed Claims** â€” Players with a `goldclaimlicense` item get a licensed claim with a named zone, blip, and enter/leave notifications. Without a license the claim is flagged as illegal.
- **Claim Zones** â€” Licensed claims create a radius zone (default 20m) with map blips. Other players are warned when entering.
- **LEO Enforcement** â€” Law enforcement can destroy unlicensed claims and confiscate the rocker as evidence.
- **Async Processing** â€” Add paydirt and water to the rocker, start processing, and walk away. The server handles the timer and spawns a gold or paydirt output prop when done.
- **Weighted Nugget Drops** â€” Gold pickups give random nugget types (small/medium/large) with configurable weight distribution and amount ranges.
- **Gathering Tools** â€” Use a shovel in water to dig paydirt. Use a bucket in water to fill it.
- **Equipment Degradation** â€” Cron-based quality degradation. Equipment lost at 0% quality. Repair with 5x wood.
- **Gold Agent NPCs** â€” Smelt nuggets into gold bars and sell gold/silver bars at configurable NPC locations.
- **Rename Claims** â€” Licensed claim owners can rename their claim at any time.

### Smelter
- **Placeable Smelter** â€” Uses `p_campfirecombined01x` as the smelter prop.
- **NUI Crafting Menu** â€” Category tabs (Gold/Silver), item grid, and detail pane for smelting recipes.
- **Gold Smelting** â€” Convert small, medium, or large nuggets into gold bars.
- **Silver Smelting** â€” Convert silver ore into silver bars.
- **Optional Gold Claim Restriction** â€” Restrict smelter placement to within a licensed gold claim (`Config.Smelter.RequireGoldClaim`).
- **Persistent Props** â€” Smelters persist across server restarts via database.

### Shared
- **Custom NUI** — All ox_lib context menus/input dialogs and the smelter crafting UI are implemented as one consistent custom NUI (no external UI dependency), styled per the RDR2 leather & gold theme.
- **ox_lib Notifications** — All game notifications use `lib.notify` (client) / `TriggerClientEvent('ox_lib:notify', ...)` (server).
- **ox_target Integration** — All world interactions (rocker, output props, smelter) use ox_target.

## Dependencies

- [rsg-core](https://github.com/Starter-RSG/rsg-core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)

## Installation

1. **Database** â€” Run `install/rsg-goldclaim.sql` in your database to create the `player_goldrockers` and `player_smelter` tables.

2. **Items** â€” Add the contents of `install/shared_items.lua` to your `rsg-core/shared/items.lua`:
   - `goldrocker` â€” Placeable gold rocker equipment
   - `goldclaimlicense` â€” Grants a licensed claim on placement
   - `bucket` / `fullbucket` â€” For collecting water
   - `shovel` â€” For digging paydirt
   - `paydirt` â€” Raw material for the rocker
   - `smallnugget` / `mediumnugget` / `largenugget` â€” Gold nugget outputs
   - `goldbar` â€” Smelted gold output
   - `wood` â€” Used for rocker repairs
   - `smelter` â€” Placeable smelter equipment
   - `silverore` â€” Raw material for the smelter
   - `silverbar` â€” Smelted silver output

3. **Images** â€” Copy the images from `install/images/` to your `rsg-inventory/html/images/` folder.

4. **Resource** â€” Add to your `server.cfg`:
   ```
   ensure rsg-goldclaim
   ```

## Configuration

All configuration lives in `shared/config.lua`. Rocker/claim settings are top-level `Config.*` values; smelter settings are namespaced under `Config.Smelter.*` to avoid clashing with the rocker settings (both subsystems used to be separate resources with their own generic option names).

### General Settings (Rocker)

```lua
Config.MaxGoldRockers    = 4          -- max rockers per character
Config.DegradeChance     = 5          -- % chance of degradation per cron cycle
Config.CronJob           = '*/30 * * * *'  -- cron schedule (every 30 mins)
Config.RepairWoodAmount  = 5          -- wood needed to repair
Config.ClaimZoneRadius   = 20.0       -- licensed claim zone radius (meters)
```

### Processing

```lua
Config.ProcessingTime    = 60000      -- processing time (ms)
Config.GoldChance        = 50         -- % chance of gold vs paydirt return
Config.AddPaydirtTime    = 10000      -- time to add paydirt (ms)
Config.AddWaterTime      = 10000      -- time to add water (ms)
```

### Nugget Distribution

```lua
Config.NuggetWeights = {
    small  = 50,   -- 50% chance
    medium = 35,   -- 35% chance
    large  = 15,   -- 15% chance
}

Config.NuggetAmounts = {
    small  = { min = 1, max = 10 },
    medium = { min = 1, max = 5 },
    large  = { min = 1, max = 3 },
}
```

### Gold Agent / Smelting Prices (sold via Gold Agent NPCs)

```lua
Config.SmallNuggetSmelt  = 45         -- small nuggets per gold bar
Config.MediumNuggetSmelt = 30         -- medium nuggets per gold bar
Config.LargeNuggetSmelt  = 15         -- large nuggets per gold bar
Config.GoldBarPrice      = 500        -- sell price per gold bar
Config.SilverBarPrice    = 400        -- sell price per silver bar
Config.SmeltTime         = 30000      -- smelting time (ms) at the Gold Agent
```

### Gold Agent NPC Locations

```lua
Config.GoldAgentLocations = {
    {
        name      = 'Valentine Gold Agent',
        coords    = vector3(-303.14, 778.55, 118.70),
        npcmodel  = `s_m_m_bankclerk_01`,
        npccoords = vector4(-303.14, 778.55, 118.70, 110.30),
        showblip  = true,
    },
    -- add more locations here
}
```

### Smelter

```lua
Config.Smelter.MaxSmelters       = 2       -- max smelters per character
Config.Smelter.DestroyTime       = 10000   -- pickup progress time in ms
Config.Smelter.RequireGoldClaim  = false   -- require a licensed gold claim area for placement
Config.Smelter.GoldClaimRadius   = 20.0    -- must match Config.ClaimZoneRadius
Config.Smelter.Recipes           = { ... } -- smelting recipes used by the crafting NUI
```

## Usage

### For Players

1. **Get a Gold Rocker** â€” Obtain a `goldrocker` item.
2. **Optional: Get a License** â€” Having a `goldclaimlicense` in your inventory when placing creates a licensed claim.
3. **Place the Rocker** â€” Use the gold rocker item, position it, and confirm placement.
4. **Gather Materials** â€” Use a `shovel` while standing in water to dig paydirt. Use a `bucket` in water to fill it.
5. **Load the Rocker** â€” Add paydirt and water to the rocker via ox_target.
6. **Process** â€” Start processing from the rocker menu. Walk away and wait for the output prop to appear.
7. **Collect** â€” Pick up the output prop (gold nuggets or paydirt).
8. **Repair** â€” Keep equipment maintained with 5x wood before it degrades to 0%.
9. **Smelt & Sell** â€” Visit a Gold Agent NPC to smelt nuggets into bars and sell them, or place a `smelter` and use its crafting menu to smelt nuggets/ore into bars.

### For Law Enforcement

- Unlicensed claims trigger a server-wide alert.
- LEO players can destroy illegal claims via the rocker menu or ox_target.
- The confiscated rocker is added to the LEO's inventory as evidence.

## Database Schema

```sql
CREATE TABLE `player_goldrockers` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) DEFAULT NULL,
    `owner` varchar(50) DEFAULT NULL,
    `properties` text NOT NULL,
    `propid` int(11) NOT NULL,
    `proptype` varchar(50) DEFAULT NULL,
    `licensed` tinyint(1) NOT NULL DEFAULT 0,
    `claimname` varchar(100) DEFAULT NULL,
    `paydirt` int(3) NOT NULL DEFAULT 0,
    `water` int(3) NOT NULL DEFAULT 0,
    `quality` int(3) NOT NULL DEFAULT 100,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `player_smelter` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) DEFAULT NULL,
  `properties` text NOT NULL,
  `propid` int(11) NOT NULL,
  `proptype` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
```

## Credits

- Originally two separate scripts: `mack-goldclaim` and `mack-smelter`.
- Notifications via ox_lib.
