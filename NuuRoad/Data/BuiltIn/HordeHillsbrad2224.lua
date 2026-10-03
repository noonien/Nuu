local _, ns = ...

-- Horde 22-24 leveling route through the Sepulcher, Tarren Mill, Durnholde Keep
-- and the Hillsbrad farms, ported from the Hillsbrad half of RestedXP's Classic
-- "22-25 Hillsbrad / South Barrens" (RestedXP Horde 20-30.lua, from its start to
-- the hearth to Thunder Bluff; the Moonglade, Mulgore and southern Barrens rest
-- of that registration is NuuRoad's Southern Barrens guide). The player arrives
-- from Orgrimmar. Step order follows the source; every quest, NPC, object and
-- item ID and every coordinate was checked against Questie's Forever database
-- (QuestieDB_Forever), and every NPC stands where that database puts them. Wowhead's
-- Forever list for Hillsbrad has no new Horde quests (its two new ones, 98059 and
-- 98071, are Alliance), and the quests used here are unchanged there apart from
-- reward additions (Elixir of Pain, WANTED: Syndicate Personnel).
--
-- Notes:
--   * The source's TBC and Wrath steps (riding trainers, Blood Elf turn-ins at
--     Silvermoon and Tarren Mill, the Druid's Trial of the Sea Lion chest) are
--     left out; Forever has none of them.
--   * The source kills Citizen Wilkes and Farmer Kalaba for Dangerous! (567)
--     without ever taking the quest; its 22-25 JJ variant takes it from the
--     poster in the Tarren Mill inn, so this guide does too. Clerk Horrace
--     Whitesteed and Miner Hackett are left for a later visit, as the source
--     leaves them.
--   * Journey to Tarren Mill, Blood of Innocents and the Shaman's Call of Water
--     are gated on being in the log instead of on class: the source gives them to
--     Shamans and Warriors because those classes took Forsaken Aid earlier, and
--     anyone who did can do them.
--   * The source's repeated food, drink and arrow purchases at each Tarren Mill
--     visit are one step per item per visit; a step is done once the bags hold
--     the count, so a second visit with enough left passes by.
--   * The weapon and armour purchases are gated on money only. The source also
--     compares the armour of the worn legs and bracers, which the step
--     conditions cannot read; the note says to buy only when it is an upgrade.
--     The "equip" reminders become notes on the purchase steps.
--   * The Jailors' keys: the source kills Jailor Eston twice, once before Tog'thar
--     and again before Drull. The second key step is done at once if the first
--     key is still in the bags.
--   * Battle of Hillsbrad (529) and Souvenirs of Death (546) are finished but not
--     turned in, as in the source, which hands them in on its next visit around
--     level 30. The closing note says so and offers the turn-in now instead.
--   * Enraged Stanley, who attacks after Elixir of Pain is handed in, is a
--     kill step of its own with no quest.
--   * Deathguard Samsa's Souvenirs of Death joins the Tarren Mill turn-in card,
--     where the source takes it just after; she offers it once the first Battle
--     of Hillsbrad is in. The source's "#xprate >1.499" turn-in of 529 and 546 is
--     not ported.
--   * CompareGuideOrder is clean. CheckGroups still pairs each jailor's key with
--     the ball and chain it opens; they stay apart because the key has to be in
--     the bags first, and a key pickup cannot be a group member.
--
-- Check in client:
--   * Mura Runetotem (8385) standing in the Sepulcher for Mura Runetotem (3301),
--     and Yuriv's Tombstone at 44.19, 42.67 there for Until Death Do Us Part;
--     the database places both, but no Forever session has recorded them.
--   * Which key each Ball and Chain takes (Tog'thar's and Drull's).
--   * That Ott still sells the Merciless Axe and Broad Bladed Knife and Kris
--     Legace the Stalking Pants and Wolf Bracers on Forever, and their prices
--     (the gold gates are the source's Classic prices).
--   * The Spring Well's position for the Filled Red Waterskin (the database's
--     object spot).
--
-- Guide format v2 (see Data/Steps.lua). Coordinates are map percentages.
-- Maps: 1424 Hillsbrad Foothills (guide default), 1421 Silverpine Forest,
-- 1420 Tirisfal Glades, 1411 Durotar.
local durnholde = {
    { 75.29, 40.17 }, { 76.53, 41.00 }, { 77.28, 43.55 }, { 78.98, 45.09 }, { 80.97, 46.77 }, { 82.24, 42.50 },
    { 81.92, 39.69 }, { 83.83, 40.78 }, { 79.70, 43.22 }, { 78.25, 41.30 }, { 77.58, 39.23 }, { 76.47, 46.62 },
    { 66.04, 45.78 }, { 64.87, 47.17 }, { 66.13, 48.44 }, { 67.11, 50.53 },
}
local lions = {
    { 39.79, 34.43 }, { 38.45, 38.77 }, { 37.97, 44.59 }, { 40.91, 44.23 }, { 43.36, 39.38 }, { 51.28, 35.37 },
    { 54.29, 31.75 }, { 52.93, 29.45 }, { 54.77, 28.72 },
}
local bears = {
    { 40.88, 33.87 }, { 40.85, 39.42 }, { 37.68, 41.23 }, { 40.40, 44.65 }, { 45.23, 39.62 }, { 49.75, 34.33 },
    { 52.06, 36.86 }, { 52.39, 29.27 }, { 57.38, 22.85 }, { 58.08, 28.07 }, { 59.68, 30.90 }, { 59.89, 36.74 },
    { 62.63, 37.64 }, { 66.52, 34.52 },
}
local creepers = {
    { 62.85, 38.74 }, { 60.92, 37.92 }, { 59.62, 33.33 }, { 56.88, 29.73 }, { 57.63, 24.16 }, { 56.47, 16.42 },
    { 60.54, 13.67 }, { 64.43, 10.22 }, { 65.31, 5.76 }, { 70.39, 8.89 }, { 67.35, 12.95 }, { 71.78, 21.89 },
    { 64.85, 24.92 }, { 69.76, 31.89 }, { 67.62, 37.65 },
}
local farms = {
    { 35.90, 40.63 }, { 33.88, 41.80 }, { 30.19, 38.48 }, { 30.67, 35.21 }, { 31.71, 36.72 }, { 33.67, 35.66 },
}
local town = {
    { 36.64, 45.21 }, { 36.03, 44.40 }, { 34.36, 44.62 }, { 33.82, 45.75 }, { 33.25, 48.54 }, { 34.59, 48.13 },
    { 35.29, 47.28 }, { 36.49, 47.49 },
}

ns.builtInGuides = ns.builtInGuides or {}
ns.builtInGuides["nuuroad:leveling:horde-hillsbrad-22-24"] = {
    schema = 2,
    id = "nuuroad:leveling:horde-hillsbrad-22-24",
    updated = 1790985600,
    map = 1424,
    only = "Horde",
    meta = {
        title = "Tarren Mill",
        author = "NuuRoad",
        category = "Leveling/Hillsbrad Foothills",
        tags = { "horde", "hillsbrad", "tarren mill", "durnholde", "sepulcher" },
        levels = { 22, 24 },
    },
    steps = {
        { section = "To the Sepulcher", map = 1421, steps = {
            { travel = "Tirisfal Glades", zone = "Tirisfal Glades", at = { 50.83, 13.72, map = 1411 }, radius = 0.03,
                note = "Take the zeppelin to the Undercity from the tower outside Orgrimmar." },
            { travel = "The Sepulcher", subzone = "The Sepulcher", radius = 0.04,
                at = { { 45.51, 41.26 }, { 60.60, 58.50, map = 1420 } },
                note = "If you have the Sepulcher flight path, fly there from the Undercity. If not, walk south from the zeppelin tower past the Undercity into Silverpine Forest and down the road." },
            { group = {
                { accept = 493, npc = 1937,
                    note = "Apothecary Renferrel is down in the crypt." },
                { turnin = 3301, npc = 8385, only = "quest 3301" },
            } },
            { object = "Yuriv's Tombstone", turnin = 264, only = "quest 264", at = { 44.19, 42.67 },
                note = "The gravestone lies on the ground beside the crypt." },
            { flight = "The Sepulcher", npc = 2226 },
        } },

        { section = "Into Hillsbrad", steps = {
            { travel = "Hillsbrad Foothills", zone = "Hillsbrad Foothills", radius = 0.04,
                at = { { 20.79, 47.40 }, { 61.47, 67.47, map = 1421 }, { 67.14, 79.06, map = 1421 } },
                note = "Follow the road south and east out of Silverpine. The Dalaran Wizards near the dome cast Frostbolt, which slows you; give them room." },
            { accept = 494, npc = 2214,
                note = "Deathstalker Lesh waits by the road where it enters Hillsbrad." },
            { flight = "Tarren Mill", npc = 2389,
                note = "Zarise, at the north edge of Tarren Mill." },
        } },

        { section = "Tarren Mill", steps = {
            { group = {
                { turnin = 493, accept = { 496, 501 }, npc = 2216,
                    note = "Apothecary Lydon is inside the building on the west side of the town." },
                { turnin = 1065, accept = 1066, npc = 2216, only = "quest 1065" },
                { turnin = 494, accept = 527, npc = 2215 },
                { object = "WANTED", accept = 549, at = { 62.63, 20.75 } },
                { accept = 498, npc = 2229 },
                { object = "Dangerous!", accept = 567, at = { 62.56, 19.66 },
                    note = "The poster hangs inside the inn." },
            } },
            { objective = 1536, part = 1, collect = 7771, use = 7768, object = "Spring Well", only = "Shaman | quest 1536",
                at = { 62.18, 20.79 },
                note = "Use the Empty Red Waterskin at the well in the middle of the town." },
            { buy = 1205, count = 20, npc = 2388, only = "Priest or Mage or Warlock or Druid or Shaman | now gold 2000",
                note = "Melon Juice from Innkeeper Shay, inside the inn." },
            { buy = 3770, count = 20, npc = 2388, only = "not Priest | not Mage | not Warlock | not Druid | now gold 2000",
                note = "Mutton Chops from Innkeeper Shay. Shamans need only about ten." },
            { buy = 2515, count = 1000, npc = 2401, only = "Hunter | not now level 25 | now gold 250",
                note = "Sharp Arrows from Kayren Soothallow." },
            { buy = 3030, count = 1000, npc = 2401, only = "Hunter | now level 25 | now gold 1500",
                note = "Razor Arrows from Kayren Soothallow." },
            { buy = 923, npc = 3539, only = "Rogue | now slot 16 dps < 12.2 | now gold 8722",
                note = "Ott, the weaponsmith south of the town, sells the Longsword. Equip it." },
            { buy = 12249, npc = 3539, only = "Shaman or Warrior | now slot 16 dps < 21.09 | now gold 30343",
                note = "Ott sometimes has a Merciless Axe. Buy it if he does, and wear it from level 26." },
            { buy = 12247, npc = 3539, only = "Rogue | now slot 16 dps < 16.75 | now gold 28372",
                note = "Ott sometimes has a Broad Bladed Knife. Buy it if he does, and wear it from level 27." },
            { vendor = "repair", npc = 3539,
                note = "Sell your trash and repair while you are at Ott." },
        } },

        { section = "Durnholde Keep", steps = {
            { track = 496, note = "Gray Bears and Vicious Gray Bears drop the tongues, Forest Moss Creepers the ichor. Kill any on the way. Elder Gray Bears are not worth the time." },
            { travel = "Durnholde Keep", subzone = "Durnholde Keep", at = { 76.72, 46.22 }, radius = 0.04 },
            { track = 549, note = "Kill Syndicate Rogues and Watchmen as you go. With Blood of Innocents, the Shadow Mages drop the vials." },
            { collect = 3467, quest = 498, kill = 2427, at = { 79.60, 41.83 },
                note = "Jailor Eston stands in front of Tog'thar's barracks." },
            { collect = 3499, quest = 498, kill = 2428, at = { { 79.49, 40.57 }, { 77.99, 40.19 } },
                note = "Jailor Marlgen is in front of Tog'thar or at the bottom of the tower." },
            { objective = 498, part = 2, object = "Ball and Chain", at = { 79.75, 39.64 },
                note = "Click the ball and chain at Tog'thar's feet." },
            { buy = 4831, npc = 3536, only = "Rogue or Hunter or Shaman | now gold 7859",
                note = "Kris Legace, a neutral trader inside the keep, sometimes has Stalking Pants. Buy them if she does and they beat your legs; repair here too." },
            { buy = 4794, npc = 3536, only = "Rogue or Hunter or Shaman | now gold 3515",
                note = "She sometimes has Wolf Bracers too. Buy them if they beat yours." },
            { collect = 3467, quest = 498, kill = 2427, at = { { 79.60, 41.83 }, { 75.31, 41.63 } },
                note = "If the first key went on Tog'thar, kill Jailor Eston again when he is back, in front of Tog'thar or of Drull." },
            { objective = 498, part = 1, object = "Ball and Chain", at = { 75.36, 41.55 },
                note = "Click the ball and chain at Drull's feet." },
            { untrack = 549 },
            { group = {
                { objective = 549, part = 1, kill = 2260, count = 10, radius = 0.06, at = durnholde },
                { objective = 549, part = 2, kill = 2261, count = 10, radius = 0.06, at = durnholde },
                { objective = 1066, part = 1, collect = 5620, count = 5, kill = 2244, radius = 0.06, only = "quest 1066", at = durnholde },
            } },
        } },

        { section = "Hillsbrad Fields", steps = {
            { track = 501, note = "Starving Mountain Lions drop the blood. Kill any on the way west." },
            { travel = "Hillsbrad Fields", subzone = "Hillsbrad Fields", at = { 36.02, 39.19 }, radius = 0.05,
                note = "West along the road, through the creeper and bear country." },
            { track = 527, note = "Kill Hillsbrad Farmers and Farmhands as you look for the two named farmers." },
            { group = {
                { objective = 527, part = 3, kill = 232, at = { { 33.22, 34.76 }, { 33.70, 35.50 }, { 32.67, 34.80 } },
                    note = "Farmer Ray is in the vineyard, or on the first or second floor of the house." },
                { objective = 527, part = 4, kill = 2403, at = { { 35.20, 38.00 }, { 36.40, 39.40 }, { 35.20, 40.40 }, { 35.00, 38.60 } },
                    note = "Farmer Getz is in the house, the field or the barn." },
            } },
            { untrack = 527 },
            { group = {
                { objective = 527, part = 1, kill = 2266, count = 6, radius = 0.05, at = farms },
                { objective = 527, part = 2, kill = 2360, count = 6, radius = 0.05, at = farms },
            } },
            { untrack = 501 },
            { objective = 501, part = 1, collect = 3496, count = 10, kill = 2384, radius = 0.06, at = lions },
            { untrack = 496 },
            { group = {
                { objective = 496, part = 1, collect = 3476, count = 10, kill = { 2351, 2354 }, radius = 0.06, at = bears,
                    note = "Head back east towards Tarren Mill through the bear country." },
                { objective = 496, part = 2, collect = 3477, kill = { 2350, 2349 }, radius = 0.06, at = creepers },
            } },
        } },

        { section = "Tarren Mill again", steps = {
            { group = {
                { turnin = 496, accept = 499, npc = 2216 },
                { turnin = 501, accept = 502, npc = 2216 },
                { turnin = 1066, accept = 1067, npc = 2216, only = "quest 1066" },
                { turnin = 499, npc = 2230,
                    note = "Umpi is in the same building." },
                { turnin = { 527, 549 }, accept = 528, npc = 2215 },
                { turnin = 498, npc = 2229 },
                { accept = 546, npc = 2418,
                    note = "Deathguard Samsa offers it once Battle of Hillsbrad is handed in." },
            } },
            { buy = 1205, count = 20, npc = 2388, only = "Priest or Mage or Warlock or Druid or Shaman | now gold 2000" },
            { buy = 3770, count = 20, npc = 2388, only = "not Priest | not Mage | not Warlock | not Druid | now gold 2000" },
            { buy = 2515, count = 1000, npc = 2401, only = "Hunter | not now level 25 | now gold 250" },
            { buy = 3030, count = 1000, npc = 2401, only = "Hunter | now level 25 | now gold 1500" },
        } },

        { section = "Hillsbrad", steps = {
            { track = 546, note = "Every human in Hillsbrad can drop a skull. Keep killing them as you go." },
            { objective = 567, part = 2, kill = 2449,
                at = { { 32.62, 39.79 }, { 36.54, 39.44 }, { 32.58, 38.17 }, { 32.45, 42.58 }, { 30.53, 40.56 }, { 32.29, 45.13 } },
                note = "Citizen Wilkes walks the roads of the town." },
            { turnin = 502, npc = 2274,
                note = "Stanley is in the pen by the barn." },
            { kill = 2275, count = 1, at = { 32.66, 35.55 },
                note = "Stanley turns into Enraged Stanley a few seconds after drinking the elixir and attacks you. Be ready; he is worth a quest's experience." },
            { group = {
                { objective = 567, part = 4, kill = 2451, at = { 35.88, 46.57 },
                    note = "Farmer Kalaba works the field south of the town." },
                { objective = 528, part = 1, kill = 2267, count = 15, radius = 0.05, at = town },
            } },
            { group = {
                { turnin = 546, npc = 2418, only = "now quest 546 readyToTurnIn",
                    note = "Back to Tarren Mill. Hand in the skulls only if you already have thirty." },
                { turnin = 528, accept = 529, npc = 2215 },
            } },
            { buy = 1205, count = 20, npc = 2388, only = "Priest or Mage or Warlock or Druid or Shaman | now gold 2000" },
            { buy = 3770, count = 20, npc = 2388, only = "not Priest | not Mage | not Warlock | not Druid | now gold 2000" },
            { buy = 12249, npc = 3539, only = "Shaman or Warrior | now slot 16 dps < 21.09 | now gold 30343",
                note = "Look at Ott's stock again for the Merciless Axe; wear it from level 26." },
            { buy = 12247, npc = 3539, only = "Rogue | now slot 16 dps < 16.75 | now gold 28372",
                note = "Look at Ott's stock again for the Broad Bladed Knife; wear it from level 27." },
        } },

        { section = "The blacksmith", steps = {
            { group = {
                { objective = 529, part = 2, kill = 2265, count = 4, radius = 0.03,
                    at = { { 31.96, 45.83 }, { 32.69, 45.10 }, { 31.15, 43.91 }, { 31.10, 46.75 }, { 31.89, 46.72 } } },
                { objective = 529, part = 1, kill = 2404, radius = 0.02,
                    at = { { 32.11, 44.42 }, { 32.56, 45.95 }, { 32.20, 45.65 } },
                    note = "Blacksmith Verringtan works the forge in the south of the town and hits hard; pull him alone." },
                { objective = 529, part = 3, collect = 3564, object = "Shipment of Iron", at = { 32.01, 45.45 },
                    note = "The crate lies on the ground inside the smithy." },
            } },
            { untrack = 546 },
            { objective = 546, part = 1, collect = 3692, count = 30, radius = 0.05, at = town,
                kill = { 2267, 2266, 2268, 2387, 2265 },
                note = "Peasants, farmers, footmen and councilmen all drop skulls." },
            { level = 24, radius = 0.05, at = town, note = "Grind the town until you reach level 24." },
            { finish = "Hillsbrad is done for now. Battle of Hillsbrad and Souvenirs of Death are finished and wait for your return to Tarren Mill near level 30; hand them in now at Tarren Mill if you would rather not carry them. Dangerous! keeps its other two names for later. Continue with the Southern Barrens guide: hearth to Thunder Bluff." },
        } },
    },
    names = {
        npcs = {
            [232] = "Farmer Ray",
            [1937] = { "Apothecary Renferrel", at = { 42.80, 40.86, map = 1421 } },
            [2214] = { "Deathstalker Lesh", at = { 20.79, 47.40 } },
            [2215] = { "High Executor Darthalia", at = { 62.33, 20.45 } },
            [2216] = { "Apothecary Lydon", at = { 61.44, 19.06 } },
            [2226] = { "Karos Razok", at = { 45.62, 42.60, map = 1421 } },
            [2229] = { "Krusk", at = { 63.24, 20.66 } },
            [2230] = { "Umpi", at = { 61.55, 19.14 } },
            [2244] = "Syndicate Shadow Mage",
            [2260] = "Syndicate Rogue",
            [2261] = "Syndicate Watchman",
            [2265] = "Hillsbrad Apprentice Blacksmith",
            [2266] = "Hillsbrad Farmer",
            [2267] = "Hillsbrad Peasant",
            [2268] = "Hillsbrad Footman",
            [2274] = { "Stanley", at = { 32.66, 35.32 } },
            [2275] = "Enraged Stanley",
            [2349] = "Giant Moss Creeper",
            [2350] = "Forest Moss Creeper",
            [2351] = "Gray Bear",
            [2354] = "Vicious Gray Bear",
            [2360] = "Hillsbrad Farmhand",
            [2384] = "Starving Mountain Lion",
            [2387] = "Hillsbrad Councilman",
            [2388] = { "Innkeeper Shay", at = { 62.78, 19.03 } },
            [2389] = { "Zarise", at = { 60.14, 18.62 } },
            [2401] = { "Kayren Soothallow", at = { 62.56, 19.91 } },
            [2403] = "Farmer Getz",
            [2404] = "Blacksmith Verringtan",
            [2418] = { "Deathguard Samsa", at = { 62.11, 19.70 } },
            [2427] = "Jailor Eston",
            [2428] = "Jailor Marlgen",
            [2449] = "Citizen Wilkes",
            [2451] = "Farmer Kalaba",
            [3536] = { "Kris Legace", at = { 80.14, 38.89 } },
            [3539] = { "Ott", at = { 60.43, 26.18 } },
            [8385] = { "Mura Runetotem", at = { 42.91, 41.99, map = 1421 } },
        },
        quests = {
            [264] = "Until Death Do Us Part",
            [493] = "Journey to Hillsbrad Foothills",
            [494] = "Time To Strike",
            [496] = "Elixir of Suffering",
            [498] = "The Rescue",
            [499] = "Elixir of Suffering",
            [501] = "Elixir of Pain",
            [502] = "Elixir of Pain",
            [527] = "Battle of Hillsbrad",
            [528] = "Battle of Hillsbrad",
            [529] = "Battle of Hillsbrad",
            [546] = "Souvenirs of Death",
            [549] = "WANTED: Syndicate Personnel",
            [567] = "Dangerous!",
            [1065] = "Journey to Tarren Mill",
            [1066] = "Blood of Innocents",
            [1067] = "Return to Thunder Bluff",
            [1536] = "Call of Water",
            [3301] = "Mura Runetotem",
        },
        items = {
            [923] = "Longsword",
            [1205] = "Melon Juice",
            [2515] = "Sharp Arrow",
            [3030] = "Razor Arrow",
            [3467] = "Dull Iron Key",
            [3476] = "Gray Bear Tongue",
            [3477] = "Creeper Ichor",
            [3496] = "Mountain Lion Blood",
            [3499] = "Burnished Gold Key",
            [3564] = "Shipment of Iron",
            [3692] = "Hillsbrad Human Skull",
            [3770] = "Mutton Chop",
            [4794] = "Wolf Bracers",
            [4831] = "Stalking Pants",
            [5620] = "Vial of Innocent Blood",
            [7768] = "Empty Red Waterskin",
            [7771] = "Filled Red Waterskin",
            [12247] = "Broad Bladed Knife",
            [12249] = "Merciless Axe",
        },
    },
}
