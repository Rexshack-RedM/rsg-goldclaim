Config = {}
Config.PlayerProps = {}

-- Debug Settings
Config.Debug = false

---------------------------------------------
-- general settings (gold rocker / claims)
---------------------------------------------
Config.EnableVegModifier    = true                   -- clears vegetation around placed rockers
Config.GoldRocker           = `p_goldcradlestand01x` -- prop used for gold rocker
Config.MaxGoldRockers       = 4                      -- maximum gold rockers per character
Config.DegradeChance        = 5                      -- % chance of equipment degrading per cron cycle
Config.CronJob              = '*/30 * * * *'         -- cron schedule for degradation only
Config.CycleNotify          = true                   -- print when cron cycle runs
Config.RepairWoodAmount     = 5                      -- amount of wood needed to repair
Config.EnableTarget         = true                   -- toggle target for gold agent NPCs

---------------------------------------------
-- processing settings
---------------------------------------------
Config.ProcessingTime       = 60000                  -- time in ms to process (1 minute)
Config.GoldChance           = 50                     -- % chance of gold vs paydirt return
Config.AddPaydirtTime       = 10000                  -- time in ms to add paydirt to rocker
Config.AddWaterTime         = 10000                  -- time in ms to add water to rocker
Config.MaxPaydirt           = 5                      -- max paydirt units a rocker can hold
Config.MaxWater             = 5                      -- max water units a rocker can hold
Config.RepairTime           = 10000                  -- time in ms to repair
Config.CollectGoldTime      = 10000                  -- time in ms to pack up

---------------------------------------------
-- nugget weight distribution
---------------------------------------------
Config.NuggetWeights = {
    small  = 50,  -- 50% chance
    medium = 35,  -- 35% chance
    large  = 15,  -- 15% chance
}

---------------------------------------------
-- nugget amount ranges (random between min/max)
---------------------------------------------
Config.NuggetAmounts = {
    small  = { min = 1, max = 10 },
    medium = { min = 1, max = 5 },
    large  = { min = 1, max = 3 },
}

---------------------------------------------
-- gathering settings (shovel / bucket)
---------------------------------------------
Config.ShovelDigTime        = 10000                  -- time in ms to dig paydirt
Config.BucketFillTime       = 8000                   -- time in ms to fill bucket

---------------------------------------------
-- prop models
---------------------------------------------
Config.GoldProp             = `p_goldstack01x`                -- gold output prop
Config.PaydirtProp          = `mp005_p_dirtpile_sca02_buried` -- paydirt output prop
Config.PropSpawnOffset      = 1.5                             -- distance to side of rocker to spawn output prop

---------------------------------------------
-- shovel prop (attached to hand during dig)
---------------------------------------------
Config.ShovelProp = {
    model = 'p_shovel02x',
    bone  = 'skel_r_hand',
    offset = {0.06, -0.06, -0.03, 270.0, 165.0, 150.0},
}

---------------------------------------------
-- animations
---------------------------------------------
Config.Anims = {
    dig = {
        dict = 'amb_work@world_human_gravedig@working@male_b@base',
        name = 'base',
    },
    crouch_inspect = 'WORLD_HUMAN_CROUCH_INSPECT', -- scenario
    add_paydirt = 'WORLD_HUMAN_FEED_PIGS',         -- scenario used when adding paydirt to a rocker
    add_water = 'WORLD_HUMAN_BUCKET_POUR_LOW',     -- scenario used when adding water to a rocker
    bucket_fill = {
        dict = 'amb_work@world_human_bucket_fill@working@male_b@base',
        name = 'base',
    },
    processing = {
        dict = 'amb_work@world_human_gravedig@working@male_b@idle_a',
        name = 'idle_a',
    },
}

---------------------------------------------
-- claim zone settings
---------------------------------------------
Config.ClaimZoneRadius      = 20.0                   -- radius in meters for licensed claim zone

---------------------------------------------
-- claim blip settings
---------------------------------------------
Config.ClaimBlip = {
    blipSprite = 'blip_gold',
    blipScale  = 0.2,
    blipColour = 'BLIP_MODIFIER_MP_COLOR_6',
}

---------------------------------------------
-- equipment blip settings (legacy for rocker)
---------------------------------------------
Config.Blip = {
    blipName   = 'Gold Claim',
    blipSprite = 'blip_gold',
    blipScale  = 0.2,
    blipColour = 'BLIP_MODIFIER_MP_COLOR_6',
}

---------------------------------------------
-- gold agent / smelting settings
---------------------------------------------
Config.SmallNuggetSmelt  = 45
Config.MediumNuggetSmelt = 30
Config.LargeNuggetSmelt  = 15
Config.GoldBarPrice      = 500
Config.SilverBarPrice    = 400
Config.SmeltTime         = 30000

---------------------------------------------
-- gold agent blip settings
---------------------------------------------
Config.GoldAgentBlip = {
    blipName   = 'Gold-Silver Agent',
    blipSprite = 'blip_gold',
    blipScale  = 0.2,
}

---------------------------------------------
-- deploy prop settings (rocker placement system)
---------------------------------------------
Config.ForwardDistance    = 2.0
Config.PromptGroupName   = 'Place Equipment'
Config.PromptCancelName  = 'Cancel'
Config.PromptPlaceName   = 'Set'
Config.PromptRotateLeft  = 'Rotate Left'
Config.PromptRotateRight = 'Rotate Right'

---------------------------------------------
-- npc settings
---------------------------------------------
Config.DistanceSpawn = 20.0
Config.FadeIn        = true
Config.Keybind       = 'J'

---------------------------------------------
-- gold agent locations
---------------------------------------------
Config.GoldAgentLocations = {
    {
        name      = 'Valentine Gold Agent',
        prompt    = 'val-goldagent',
        coords    = vector3(-303.14, 778.55, 118.70),
        npcmodel  = `s_m_m_bankclerk_01`,
        npccoords = vector4(-303.14, 778.55, 118.70, 110.30),
        showblip  = true,
    },
    {
        name      = 'St Denis Gold Agent',
        prompt    = 'std-goldagent',
        coords    = vector3(2651.56, -1293.23, 52.25),
        npcmodel  = `s_m_m_bankclerk_01`,
        npccoords = vector4(2651.56, -1293.23, 52.25, 114.41),
        showblip  = true,
    },
    {
        name      = 'Rhodes Gold Agent',
        prompt    = 'rho-goldagent',
        coords    = vector3(1288.81, -1298.36, 77.04),
        npcmodel  = `s_m_m_bankclerk_01`,
        npccoords = vector4(1288.81, -1298.36, 77.04, 232.77),
        showblip  = true,
    },
}

---------------------------------------------------------------------------
-- Smelter subsystem
-- Namespaced under Config.Smelter to avoid colliding with the rocker
-- settings above (both scripts originally shipped as separate resources
-- and both used generic names like PlayerProps / ForwardDistance / etc.)
---------------------------------------------------------------------------
Config.Smelter = {}
Config.Smelter.PlayerProps = {}

---------------------------------------------
-- deploy prop settings (smelter placement system)
---------------------------------------------
Config.Smelter.ForwardDistance  = 1.5
Config.Smelter.PromptGroupName  = 'Place Smelter'
Config.Smelter.PromptCancelName = 'Cancel'
Config.Smelter.PromptPlaceName  = 'Place'
Config.Smelter.PromptRotateLeft  = 'Rotate Left'
Config.Smelter.PromptRotateRight = 'Rotate Right'

---------------------------------------------
-- general settings
---------------------------------------------
Config.Smelter.EnableVegModifier = true                       -- if set true clears vegetation around smelter
Config.Smelter.DestroyTime       = 10000                      -- how long for destroy progress bar (ms)
Config.Smelter.MaxSmelters       = 2                          -- max smelters a character can have
Config.Smelter.SmelterProp       = 'p_campfirecombined01x'    -- prop used for smelter

---------------------------------------------
-- gold claim restriction
-- NOTE: If true, the player must be standing within the radius of one of
-- their own licensed gold claims (from the rocker subsystem) to place a smelter
---------------------------------------------
Config.Smelter.RequireGoldClaim  = false
Config.Smelter.GoldClaimRadius   = 20.0                       -- must match Config.ClaimZoneRadius above

---------------------------------------------
-- smelting settings (informational; actual amounts live in Config.Smelter.Recipes)
---------------------------------------------
Config.Smelter.SmallNuggetSmelt  = 45                         -- small nuggets required for 1 gold bar
Config.Smelter.MediumNuggetSmelt = 30                         -- medium nuggets required for 1 gold bar
Config.Smelter.LargeNuggetSmelt  = 15                         -- large nuggets required for 1 gold bar
Config.Smelter.SilverOreSmelt    = 15                         -- silver ore required for 1 silver bar
Config.Smelter.SmeltTime         = 30000                      -- time to smelt one bar (ms)

---------------------------------------------
-- recipes (used by the NUI crafting system)
---------------------------------------------
Config.Smelter.Recipes = {
    ["goldbar_small"] = {
        name = "Gold Bar (Small Nuggets)",
        crafttime = 30000,
        category = "Gold",
        ingredients = {
            [1] = { item = "smallnugget", amount = 45 }
        },
        receive = "goldbar"
    },
    ["goldbar_medium"] = {
        name = "Gold Bar (Medium Nuggets)",
        crafttime = 30000,
        category = "Gold",
        ingredients = {
            [1] = { item = "mediumnugget", amount = 30 }
        },
        receive = "goldbar"
    },
    ["goldbar_large"] = {
        name = "Gold Bar (Large Nuggets)",
        crafttime = 30000,
        category = "Gold",
        ingredients = {
            [1] = { item = "largenugget", amount = 15 }
        },
        receive = "goldbar"
    },
    ["silverbar"] = {
        name = "Silver Bar",
        crafttime = 30000,
        category = "Silver",
        ingredients = {
            [1] = { item = "silverore", amount = 50 }
        },
        receive = "silverbar"
    },
}
