-- A packaged guide, in guide export format 1 (docs/examples/guide-export.lua):
-- Data/Import.lua reads it as the addon loads. Converted from the authored v2
-- guide that was Data/BuiltIn/HordeHillsbrad2224.lua.
--
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
-- Notes (from the packaged guide):
--   * The source's TBC and Wrath steps (riding trainers, Blood Elf turn-ins at
--     Silvermoon and Tarren Mill, the Druid's Trial of the Sea Lion chest) are
--     left out; Forever has none of them.
--   * The source kills Citizen Wilkes and Farmer Kalaba for Dangerous! (567)
--     without ever taking the quest; its 22-25 JJ variant takes it from the
--     poster in the Tarren Mill inn, so this guide does too. Clerk Horrace
--     Whitesteed and Miner Hackett are left for a later visit, as the source
--     leaves them.
--   * Journey to Tarren Mill, Blood of Innocents and the Shaman's Call of Water
--     were gated on being in the log instead of on class: the source gives them
--     to Shamans and Warriors because those classes took Forsaken Aid earlier,
--     and anyone who did can do them. (See the conversion notes for how that
--     gate is carried here.)
--   * The source's repeated food, drink and arrow purchases at each Tarren Mill
--     visit are one step per item per visit; a step is done once the bags hold
--     the count, so a second visit with enough left passes by.
--   * The weapon and armour purchases were gated on money only. The source also
--     compares the armour of the worn legs and bracers, which conditions cannot
--     read; the note says to buy only when it is an upgrade. The "equip"
--     reminders are notes on the purchase steps.
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
--     Legace the Stalking Pants and Wolf Bracers on Forever, and their prices.
--   * The Spring Well's position for the Filled Red Waterskin (the database's
--     object spot).
--
-- Maps: 1424 Hillsbrad Foothills (guide default), 1421 Silverpine Forest,
-- 1420 Tirisfal Glades, 1411 Durotar.
--
-- Conversion notes:
--   * Wrapper: only = "Horde" -> cond = { faction = "Horde" }; levels { 22, 24 }
--     -> { from = 22, to = 24 }; `source` written from the header comment. Same
--     id and updated timestamp.
--   * `names` -> `npcs`: NPCs with a position go under the map their `at` was
--     on (1421 for Renferrel, Karos Razok and Mura Runetotem; 1424 for the
--     rest). Quest and item names are dropped (the client names them).
--   * NPC notes: step notes that only said where a visited NPC stands moved to
--     the NPC (Renferrel, Lesh, Zarise, Lydon, Umpi, Innkeeper Shay, Ott, Kris
--     Legace, Stanley). Umpi's "in the same building" is reworded "In
--     Apothecary Lydon's building." since an NPC note stands on its own. Notes
--     that only repeated the step title ("Sharp Arrows from Kayren Soothallow")
--     are dropped. No visited NPC lacks a position.
--   * Travel areas and flight nodes: the source names subzones (The Sepulcher,
--     Durnholde Keep, Hillsbrad Fields) and flight paths (The Sepulcher, Tarren
--     Mill) by name. The travel steps leave `area` out and finish on arriving
--     at their `at`. The flight nodes are TaxiNodes 10 (The Sepulcher) and 13
--     (Tarren Mill), from db/sources/wago/forever. Zones (Tirisfal Glades,
--     Hillsbrad Foothills) became zone = 1420 / 1424.
--   * Multi-point `at` on the two long travel steps keeps the source's order
--     (target first, then the road pins), though format 1 reads a list as
--     "nearest wins".
--   * Objectives: every `objective`/`part` had its number in the source; none
--     inferred. Their counts (10, 6, 15, 4, 30, 5) are dropped, as is Enraged
--     Stanley's kill count = 1. The Ball and Chain objectives are interact
--     steps; the waterskin, vials, tongues, ichor, blood, Shipment of Iron and
--     skulls are collect steps. The jailors' keys keep quest = 498 (the whole
--     quest; count defaults to 1).
--   * track/untrack (5 pairs) -> `from` on the steps the untrack handed over
--     to. Labels: 496 from the "Durnholde Keep" section ("durnholde"), 549 from
--     the travel to Durnholde ("keep"), 501 from the "Hillsbrad Fields"
--     section ("fields"), 527 from the travel to Hillsbrad Fields ("farms"),
--     546 from the "Hillsbrad" section ("hillsbrad"); each label sits where the
--     source wrote its track. The track notes moved onto those steps (split
--     between the bears and creepers for 496; whole on the Syndicate Rogue step
--     for 549, whose Shadow Mage vial step gets no `from`, as the source
--     tracked 549 only; merged with the skull step's own note for 546).
--   * `only` class terms -> cond. The food and drink class gates are named
--     conditions in data.conds ("drinks", "eats").
--   * Dropped `now` gates: every money gate (the buys), the hunters' level 25
--     gate on Sharp vs Razor Arrows (each step's note now says which level it
--     is for, so the player skips the other), and the main-hand dps gates
--     (slot 16) on the Longsword, Merciless Axe and Broad Bladed Knife.
--   * Quest-state `only` terms, which format 1 cannot express:
--       - "quest 3301", "quest 264", "quest 1065" on turn-ins/talks of quests
--         brought from earlier guides -> optional = true (passed unless ready).
--       - "quest 1066" on the 1066 -> 1067 talk -> optional = true; on the vial
--         collect step -> dropped (a player without Blood of Innocents skips it).
--       - "Shaman | quest 1536" on the Spring Well step -> cond = SHAMAN only;
--         the in-log term is dropped (a Shaman without Call of Water skips it).
--       - "now quest 546 readyToTurnIn" on Samsa's turn-in -> optional = true,
--         which passes it unless ready, as the gate did.
--   * vendor = "repair" at Ott -> sell = true, repair = true, since the step's
--     note said to sell trash and repair; the note is dropped.
--   * Section maps: "To the Sepulcher" keeps map = 1421; no section relied on
--     a first point's map, so no map was added.

local _, ns = ...

ns.packagedGuides = ns.packagedGuides or {}
table.insert(ns.packagedGuides, {
    kind = "guide",
    format = 1,

    id = "nuuroad:leveling:horde-hillsbrad-22-24",
    updated = 1790985600,
    title = "Tarren Mill",
    category = "Leveling/Hillsbrad Foothills",
    author = "NuuRoad",
    tags = { "horde", "hillsbrad", "tarren mill", "durnholde", "sepulcher" },
    levels = { from = 22, to = 24 },
    cond = { faction = "Horde" },
    source = "Ported from the Hillsbrad half of RestedXP's Classic \"22-25 Hillsbrad / South Barrens\", checked against Questie's Forever database.",

    data = {
        map = 1424,

        conds = {
            drinks = { class = { "PRIEST", "MAGE", "WARLOCK", "DRUID", "SHAMAN" } },
            eats = { none = { { class = { "PRIEST", "MAGE", "WARLOCK", "DRUID" } } } },
        },

        sections = {
            { title = "To the Sepulcher", map = 1421, steps = {
                { type = "travel", to = "Tirisfal Glades", zone = 1420, at = { { 5083, 1372, map = 1411 } }, radius = 300,
                  note = "Take the zeppelin to the Undercity from the tower outside Orgrimmar." },
                { type = "travel", to = "The Sepulcher", radius = 400,
                  at = { { 4551, 4126 }, { 6060, 5850, map = 1420 } },
                  note = "If you have the Sepulcher flight path, fly there from the Undercity. If not, walk south from the zeppelin tower past the Undercity into Silverpine Forest and down the road." },
                { group = {
                    { type = "accept", quests = { 493 }, npc = { 1937 } },
                    { type = "turnin", quests = { 3301 }, npc = { 8385 }, optional = true },
                } },
                { type = "turnin", quests = { 264 }, object = "Yuriv's Tombstone", optional = true, at = { { 4419, 4267 } },
                  note = "The gravestone lies on the ground beside the crypt." },
                { type = "flight", node = 10, npc = { 2226 } },
            } },

            { title = "Into Hillsbrad", steps = {
                { type = "travel", to = "Hillsbrad Foothills", zone = 1424, radius = 400,
                  at = { { 2079, 4740 }, { 6147, 6747, map = 1421 }, { 6714, 7906, map = 1421 } },
                  note = "Follow the road south and east out of Silverpine. The Dalaran Wizards near the dome cast Frostbolt, which slows you; give them room." },
                { type = "accept", quests = { 494 }, npc = { 2214 } },
                { type = "flight", node = 13, npc = { 2389 } },
            } },

            { title = "Tarren Mill", steps = {
                { group = {
                    { type = "talk", turnin = { 493 }, accept = { 496, 501 }, npc = { 2216 } },
                    { type = "talk", turnin = { 1065 }, accept = { 1066 }, npc = { 2216 }, optional = true },
                    { type = "talk", turnin = { 494 }, accept = { 527 }, npc = { 2215 } },
                    { type = "accept", quests = { 549 }, object = "WANTED", at = { { 6263, 2075 } } },
                    { type = "accept", quests = { 498 }, npc = { 2229 } },
                    { type = "accept", quests = { 567 }, object = "Dangerous!", at = { { 6256, 1966 } },
                      note = "The poster hangs inside the inn." },
                } },
                { type = "collect", item = 7771, quest = { 1536, 1 }, use = { 7768 }, object = "Spring Well",
                  cond = { class = "SHAMAN" }, at = { { 6218, 2079 } },
                  note = "Use the Empty Red Waterskin at the well in the middle of the town." },
                { type = "buy", item = 1205, count = 20, npc = { 2388 }, cond = { is = "drinks" } },
                { type = "buy", item = 3770, count = 20, npc = { 2388 }, cond = { is = "eats" },
                  note = "Shamans need only about ten." },
                { type = "buy", item = 2515, count = 1000, npc = { 2401 }, cond = { class = "HUNTER" },
                  note = "Below level 25." },
                { type = "buy", item = 3030, count = 1000, npc = { 2401 }, cond = { class = "HUNTER" },
                  note = "From level 25." },
                { type = "buy", item = 923, npc = { 3539 }, cond = { class = "ROGUE" },
                  note = "Ott sells the Longsword. Equip it." },
                { type = "buy", item = 12249, npc = { 3539 }, cond = { class = { "SHAMAN", "WARRIOR" } },
                  note = "Ott sometimes has a Merciless Axe. Buy it if he does, and wear it from level 26." },
                { type = "buy", item = 12247, npc = { 3539 }, cond = { class = "ROGUE" },
                  note = "Ott sometimes has a Broad Bladed Knife. Buy it if he does, and wear it from level 27." },
                { type = "vendor", sell = true, repair = true, npc = { 3539 } },
            } },

            { title = "Durnholde Keep", label = "durnholde", steps = {
                { type = "travel", to = "Durnholde Keep", label = "keep", at = { { 7672, 4622 } }, radius = 400 },
                { type = "collect", item = 3467, quest = 498, kill = { 2427 }, at = { { 7960, 4183 } },
                  note = "Jailor Eston stands in front of Tog'thar's barracks." },
                { type = "collect", item = 3499, quest = 498, kill = { 2428 }, at = { { 7949, 4057 }, { 7799, 4019 } },
                  note = "Jailor Marlgen is in front of Tog'thar or at the bottom of the tower." },
                { type = "interact", object = "Ball and Chain", quest = { 498, 2 }, at = { { 7975, 3964 } },
                  note = "Click the ball and chain at Tog'thar's feet." },
                { type = "buy", item = 4831, npc = { 3536 }, cond = { class = { "ROGUE", "HUNTER", "SHAMAN" } },
                  note = "She sometimes has Stalking Pants. Buy them if she does and they beat your legs; repair here too." },
                { type = "buy", item = 4794, npc = { 3536 }, cond = { class = { "ROGUE", "HUNTER", "SHAMAN" } },
                  note = "She sometimes has Wolf Bracers too. Buy them if they beat yours." },
                { type = "collect", item = 3467, quest = 498, kill = { 2427 }, at = { { 7960, 4183 }, { 7531, 4163 } },
                  note = "If the first key went on Tog'thar, kill Jailor Eston again when he is back, in front of Tog'thar or of Drull." },
                { type = "interact", object = "Ball and Chain", quest = { 498, 1 }, at = { { 7536, 4155 } },
                  note = "Click the ball and chain at Drull's feet." },
                { group = {
                    { type = "kill", kill = { 2260 }, quest = { 549, 1 }, from = "keep", radius = 600,
                      at = {
                          { 7529, 4017 }, { 7653, 4100 }, { 7728, 4355 }, { 7898, 4509 }, { 8097, 4677 }, { 8224, 4250 },
                          { 8192, 3969 }, { 8383, 4078 }, { 7970, 4322 }, { 7825, 4130 }, { 7758, 3923 }, { 7647, 4662 },
                          { 6604, 4578 }, { 6487, 4717 }, { 6613, 4844 }, { 6711, 5053 },
                      },
                      note = "Kill Syndicate Rogues and Watchmen as you go." },
                    { type = "kill", kill = { 2261 }, quest = { 549, 2 }, from = "keep", radius = 600,
                      at = {
                          { 7529, 4017 }, { 7653, 4100 }, { 7728, 4355 }, { 7898, 4509 }, { 8097, 4677 }, { 8224, 4250 },
                          { 8192, 3969 }, { 8383, 4078 }, { 7970, 4322 }, { 7825, 4130 }, { 7758, 3923 }, { 7647, 4662 },
                          { 6604, 4578 }, { 6487, 4717 }, { 6613, 4844 }, { 6711, 5053 },
                      } },
                    { type = "collect", item = 5620, kill = { 2244 }, quest = { 1066, 1 }, radius = 600,
                      at = {
                          { 7529, 4017 }, { 7653, 4100 }, { 7728, 4355 }, { 7898, 4509 }, { 8097, 4677 }, { 8224, 4250 },
                          { 8192, 3969 }, { 8383, 4078 }, { 7970, 4322 }, { 7825, 4130 }, { 7758, 3923 }, { 7647, 4662 },
                          { 6604, 4578 }, { 6487, 4717 }, { 6613, 4844 }, { 6711, 5053 },
                      },
                      note = "With Blood of Innocents, the Shadow Mages drop the vials." },
                } },
            } },

            { title = "Hillsbrad Fields", label = "fields", steps = {
                { type = "travel", to = "Hillsbrad Fields", label = "farms", at = { { 3602, 3919 } }, radius = 500,
                  note = "West along the road, through the creeper and bear country." },
                { group = {
                    { type = "kill", kill = { 232 }, quest = { 527, 3 }, at = { { 3322, 3476 }, { 3370, 3550 }, { 3267, 3480 } },
                      note = "Farmer Ray is in the vineyard, or on the first or second floor of the house." },
                    { type = "kill", kill = { 2403 }, quest = { 527, 4 },
                      at = { { 3520, 3800 }, { 3640, 3940 }, { 3520, 4040 }, { 3500, 3860 } },
                      note = "Farmer Getz is in the house, the field or the barn." },
                } },
                { group = {
                    { type = "kill", kill = { 2266 }, quest = { 527, 1 }, from = "farms", radius = 500,
                      at = { { 3590, 4063 }, { 3388, 4180 }, { 3019, 3848 }, { 3067, 3521 }, { 3171, 3672 }, { 3367, 3566 } },
                      note = "Kill Hillsbrad Farmers and Farmhands as you look for the two named farmers." },
                    { type = "kill", kill = { 2360 }, quest = { 527, 2 }, from = "farms", radius = 500,
                      at = { { 3590, 4063 }, { 3388, 4180 }, { 3019, 3848 }, { 3067, 3521 }, { 3171, 3672 }, { 3367, 3566 } } },
                } },
                { type = "collect", item = 3496, kill = { 2384 }, quest = { 501, 1 }, from = "fields", radius = 600,
                  at = {
                      { 3979, 3443 }, { 3845, 3877 }, { 3797, 4459 }, { 4091, 4423 }, { 4336, 3938 }, { 5128, 3537 },
                      { 5429, 3175 }, { 5293, 2945 }, { 5477, 2872 },
                  },
                  note = "Starving Mountain Lions drop the blood. Kill any on the way west." },
                { group = {
                    { type = "collect", item = 3476, kill = { 2351, 2354 }, quest = { 496, 1 }, from = "durnholde", radius = 600,
                      at = {
                          { 4088, 3387 }, { 4085, 3942 }, { 3768, 4123 }, { 4040, 4465 }, { 4523, 3962 }, { 4975, 3433 },
                          { 5206, 3686 }, { 5239, 2927 }, { 5738, 2285 }, { 5808, 2807 }, { 5968, 3090 }, { 5989, 3674 },
                          { 6263, 3764 }, { 6652, 3452 },
                      },
                      note = "Gray Bears and Vicious Gray Bears drop the tongues; kill any on the way. Elder Gray Bears are not worth the time. Head back east towards Tarren Mill through the bear country." },
                    { type = "collect", item = 3477, kill = { 2350, 2349 }, quest = { 496, 2 }, from = "durnholde", radius = 600,
                      at = {
                          { 6285, 3874 }, { 6092, 3792 }, { 5962, 3333 }, { 5688, 2973 }, { 5763, 2416 }, { 5647, 1642 },
                          { 6054, 1367 }, { 6443, 1022 }, { 6531, 576 }, { 7039, 889 }, { 6735, 1295 }, { 7178, 2189 },
                          { 6485, 2492 }, { 6976, 3189 }, { 6762, 3765 },
                      },
                      note = "Forest Moss Creepers drop the ichor; kill any on the way." },
                } },
            } },

            { title = "Tarren Mill again", steps = {
                { group = {
                    { type = "talk", turnin = { 496 }, accept = { 499 }, npc = { 2216 } },
                    { type = "talk", turnin = { 501 }, accept = { 502 }, npc = { 2216 } },
                    { type = "talk", turnin = { 1066 }, accept = { 1067 }, npc = { 2216 }, optional = true },
                    { type = "turnin", quests = { 499 }, npc = { 2230 } },
                    { type = "talk", turnin = { 527, 549 }, accept = { 528 }, npc = { 2215 } },
                    { type = "turnin", quests = { 498 }, npc = { 2229 } },
                    { type = "accept", quests = { 546 }, npc = { 2418 },
                      note = "Deathguard Samsa offers it once Battle of Hillsbrad is handed in." },
                } },
                { type = "buy", item = 1205, count = 20, npc = { 2388 }, cond = { is = "drinks" } },
                { type = "buy", item = 3770, count = 20, npc = { 2388 }, cond = { is = "eats" } },
                { type = "buy", item = 2515, count = 1000, npc = { 2401 }, cond = { class = "HUNTER" },
                  note = "Below level 25." },
                { type = "buy", item = 3030, count = 1000, npc = { 2401 }, cond = { class = "HUNTER" },
                  note = "From level 25." },
            } },

            { title = "Hillsbrad", label = "hillsbrad", steps = {
                { type = "kill", kill = { 2449 }, quest = { 567, 2 },
                  at = { { 3262, 3979 }, { 3654, 3944 }, { 3258, 3817 }, { 3245, 4258 }, { 3053, 4056 }, { 3229, 4513 } },
                  note = "Citizen Wilkes walks the roads of the town." },
                { type = "turnin", quests = { 502 }, npc = { 2274 } },
                { type = "kill", kill = { 2275 }, at = { { 3266, 3555 } },
                  note = "Stanley turns into Enraged Stanley a few seconds after drinking the elixir and attacks you. Be ready; he is worth a quest's experience." },
                { group = {
                    { type = "kill", kill = { 2451 }, quest = { 567, 4 }, at = { { 3588, 4657 } },
                      note = "Farmer Kalaba works the field south of the town." },
                    { type = "kill", kill = { 2267 }, quest = { 528, 1 }, radius = 500,
                      at = {
                          { 3664, 4521 }, { 3603, 4440 }, { 3436, 4462 }, { 3382, 4575 }, { 3325, 4854 }, { 3459, 4813 },
                          { 3529, 4728 }, { 3649, 4749 },
                      } },
                } },
                { group = {
                    { type = "turnin", quests = { 546 }, npc = { 2418 }, optional = true,
                      note = "Back to Tarren Mill. Hand in the skulls only if you already have thirty." },
                    { type = "talk", turnin = { 528 }, accept = { 529 }, npc = { 2215 } },
                } },
                { type = "buy", item = 1205, count = 20, npc = { 2388 }, cond = { is = "drinks" } },
                { type = "buy", item = 3770, count = 20, npc = { 2388 }, cond = { is = "eats" } },
                { type = "buy", item = 12249, npc = { 3539 }, cond = { class = { "SHAMAN", "WARRIOR" } },
                  note = "Look at Ott's stock again for the Merciless Axe; wear it from level 26." },
                { type = "buy", item = 12247, npc = { 3539 }, cond = { class = "ROGUE" },
                  note = "Look at Ott's stock again for the Broad Bladed Knife; wear it from level 27." },
            } },

            { title = "The blacksmith", steps = {
                { group = {
                    { type = "kill", kill = { 2265 }, quest = { 529, 2 }, radius = 300,
                      at = { { 3196, 4583 }, { 3269, 4510 }, { 3115, 4391 }, { 3110, 4675 }, { 3189, 4672 } } },
                    { type = "kill", kill = { 2404 }, quest = { 529, 1 }, radius = 200,
                      at = { { 3211, 4442 }, { 3256, 4595 }, { 3220, 4565 } },
                      note = "Blacksmith Verringtan works the forge in the south of the town and hits hard; pull him alone." },
                    { type = "collect", item = 3564, quest = { 529, 3 }, object = "Shipment of Iron", at = { { 3201, 4545 } },
                      note = "The crate lies on the ground inside the smithy." },
                } },
                { type = "collect", item = 3692, kill = { 2267, 2266, 2268, 2387, 2265 }, quest = { 546, 1 },
                  from = "hillsbrad", radius = 500,
                  at = {
                      { 3664, 4521 }, { 3603, 4440 }, { 3436, 4462 }, { 3382, 4575 }, { 3325, 4854 }, { 3459, 4813 },
                      { 3529, 4728 }, { 3649, 4749 },
                  },
                  note = "Every human in Hillsbrad can drop a skull; keep killing them as you go. Peasants, farmers, footmen and councilmen all drop skulls." },
                { type = "level", level = 24, radius = 500,
                  at = {
                      { 3664, 4521 }, { 3603, 4440 }, { 3436, 4462 }, { 3382, 4575 }, { 3325, 4854 }, { 3459, 4813 },
                      { 3529, 4728 }, { 3649, 4749 },
                  },
                  note = "Grind the town until you reach level 24." },
                { type = "finish", note = "Hillsbrad is done for now. Battle of Hillsbrad and Souvenirs of Death are finished and wait for your return to Tarren Mill near level 30; hand them in now at Tarren Mill if you would rather not carry them. Dangerous! keeps its other two names for later. Continue with the Southern Barrens guide: hearth to Thunder Bluff." },
            } },
        },

        npcs = {
            [1421] = { -- Silverpine Forest
                [1937] = { name = "Apothecary Renferrel", at = { 4280, 4086 }, note = "Down in the crypt." },
                [2226] = { name = "Karos Razok", at = { 4562, 4260 } },
                [8385] = { name = "Mura Runetotem", at = { 4291, 4199 } },
            },
            [1424] = { -- Hillsbrad Foothills
                -- Visited.
                [2214] = { name = "Deathstalker Lesh", at = { 2079, 4740 }, note = "Waits by the road where it enters Hillsbrad." },
                [2389] = { name = "Zarise", at = { 6014, 1862 }, note = "At the north edge of Tarren Mill." },
                [2216] = { name = "Apothecary Lydon", at = { 6144, 1906 }, note = "Inside the building on the west side of the town." },
                [2230] = { name = "Umpi", at = { 6155, 1914 }, note = "In Apothecary Lydon's building." },
                [2215] = { name = "High Executor Darthalia", at = { 6233, 2045 } },
                [2229] = { name = "Krusk", at = { 6324, 2066 } },
                [2388] = { name = "Innkeeper Shay", at = { 6278, 1903 }, note = "Inside the inn." },
                [2401] = { name = "Kayren Soothallow", at = { 6256, 1991 } },
                [2418] = { name = "Deathguard Samsa", at = { 6211, 1970 } },
                [3539] = { name = "Ott", at = { 6043, 2618 }, note = "The weaponsmith south of the town." },
                [3536] = { name = "Kris Legace", at = { 8014, 3889 }, note = "A neutral trader inside the keep." },
                [2274] = { name = "Stanley", at = { 3266, 3532 }, note = "In the pen by the barn." },

                -- Kill targets: the steps that fight them say where.
                [232] = "Farmer Ray",
                [2403] = "Farmer Getz",
                [2449] = "Citizen Wilkes",
                [2451] = "Farmer Kalaba",
                [2404] = "Blacksmith Verringtan",
                [2427] = "Jailor Eston",
                [2428] = "Jailor Marlgen",
                [2244] = "Syndicate Shadow Mage",
                [2260] = "Syndicate Rogue",
                [2261] = "Syndicate Watchman",
                [2265] = "Hillsbrad Apprentice Blacksmith",
                [2266] = "Hillsbrad Farmer",
                [2267] = "Hillsbrad Peasant",
                [2268] = "Hillsbrad Footman",
                [2360] = "Hillsbrad Farmhand",
                [2387] = "Hillsbrad Councilman",
                [2349] = "Giant Moss Creeper",
                [2350] = "Forest Moss Creeper",
                [2351] = "Gray Bear",
                [2354] = "Vicious Gray Bear",
                [2384] = "Starving Mountain Lion",

                -- Brought on by a scene: Stanley turns into him after the elixir.
                [2275] = "Enraged Stanley",
            },
        },
    },
})
