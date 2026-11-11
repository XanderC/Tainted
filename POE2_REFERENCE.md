# Path of Exile 2 reference for Tainted's skills and supports

Source: poe2db.tw (`https://poe2db.tw/us/<Name>`), fetched 2026-11-11. 419 skill gems and 558 supports are listed there.
Numbers marked **(inferred)** are my reading of the pages, not stated on them. Pages for individual gems carry the real tables; spot-check before copying a number into game data.

URL patterns: gem page `/us/Fireball`, `/us/Chain_I` (spaces become `_`, apostrophes are dropped); indexes `/us/Skill_Gems` and `/us/Support_Gems`. `/us/Skill_Gemcutting` returns 404.

## 1. How levels work

Every skill gem levels from 1 to 20 (21 to 40 are bonus levels from items, and need character levels 115 to 629, so ignore them). **One shared curve** sets what each gem level needs, the same for every gem checked (Fireball, Cast on Critical):

| Gem level | Char level | Attribute | | Gem level | Char level | Attribute |
|---|---|---|---|---|---|---|
| 1 | 0 | 4 | | 11 | 41 | 74 |
| 2 | 3 | 9 | | 12 | 46 | 82 |
| 3 | 6 | 14 | | 13 | 52 | 92 |
| 4 | 10 | 21 | | 14 | 58 | 103 |
| 5 | 14 | 28 | | 15 | 64 | 113 |
| 6 | 18 | 35 | | 16 | 66 | 116 |
| 7 | 22 | 41 | | 17 | 72 | 126 |
| 8 | 26 | 48 | | 18 | 78 | 137 |
| 9 | 31 | 57 | | 19 | 84 | 147 |
| 10 | 36 | 65 | | 20 | 90 | 157 |

- The attribute is the gem's colour (Int for Fireball and Cast on Critical).
- A skill's **tier** (the number beside its name in the index: 1, 3, 4, 5, 7, 8, 9, 11, 13, 14) is where it first appears. Fireball is tier 3 and its page says "Minimum gem level changed from 9 to 3" (0.3.0), so a tier is the **lowest gem level that skill can be cut at (inferred)**, and the character level to use it is the curve at that level: tier 3 = character level 6, tier 14 = character level 58.
- Per level a skill's damage, mana cost and requirements grow. Fireball: 8-12 fire at level 1 to 224-336 at 20; mana 10 to 104; cast time 1.2 s, crit 7%, projectile speed 10.4 m/s.
- Quality (0-10%) gives an alternate bonus; not modelled in Tainted.

## 2. How supports work

- A support is linked to a skill gem. The index number is the support's **tier** (1-5) within its family.
- **Families:** Chain I/II/III, Multishot I/II, Pierce I/II/III, Rapid Attacks I/II/III, Rapid Casting I/II/III, Brutality I/II/III, Ignite I/II/III, Bleed I-IV, Poison I/II/III. A higher tier is a stronger version (more of the effect, with a different trade-off). "You cannot socket multiple Support Gems of the same Category in one skill."
- **Mana multiplier:** the I tier of Chain and Multishot is 100%; each support states its own.
- **Trade-off built in:** Multishot I = fires 2 additional projectiles, 35% less damage, 20% less skill speed. Chain I = chains +1 time, 30% less damage with hits (0.4.0 nerfed it from 100% more chains, 50% less damage).
- **Restricted by skill type:** a support lists allowed types (Chain: Chains, Projectile; Multishot: Projectile) and excluded types. The tags on the index (Attack, Spell, Projectile, Melee, AoE, Fire, Cold, Lightning, Chaos, Minion, Totem, Warcry...) show where each can go.
- **Meta gems** (Cast on Critical, Cast on Minion Death, Cast on Dodge, Cast on Elemental Ailment, Barrier Invocation, Elemental Invocation, Blasphemy...) are skill gems, not supports. Cast on Critical: reserves **100 Spirit**, gains **1 Energy per Power of each enemy you crit**, and when Energy is full it triggers every socketed spell and empties; maximum Energy is 10 per 0.1 s of the socketed spells' base cast time; socketed skills deal 20% less damage; its level only adds energy gained (3% per level, 0% at level 1 to 57% at 20).
- Source tags are lineage supports (named uniques-style), Occult/Bow/Mace/Elemental/Spear/Crossbow/Quarterstaff/Primal families.

## 3. Skill tiers by weapon group (index numbers)

Tier 1: the first skills of the group; 3, 4, 5: early; 7, 8, 9: mid; 11, 13, 14: late. Names only; a tag list for each is on the index page.

- **Bow:** 1 Escape Shot, Lightning Arrow, Lightning Rod, Poisonburst Arrow; 3 Freezing Salvo, Snipe, Stormcaller Arrow, Vine Arrow; 4 Plague Bearer, Wind Dancer, Herald of Thunder; 5 Electrocuting Arrow, Ice-Tipped Arrows, Toxic Growth, Barrage; 7 Gas Arrow, Sniper's Mark, Voltaic Mark, Freezing Mark; 8 Herald of Plague, Combat Frenzy, Mirage Archer; 9 Detonating Arrow, Ice Shot, Rain of Arrows; 11 Shockchain Arrow, Tornado Shot; 13 Magnetic Salvo, Spiral Volley, Toxic Domain; 14 Alchemist's Boon, Rhoa Mount.
- **Mace:** 1 Boneshatter, Earthquake, Rolling Slam; 3 Armour Breaker, Infernal Cry, Shield Charge, Shockwave Totem; 4 Iron Ward, Magma Barrier, Scavenged Plating, Herald of Ash; 5 Molten Blast, Perfect Strike, Resonating Shield; 7 Earthshatter, Leap Slam, Shield Wall, Volcanic Fissure; 8 Time of Need, Overwhelming Presence; 9 Forge Hammer, Fortifying Cry, Sunder; 11 Seismic Cry, Stampede, Supercharged Slam; 13 Ancestral Cry, Ancestral Warrior Totem, Hammer of the Gods; 14 Berserk, Dread Banner.
- **Elemental (spells):** 1 Flame Wall, Frost Bomb, Ice Nova, Spark; 3 Fireball, Frost Darts, Living Bomb, Orb of Storms; 4 Arctic Armour, Mana Remnants, Raging Spirits, Convalescence; 5 Arc, Ember Fusillade, Frostbolt, Snap; 7 Elemental Weakness, Mana Tempest, Temporal Chains; 8 Blink, Siphon Elements, Elemental Invocation, Barrier Invocation; 9 Frost Wall, Incinerate, Lightning Warp; 11 Ball Lightning, Comet, Firestorm; 13 Eye of Winter, Flameblast, Lightning Conduit; 14 Archmage, Cast on Elemental Ailment, Elemental Conflux.
- **Occult (chaos, minions, curses):** 1 Contagion, Skeletal Sniper, Unearth; 3 Bone Cage, Enfeeble, Essence Drain, Skeletal Arsonist; 4 Grim Feast, Ravenous Swarm, Withering Presence; 5 Bonestorm, Pain Offering, Raise Zombie, Skeletal Frost Mage; 7 Bind Spectre, Detonate Dead, Profane Ritual, Vulnerability; 8 Blasphemy, Cast on Minion Death, Barrier Invocation; 9 Dark Effigy, Despair, Skeletal Reaver; 11 Bone Offering, Hexblast, Skeletal Storm Mage; 13 Skeletal Brute, Skeletal Cleric, Soul Offering; 14 Cast on Critical, Sacrifice.
- **Spear:** 1 Disengage, Explosive Spear, Twister, Whirling Slash; 3 Cull The Weak, Fangs of Frost, Lightning Spear, Rake; 4 Herald of Blood; 5 Rapid Assault, Spearfield, Storm Lance; 7 Blood Hunt, Glacial Lance, Tame Beast; 8 Trail of Caltrops; 9 Bloodhound's Mark, Primal Strikes, Thunderous Leap; 11 Elemental Sundering, Whirlwind Lance; 13 Spear of Solaris, Wind Serpent's Fury; 14 Trinity.
- **Crossbow:** 1 Armour Piercing Rounds, Explosive Grenade, Fragmentation Rounds, Permafrost Bolts; 3 Flash Grenade, High Velocity Rounds, Incendiary Shot; 4 War Banner; 5 Galvanic Shards, Ice Shards, Rapid Shot, Gas Grenade; 7 Artillery Ballista, Explosive Shot, Glacial Bolt, Voltaic Grenade; 9 Oil Grenade, Siege Ballista, Stormblast Bolts; 11 Hailstorm Rounds, Shockburst Rounds, Mortar Cannon; 13 Cluster Grenade, Plasma Blast, Siege Cascade.
- **Quarterstaff:** 1 Falling Thunder, Frozen Locus, Glacial Cascade, Killing Palm; 3 Staggering Palm, Tempest Bell, Wind Blast; 5 Ice Strike, Tempest Flurry, Vaulting Impact; 7 Siphoning Strike, Storm Wave, Wave of Frost; 9 Charged Staff, Hand of Chayula; 11 Shattering Palm, Whirling Assault; 13 Flicker Strike, Gathering Storm; 14 Cast on Dodge, Reaper's Invocation.
- **Primal (shapeshift, plants, storms):** 1 Entangle, Furious Slam, Lunar Assault, Volcano; 3 Rolling Magma, Wing Blast, Pounce; 5 Thunderstorm, Fury of the Mountain; 7 Ferocious Roar, Spell Totem, Cross Slash; 9 Oil Barrage, Thrashing Vines; 11 Rampage, Tornado; 13 Walking Calamity, Flame Breath; 14 Eternal Rage, Feral Invocation, Trinity.
- **Item and character skills at tier 1:** Maul, Axe/Mace/Sword Slash, Claw/Dagger Stab, Bow Shot, Crossbow Shot, Spear Throw, Punch, Shred, Rend (Wyvern); item-granted spells Firebolt, Freezing Shards, Chaos Bolt, Consecrate, Raise Shield, Parry and the auras Discipline, Purity of Fire/Ice/Lightning, Malice.

## 4. Tainted's skills against PoE2

Tainted uses its own clusters for the gating (`SkillTree.GEM_LEVEL_REQ`): basic 1, core 3, defensive 5, brawling 8, mastery 12, ultimate 18, with attribute 10/18/24/32/42/56. PoE2's equivalent is tier then curve (see section 1).

| Tainted skill (cluster) | Nearest PoE2 gem (tier) |
|---|---|
| Cleave (basic) | Sword/Axe Slash (1); Boneshatter (1) |
| Sundering Strike (basic) | Armour Breaker (3) |
| Whirlwind (core) | Whirling Slash (1); Whirling Assault (11) |
| Double Swing (core) | Rapid Assault (5) |
| Rend (core) | Rend (1, Wyvern); Rake (3) |
| Ground Stomp (defensive) | Rolling Slam (1); Earthshatter (7) |
| Iron Skin (defensive) | Iron Ward (4); Scavenged Plating (4) |
| Threatening Shout (defensive) | Infernal Cry (3); Seismic Cry (11) |
| Ignore Pain (defensive) | Shield Wall (7); Time of Need (8) |
| Leap (brawling) | Disengage (1); Vaulting Impact (5) |
| Leap Slam (brawling) | Leap Slam (7) |
| Shield Slam (brawling) | Shield Charge (3); Resonating Shield (5) |
| Demoralizing Taunt (brawling) | Armour Breaker (3) (debuff); no exact match |
| Earthquake (mastery) | Earthquake (1); Hammer of the Gods (13) |
| Battle Cry (mastery) | Ancestral Cry (13); Fortifying Cry (9) |
| War Cry (mastery) | Fortifying Cry (9) |
| War Banner (mastery) | War Banner (4); Dread Banner (14) |
| Wrath of the Berserker (ultimate) | Berserk (14) |
| Avatar of Stone (ultimate) | Scavenged Plating (4); no exact match |
| Call of the Ancients (ultimate) | Ancestral Warrior Totem (13) |
| Frenzy (basic) | Combat Frenzy (8); Rapid Assault (5) |
| Quick Shot (basic) | Bow Shot (1) |
| Power Shot (core) | Snipe (3); Ice Shot (9) |
| Multishot (core) | Freezing Salvo (3); Magnetic Salvo (13) |
| Blade Vortex (core) | Spiral Volley (13); Whirlwind Lance (11) |
| Fan of Knives (defensive) | Poisonburst Arrow (1); no exact match |
| Shadow Step (brawling) | Disengage (1); Escape Shot (1) |
| Spear Throw (brawling) | Spear Throw (1); Lightning Spear (3) |
| Arrow Rain (mastery) | Rain of Arrows (9) |
| Death Blossom (ultimate) | Tornado Shot (11); no exact match |
| Firebolt (basic) | Firebolt (1, item skill); Fireball (3) |
| Frost Nova (core) | Ice Nova (1) |
| Arc (core) | Arc (5) |
| Arcane Ward (defensive) | Arctic Armour (4); no exact match |
| Holy Nova (brawling) | Consecrate (1); no exact match |
| Meteor (mastery) | Comet (11); Firestorm (11) |
| Thunderstorm (ultimate) | Thunderstorm (5, Primal) |
| Viper Strike (hybrid basic) | Cull The Weak (3) |
| Smite (hybrid core) | Falling Thunder (1) |

PoE2 puts Arc at tier 5 and Fireball at tier 3, where Tainted puts Arc in core (level 3). Tiers 1 to 14 are far more spread than Tainted's six clusters; if the curve is adopted, map clusters to tiers (basic 1, core 3, defensive 4, brawling 5 to 7, mastery 9 to 11, ultimate 13 to 14).

## 5. Tainted's supports against PoE2

Tainted's supports are 12 flat ones (`RuneDef.DB`), level adds +3% effect and +1% damage. In PoE2 each is a family with tiers.

| Tainted support | PoE2 equivalent | Notes |
|---|---|---|
| Glacial Support (cold conversion, chill, freeze on crit) | Cold Attunement (1), Deep Freeze (1), Freeze (2), Cold Mastery (5) | |
| Cinder Support (fire conversion, ignite) | Fire Attunement (1), Ignite I/II/III (1/3/5), Fire Mastery (5) | |
| Storm Support (lightning conversion, shock) | Lightning Attunement (1), Shock (1), Lightning Mastery (5) | |
| Venom Support (chaos conversion, poison) | Chaos Attunement (3), Poison I/II/III (1/3/5), Chaos Mastery (5) | |
| Nova Support (360 arc, +25% radius) | Nova Projectiles I/II (2/4), Spell Cascade (1) | |
| Cascade Support (echo hit) | Spell Echo (2), Aftershock I/II (2/4) | |
| Reach Support (+45% area) | Concentrated Area (1), Magnified Area I/II (1/3), Expand (5) | |
| Vampiric Support (18% leech) | Life Leech I/II/III (2/3/5), Life Drain (1) | |
| Brutality Support (+35% damage, +15% cooldown) | Brutality I/II/III (1/2/5) | |
| Alacrity Support (-30% cooldown) | Rapid Attacks I/II/III (1/4/5), Rapid Casting I/II/III (1/4/5) | |
| Execute Support (+50% crit under 35% life) | Execute I/II/III (1/4/5), Culling Strike I/II (4/5) | |
| Cast on Critical Strike | Cast on Critical (meta skill gem, 14) | uses Spirit and Energy in PoE2 |
| Cast when Damage Taken | Cast on Dodge (14), Cast on Block (unique) | no exact match |

Not in Tainted and common in PoE2: Chain, Multishot, Pierce, Fork, Ricochet, Projectile Acceleration, Controlled Destruction, Faster Casting, Penetration (Fire, Cold, Lightning) I/II, Exposure (Fire, Cold, Lightning), Heightened Accuracy, Bleed, Maim, Stun, Rage, Fist of War, Armour Break, Warcry supports, Minion supports, totem supports, curse supports.

## 6. What this means for the game

- **Level requirements:** replace the six-cluster table with the shared curve; the cluster becomes the minimum gem level (tier). Needs a decision on character level cap (the game's cap is below PoE2's 90, so the curve would need compressing or truncating to the levels the game reaches).
- **Supports:** add family tiers and skill-type restrictions (tags above), with the trade-offs the pages state (for example Multishot I = +2 projectiles, 35% less damage, 20% less skill speed).
- **Meta gems:** PoE2 uses Spirit and Energy; Tainted's version fires a chosen skill free on a timer. Keep Tainted's, document the difference.
