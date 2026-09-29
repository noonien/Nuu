# Fixed bug reports

Bug reports filed in the game (MENU -> Report a bug) that have been dealt
with. `sessions.py --bugs` leaves out every report listed here, so each one is
read once; `--bugs --all` shows them again.

One line a report: the session and the time from the report's `==` header, in
backticks, then what was wrong and what fixed it. Add the line in the same
change as the fix.

- `20260924-150135 15:41:31` Arrow and map pins, "arrow not showing" on Bruised Pride and Lion Hides objective 1 (95494): the step had no coordinates. Fixed in 53adc45, the step pinned to the client's own quest marker.
- `20260924-170144 17:13:50` Travel route, flight not used until the taxi map was opened, and the route dropped to walking once in the air. Fixed in 895928f, the flight route kept while flying.
- `20260924-173001 18:04:18` Wailing Caverns, finished Deviate Viper and Shambler kills (1487 parts 2 and 3) still on the carried card. Sticky steps left the card only on a recorded status, which the flow never records for them; `Progress:Carried` now drops a sticky step once the game shows its work done.
- `20260924-182053 19:39:24` Wailing Caverns, "turned the quests out of order, but the guide didn't skip past the completed step": the travel before Falla Sagewind was never passed, because a turn-in-and-accept step's `all` rule did not count as proof of the visit, and turn-ins handed in early (gated out by `readyToTurnIn`) were not looked at. Fixed in `ObservedProgress:PassedTo`; step moves now go on the `guide` channel of the session log.
- `20260926-145511 15:03:56` Skyborne, "i'm not a hunter, why does this step show up": the Hunter trainer visit (`only = "Hunter | level 4 | gold 200"`) showed for a level 4 Warrior. The `only` parser OR-ed every positive term across `|`, so level 4 alone opened it. `|` now joins groups that must all hold (`Data/Steps.lua`), and the port's RestedXP-style gates are `now` terms, passed over when they do not hold rather than waited on.
- `20260926-145511 15:04:38` Skyborne, "im not a druid": the Druid trainer visit, same cause and fix as the report above.
- `20260926-145511 15:05:39` Tracker, "this bug reporter shows step 61 but the step guide shows step 46, we should not reindex steps": the tracker numbered only this character's steps. The counter, the list, the jump box and the bar tooltip now show the guide's own step number.
- `20260926-163726 16:56:51` Skyborne, "i trained cooking and the step did not advance": the Forever client lists no professions among its skill lines, so the `train = "Cooking"` step never saw the rank. Fixed in af163fa, `Client:GetSkillRank` reads `GetProfessions` too.
- `20260926-153127 15:44:17` Skyborne, "guide did not automatically continue after i trained parry": class training was a note, which nothing in the game completes. New `learn` verb (spell IDs, done once `IsPlayerSpell` knows them all); every named class-trainer visit in the Skyborne guide uses it. Not yet seen in the client.
- `20260926-163726 16:56:32` Tracker, "did not complete/advance, it's a note, add a 'press here when done' text ... and highlight the skip button": the step was a vendor visit, and only notes lit SKIP. Every step with no completion rule now lights SKIP and ends its card with a DONE - NEXT STEP button that records it done.
- `20260926-163726 16:57:42` Step list, "quest icon shows as green in the step viewer, but i've not accepted yet": the current row tinted the game's yellow quest art with the cyan accent, which multiplies to the green of a finished step. The current row's icon keeps its own colours now.
- `20260926-205948 21:12:34` Skyborne, "skysight cast not detected": the Skysight and Read Ley Line steps were notes. New `cast` verb, counted from `UNIT_SPELLCAST_SUCCEEDED` while on the step; those steps use it. Not yet seen in the client.
