"""Builds scripts/affix_data.gd from poe2db.tw's item class pages.

Each class page embeds its whole modifier table as JSON in a `ModsView({...})` call (the "normal" list:
Name, Level, ModGenerationTypeID 1 prefix / 2 suffix, ModFamilyList, str). WebFetch cannot see it, curl can:

    for p in Rings Amulets Belts ...; do curl -s -A "Mozilla/5.0" https://poe2db.tw/us/$p -o $p.html; done
    python tools/import_poe2_mods.py <folder with the .html files>

Only the families the game has a stat for are written (FAMILY below); the rest are listed in POE2_REFERENCE.md.
Every tier is [item level needed, low, high] with PoE2's own numbers: scaling to the game is AffixDB's job.
"""
import html
import io
import json
import re
import sys

# game class -> poe2db page
CLASSES = {
    "ring": "Rings", "amulet": "Amulets", "belt": "Belts",
    "helmet": "Helmets_str", "chest": "Body_Armours_str", "gloves": "Gloves_str", "boots": "Boots_str",
    "shield": "Shields_str",
    "sword1": "One_Hand_Swords", "sword2": "Two_Hand_Swords", "dagger": "Daggers", "staff": "Staves",
    "bow": "Bows", "crossbow": "Crossbows",
    "flask_life": "Life_Flasks", "flask_mana": "Mana_Flasks", "charm": "Charms",
}

# The dex and int pages of an armour slot hold the evasion and energy shield modifiers: merged into the same class
EXTRA_PAGES = {
    "helmet": ["Helmets_dex", "Helmets_int"], "chest": ["Body_Armours_dex", "Body_Armours_int"],
    "gloves": ["Gloves_dex", "Gloves_int"], "boots": ["Boots_dex", "Boots_int"],
}

# poe2db family -> game family id. A family that reads "increased" rather than "+" gets a second id (see ALT).
FAMILY = {
    "IncreasedLife": "life", "IncreasedMana": "mana",
    "MaximumLifeIncreasePercent": "life_pct", "MaximumManaIncreasePercent": "mana_pct",
    "BaseLocalDefences": "armour", "IncreasedPhysicalDamageReductionRating": "armour",
    "DefencesPercent": "armour_pct", "IncreasedPhysicalDamageReductionRatingPercent": "armour_pct",
    "PhysicalDamage": "phys_add", "FireDamage": "fire_add", "ColdDamage": "cold_add", "LightningDamage": "lightning_add",
    "LocalPhysicalDamagePercent": "phys_pct",
    "IncreasedWeaponElementalDamagePercent": "elem_pct",
    "FireDamagePercentage": "fire_pct", "ColdDamagePercentage": "cold_pct", "LightningDamagePercentage": "lightning_pct",
    "IncreasedChaosDamage": "chaos_pct",
    "SpellDamage": "spell_dmg", "WeaponCasterDamagePrefix": "spell_dmg",
    "MovementVelocity": "move_speed",
    "Strength": "str", "Dexterity": "dex", "Intelligence": "ene", "AllAttributes": "all_attr",
    "FireResistance": "res_fire", "ColdResistance": "res_cold", "LightningResistance": "res_lightning",
    "ChaosResistance": "res_chaos", "AllResistances": "res_all",
    "IncreasedAttackSpeed": "attack_speed", "IncreasedCastSpeed": "cast_speed",
    "CriticalStrikeChanceIncrease": "crit_chance", "CriticalStrikeMultiplier": "crit_damage",
    "LifeRegeneration": "life_regen", "ManaRegeneration": "mana_regen",
    "LifeGainedFromEnemyDeath": "life_kill", "ManaGainedFromEnemyDeath": "mana_kill",
    "LifeLeech": "life_leech", "ManaLeech": "mana_leech", "LifeGainPerTarget": "life_hit",
    "IncreasedEvasionRating": "evasion", "EvasionRatingPercent": "evasion_pct",
    "IncreasedEnergyShield": "es", "EnergyShieldPercent": "es_pct",
    "StunThreshold": "stun_threshold", "Thorns": "thorns", "ReducedAilmentDuration": "ail_",
    "IncreasedAccuracy": "accuracy", "BaseSpirit": "spirit", "IncreaseSocketedGemLevel": "lvl_",
    "BaseLocalDefencesAndLife": "hyb", "BaseLocalDefencesAndMana": "hyb", "BaseLocalDefencesAndDefencePercent": "hyb",
    "DefencesPercentAndStunThreshold": "hyb", "SpellDamageAndMana": "hyb",
    "LocalIncreasedPhysicalDamagePercentAndAccuracyRating": "hyb",
    "ItemFoundRarityIncreasePrefix": "rarity_prefix", "ItemFoundRarityIncrease": "rarity",
    "IncreasedShieldBlockPercentage": "block", "ArmourAppliesToElementalDamage": "armour_ele",
    "MaximumFireResist": "max_fire", "MaximumColdResist": "max_cold", "MaximumLightningResistance": "max_lightning",
    "MaximumChaosResistance": "max_chaos", "MaximumResistances": "max_res",
    "DamageTakenGainedAsLife": "recoup_life", "PercentDamageGoesToMana": "recoup_mana",
    # Flasks and charms (used from the flask and charm phases)
    "FlaskRecoveryAmount": "flask_amount", "FlaskRecoverySpeed": "flask_speed",
    "FlaskChargesUsed": "flask_used", "FlaskGainCharge": "flask_per_second",
    "FlaskNumCharges": "flask_charges", "FlaskRechargeRate": "flask_gained",
    "BeltFlaskRecoveryRate": "belt_flask_recovery", "BeltCharmDuration": "belt_charm_duration",
    "BeltCharmChargesGained": "belt_charm_gained", "BeltCharmChargesUsed": "belt_charm_used",
    "BeltFlaskChargesGained": "belt_flask_gained", "BeltFlaskChargesUsed": "belt_flask_used",
}
# A flask or charm family mixes several mods; keep the ones the game has, by what the line says
FLASK_TEXT = {
    "flask_amount": "increased Amount Recovered", "flask_speed": "increased Recovery rate",
    "flask_gained": "increased Charges gained", "flask_charges": "increased Charges",
    "flask_used": "reduced Charges per use", "flask_per_second": "Charges per Second",
}
# "+x% to Critical Hit Chance" (weapons) and "x% increased Critical Hit Chance" (jewellery) are different mods
ALT = {"crit_chance": "crit_chance_inc"}


def values(raw: str):
    """The (low, high) of each number span in a modifier line."""
    out = []
    for span in re.findall(r"<span class='mod-value'>((?:[^<]|<span[^>]*>[^<]*</span>)*)</span>", raw):
        text = html.unescape(re.sub(r"<[^>]+>", "", span.replace("—", "-")))
        m = re.search(r"(\d+(?:\.\d+)?)(?:\s*-\s*(\d+(?:\.\d+)?))?", text)
        if m:
            lo = float(m.group(1))
            out.append((lo, float(m.group(2)) if m.group(2) else lo))
    return out


def tier_row(m, hybrid=False):
    vs = values(m["str"])
    if not vs:
        return None
    if hybrid:
        if len(vs) < 2:
            return None
        return [int(m["Level"]), round(vs[0][0], 3), round(vs[0][1], 3), round(vs[1][0], 3), round(vs[1][1], 3)]
    if len(vs) >= 2 and re.search(r"Adds|Gain|Thorns", html.unescape(re.sub(r"<[^>]+>", "", m["str"])), re.I):
        lo = (vs[0][0] + vs[1][0]) / 2.0  # "Adds (1-2) to (3-5)": the average hit, low and high roll
        hi = (vs[0][1] + vs[1][1]) / 2.0
    else:
        lo, hi = vs[0]
    return [int(m["Level"]), round(lo, 3), round(hi, 3)]


def main(folder: str, out: str) -> None:
    data = {}
    for cls, page in CLASSES.items():
        fams = {}
        pages = [page] + EXTRA_PAGES.get(cls, [])
        rows = []
        for pg in pages:
            s = io.open(f"{folder}/{pg}.html", encoding="utf-8").read()
            i = s.index("ModsView({") + len("ModsView(")
            d, _ = json.JSONDecoder().raw_decode(s[i:])
            rows += [(pg, m) for m in d["normal"]]
        have = set()
        for pg, m in rows:
            fam = "/".join(m["ModFamilyList"])
            if fam not in FAMILY:
                continue
            text = html.unescape(re.sub(r"<[^>]+>", "", m["str"]))
            fid = FAMILY[fam]
            if fid in ALT and "increased" in text:
                fid = ALT[fid]
            if fam in ("BaseLocalDefences", "DefencesPercent"):
                flat = fam == "BaseLocalDefences"
                if "Evasion" in text:
                    fid = "evasion" if flat else "evasion_pct"
                elif "Energy Shield" in text:
                    fid = "es" if flat else "es_pct"
                else:
                    fid = "armour" if flat else "armour_pct"
            if fam == "IncreaseSocketedGemLevel":
                kinds = [("Melee Skills", "lvl_melee"), ("Projectile Skills", "lvl_projectile"), ("Fire Spell", "lvl_fire"),
                         ("Cold Spell", "lvl_cold"), ("Lightning Spell", "lvl_lightning"), ("Chaos Spell", "lvl_chaos"),
                         ("Physical Spell", "lvl_phys_spell"), ("all Spell Skills", "lvl_spell")]
                fid = next((v for k, v in kinds if k in text), None)
                if fid is None:
                    continue  # Minion skills: the game has no such gems
            if FAMILY[fam] == "hyb":
                kind = "evasion" if "Evasion" in text else ("es" if "Energy Shield" in text else "armour")
                fid = {"BaseLocalDefencesAndLife": f"{kind}_pct_life", "BaseLocalDefencesAndMana": f"{kind}_pct_mana",
                       "BaseLocalDefencesAndDefencePercent": f"{kind}_flat_pct", "DefencesPercentAndStunThreshold": f"{kind}_pct_stun",
                       "SpellDamageAndMana": "spell_mana", "LocalIncreasedPhysicalDamagePercentAndAccuracyRating": "phys_acc"}[fam]
            if fam == "ReducedAilmentDuration":
                kinds = {"Bleeding": "ail_bleed", "Poison": "ail_poison", "Ignite": "ail_ignite", "Shock": "ail_shock", "Freeze": "ail_freeze"}
                fid = next((v for k, v in kinds.items() if k in text), None)
                if fid is None:
                    continue  # Chill: the game has no chill
            if fid == "spell_dmg" and fam == "WeaponCasterDamagePrefix" and "Spell Damage" not in text:
                continue
            if cls == "charm" and fam == "FlaskRecoveryAmount":
                if "Life when Used" in text:
                    fid = "charm_life"
                elif "Mana when Used" in text:
                    fid = "charm_mana"
                else:
                    continue  # "Also grants Guard": the game has no Guard
            elif cls == "charm" and fam == "FlaskRecoverySpeed":
                if "increased Duration" not in text:
                    continue
                fid = "charm_duration"
            if fid in FLASK_TEXT:
                if fid == "flask_speed" and "applied Instantly" in text:
                    fid = "flask_instant_part"
                elif FLASK_TEXT[fid] not in text or "more Recovery" in text:
                    continue
            if fid == "belt_flask_recovery" and "Life Recovery" not in text:
                continue  # the belt's mana line is the same mod for the other flask
            row = tier_row(m, FAMILY[fam] == "hyb")
            if row is None:
                continue
            if pg != page and fid in have and fid not in fams:
                continue
            if pg == page:
                have.add(fid)
            elif fid in have:
                continue  # the main page's version of a family wins
            fams.setdefault(fid, {})[row[0]] = row  # one row per item level
        # Vitality has no PoE2 counterpart: it takes the tiers of the first attribute the class has
        for src in ("str", "dex", "ene"):
            if src in fams and "vit" not in fams:
                fams["vit"] = fams[src]
        data[cls] = {f: [fams[f][k] for k in sorted(fams[f])] for f in sorted(fams)}

    def fmt(v):
        return ("%g" % v)

    lines = ["# Generated by tools/import_poe2_mods.py from poe2db.tw: do not edit by hand.",
             "# MODS[class][family] = tiers, lowest first, each [item level needed, low, high] as PoE2 prints them.",
             "class_name AffixData", "", "const MODS := {"]
    for cls, fams in data.items():
        lines.append('\t"%s": {' % cls)
        for f, tiers in fams.items():
            rows = ", ".join("[" + ", ".join([str(t[0])] + [fmt(v) for v in t[1:]]) + "]" for t in tiers)
            lines.append('\t\t"%s": [%s],' % (f, rows))
        lines.append("\t},")
    lines.append("}")
    with io.open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", out, {c: len(f) for c, f in data.items()})


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "scripts/affix_data.gd")
