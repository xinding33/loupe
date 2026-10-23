#!/usr/bin/env python3
"""Convert the community artifact-preference draft into first-pass role weights.

Reads fallumina/Genshin-Artifact-Rater `characters.js` (unlicensed) and game data
from frzyc/genshin-optimizer (MIT) at a pinned commit, then writes
`local/role-weights-draft.json` and `local/role-weights-review.md`.

Standard library only. Run with `python3 -I tools/weights/convert_draft.py`.
"""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

DRAFT_REPO = "fallumina/Genshin-Artifact-Rater"
DRAFT_PATH = "characters.js"
GO_REPO = "frzyc/genshin-optimizer"
GO_PINNED_SHA = "2ce06b88a442531b49d84cbed15204a4a03d078a"
GO_FILES = {
    "allStat_gen.json": "libs/gi/stats/src/allStat_gen.json",
    "charNames_gen.json": "libs/gi/dm-localization/assets/locales/en/charNames_gen.json",
    "artifactNames_gen.json": "libs/gi/dm-localization/assets/locales/en/artifactNames_gen.json",
    "character.ts": "libs/gi/consts/src/character.ts",
}

LEVEL = 90
ASCENSION = 6
DEFAULT_WEAPON_ATK = 608

# 5-star max substat rolls. Percent values are fractions.
MAX_ROLL = {"hp": 298.75, "atk": 19.45, "def": 23.15, "hp_": 0.0583, "atk_": 0.0583, "def_": 0.0729}
FLAT_TO_PERCENT = {"hp": "hp_", "atk": "atk_", "def": "def_"}

DRAFT_SUBSTATS = {
    "Crit Rate": "critRate_",
    "Crit DMG": "critDMG_",
    "HP%": "hp_",
    "HP": "hp",
    "ATK%": "atk_",
    "ATK": "atk",
    "DEF%": "def_",
    "DEF": "def",
    "Energy Recharge": "enerRech_",
    "Elemental Mastery": "eleMas",
}
PROFILE_KEYS = ["critRate_", "critDMG_", "hp_", "atk_", "def_", "enerRech_", "eleMas"]

ELEMENTS = ["pyro", "hydro", "electro", "cryo", "anemo", "geo", "dendro"]
SLOTS = [("flower", "flower"), ("feather", "plume"), ("sands", "sands"), ("goblet", "goblet"), ("circlet", "circlet")]
LEGAL_MAINS = {
    "flower": {"hp"},
    "plume": {"atk"},
    "sands": {"hp_", "atk_", "def_", "eleMas", "enerRech_"},
    "goblet": {"hp_", "atk_", "def_", "eleMas", "physical_dmg_", *(f"{e}_dmg_" for e in ELEMENTS)},
    "circlet": {"hp_", "atk_", "def_", "eleMas", "critRate_", "critDMG_", "heal_"},
}
MAIN_STAT_NAMES = {
    "hp": "hp", "atk": "atk", "def": "def",
    "hp%": "hp_", "atk%": "atk_", "def%": "def_",
    "elemental mastery": "eleMas", "energy recharge": "enerRech_",
    "crit rate": "critRate_", "crit dmg": "critDMG_", "healing bonus": "heal_",
}
ROLE_TYPOS = [(r"\bFeild\b", "Field"), (r"\bSheild\b", "Shield"), (r"\bVaporise\b", "Vaporize")]


# ---------------------------------------------------------------- fetching

def gh_raw(repo: str, path: str, ref: str | None = None) -> bytes:
    endpoint = f"repos/{repo}/contents/{path}" + (f"?ref={ref}" if ref else "")
    return subprocess.run(
        ["gh", "api", "-H", "Accept: application/vnd.github.raw", endpoint],
        check=True, capture_output=True,
    ).stdout


def gh_json(endpoint: str):
    out = subprocess.run(["gh", "api", endpoint], check=True, capture_output=True).stdout
    return json.loads(out)


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def load_draft(args, cache: Path) -> tuple[str, dict]:
    """Return draft text and its source record."""
    if args.draft:
        data = Path(args.draft).read_bytes()
        commit = args.draft_commit
        if commit is None and not args.offline:
            # Best effort: if the local copy matches upstream HEAD, record that commit.
            try:
                latest = gh_json(f"repos/{DRAFT_REPO}/commits?path={DRAFT_PATH}&per_page=1")[0]["sha"]
                remote = gh_json(f"repos/{DRAFT_REPO}/contents/{DRAFT_PATH}?ref={latest}")["sha"]
                if remote == git_blob_sha(data):
                    commit = latest
            except (subprocess.CalledProcessError, FileNotFoundError, IndexError, KeyError):
                pass
    else:
        commit = gh_json(f"repos/{DRAFT_REPO}/commits?path={DRAFT_PATH}&per_page=1")[0]["sha"]
        cached = cache / f"draft-{commit[:12]}" / DRAFT_PATH
        if not cached.exists() or args.refresh:
            cached.parent.mkdir(parents=True, exist_ok=True)
            cached.write_bytes(gh_raw(DRAFT_REPO, DRAFT_PATH, commit))
        data = cached.read_bytes()
    source = {
        "repo": f"https://github.com/{DRAFT_REPO}",
        "path": DRAFT_PATH,
        "commitSHA": commit,
        "blobSHA": git_blob_sha(data),
        "license": "none",
    }
    return data.decode("utf-8"), source


def load_game_data(args, cache: Path) -> dict[str, str]:
    """Return GO file contents keyed by short name, fetched at the pinned SHA and cached."""
    base = Path(args.go_dir) if args.go_dir else cache / f"genshin-optimizer-{args.go_ref[:12]}"
    out = {}
    for name, path in GO_FILES.items():
        f = base / name
        if not f.exists() or (args.refresh and not args.go_dir):
            if args.go_dir:
                sys.exit(f"missing {f}")
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(gh_raw(GO_REPO, path, args.go_ref))
        out[name] = f.read_text("utf-8")
    return out


# ---------------------------------------------------------------- parsing

JS_ESCAPES = {"'": "'", '"': '"', "\\": "\\", "/": "/", "n": "\n", "t": "\t", "r": "\r",
              "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


def decode_js_string(raw: str) -> str:
    """Decode the escapes a JS string literal may contain; reject forms this parser does not support."""
    out, i = [], 0
    while i < len(raw):
        if raw[i] != "\\":
            out.append(raw[i])
            i += 1
            continue
        e = raw[i + 1]
        n = {"u": 4, "x": 2}.get(e, 0)
        digits = raw[i + 2:i + 2 + n]
        if e in JS_ESCAPES:
            out.append(JS_ESCAPES[e])
            i += 2
        elif n and re.fullmatch(rf"[0-9A-Fa-f]{{{n}}}", digits):
            out.append(chr(int(digits, 16)))
            i += 2 + n
        else:
            raise ValueError(f"unsupported JS string escape \\{e} in {raw!r}")
    return "".join(out)


def js_array_to_json(src: str) -> list:
    """Parse the draft's JS array literal (unquoted keys, trailing commas)."""
    start = src.index("[", src.index("characters"))
    out, i, depth = [], start, 0
    while i < len(src):
        c = src[i]
        if c == '"' or c == "'":
            j = i + 1
            while src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(json.dumps(decode_js_string(src[i + 1:j])))
            i = j + 1
            continue
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_]\w*", src[i:])
            word = m.group(0)
            out.append(word if word in ("true", "false", "null") else json.dumps(word))
            i += len(word)
            continue
        if c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            # Drop a trailing comma before the closing bracket.
            k = len(out) - 1
            while k >= 0 and out[k].isspace():
                k -= 1
            if k >= 0 and out[k] == ",":
                del out[k]
        out.append(c)
        i += 1
        if depth == 0:
            break
    return json.loads("".join(out))


def parse_ts_string_array(ts: str, name: str) -> list[str]:
    body = re.search(rf"export const {name} = \[(.*?)\] as const", ts, re.S).group(1)
    return re.findall(r"'([^']+)'", body)


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def slug(s: str) -> str:
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", "-", s)
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


class Matcher:
    """Exact-then-fuzzy matching of display names to GO keys."""

    def __init__(self, names: dict[str, str], cutoff: float):
        self.by_norm = {}
        for key, display in names.items():
            self.by_norm.setdefault(norm(display), key)
            self.by_norm.setdefault(norm(key), key)
        self.cutoff = cutoff

    def match(self, name: str) -> tuple[str | None, str]:
        n = norm(name)
        if n in self.by_norm:
            return self.by_norm[n], "exact"
        close = difflib.get_close_matches(n, self.by_norm, n=1, cutoff=self.cutoff)
        if close:
            return self.by_norm[close[0]], "fuzzy"
        return None, "unmatched"


def main_stat_key(name: str) -> str | None:
    n = re.sub(r"\s+", " ", name.strip().lower())
    if n in MAIN_STAT_NAMES:
        return MAIN_STAT_NAMES[n]
    m = re.fullmatch(r"(\w+) dmg(?: bonus)?", n)
    if m and m.group(1) in ELEMENTS + ["physical"]:
        return f"{m.group(1)}_dmg_"
    return None


# ---------------------------------------------------------------- game data

def base_stats(all_stats: dict, loc_key: str) -> dict[str, float]:
    char = all_stats["char"]["data"][loc_key]
    curves = all_stats["char"]["expCurve"]
    out = {}
    for lc in char["lvlCurves"]:
        bonus = char["ascensionBonus"].get(lc["key"], [0] * (ASCENSION + 1))[ASCENSION]
        out[lc["key"]] = lc["base"] * curves[lc["curve"]][LEVEL] + bonus
    return out


# ---------------------------------------------------------------- conversion

def level_for(draft: int) -> tuple[str, float]:
    if draft >= 8:
        return "core", 1.0
    if draft >= 4:
        return "secondary", 0.5
    return "none", 0.0


def convert_substats(draft_subs: dict, base: dict, weapon_atk: float) -> dict:
    subs = {}
    for draft_name, key in DRAFT_SUBSTATS.items():
        if key in FLAT_TO_PERCENT:
            continue
        value = draft_subs.get(draft_name, 0)
        if key == "enerRech_":
            subs[key] = {"draft": value, "level": "requirement" if value > 0 else "none", "weight": 0}
        else:
            level, weight = level_for(value)
            subs[key] = {"draft": value, "level": level, "weight": weight}
    for flat, pct in FLAT_TO_PERCENT.items():
        draft_name = next(n for n, k in DRAFT_SUBSTATS.items() if k == flat)
        stat_base = base[flat] + (weapon_atk if flat == "atk" else 0)
        pct_weight = subs[pct]["weight"]
        weight = pct_weight * MAX_ROLL[flat] / (MAX_ROLL[pct] * stat_base) if pct_weight else 0
        subs[flat] = {
            "draft": draft_subs.get(draft_name, 0),
            "level": "derived" if weight else "none",
            "weight": round(weight, 4),
            "derivedFrom": {"stat": pct, "statWeight": pct_weight, "base": round(stat_base, 2)},
        }
    return {k: subs[k] for k in DRAFT_SUBSTATS.values()}


def build_roles(draft: list, go: dict, weapon_atk: float):
    all_stats = json.loads(go["allStat_gen.json"])
    char_names = json.loads(go["charNames_gen.json"])
    set_names = json.loads(go["artifactNames_gen.json"])
    non_traveler = parse_ts_string_array(go["character.ts"], "nonTravelerCharacterKeys")
    traveler_keys = parse_ts_string_array(go["character.ts"], "allTravelerKeys")

    char_matcher = Matcher({k: char_names.get(k, k) for k in non_traveler}, cutoff=0.8)
    set_matcher = Matcher(set_names, cutoff=0.8)

    roles, log = [], defaultdict(list)
    seen_ids = Counter()
    for entry in draft:
        flags = []
        draft_char = entry["character"]
        draft_role = entry["name"]
        role_name = draft_role
        for pat, rep in ROLE_TYPOS:
            role_name = re.sub(pat, rep, role_name, flags=re.I)
        role_name = role_name[0].upper() + role_name[1:]

        if norm(draft_char) == "traveler":
            ele = next((e for e in ELEMENTS if e in draft_role.lower()), None)
            key = f"Traveler{ele.capitalize()}" if ele else None
            how = "traveler" if key in traveler_keys else "unmatched"
        else:
            key, how = char_matcher.match(draft_char)
        if how == "fuzzy":
            log["charFuzzy"].append((draft_char, key))
            flags.append(f"character name corrected: {draft_char!r} -> {key}")
        if key is None:
            log["charUnmatched"].append(draft_char)
            flags.append(f"character not found in game data: {draft_char!r}")
            continue

        loc_key = "Traveler" if key.startswith("Traveler") else key
        base = base_stats(all_stats, loc_key)
        char_ele = key[len("Traveler"):].lower() if key.startswith("Traveler") else all_stats["char"]["data"][loc_key].get("ele")
        display = "Traveler" if key.startswith("Traveler") else char_names.get(key, key)

        mains = {}
        for draft_slot, slot in SLOTS:
            mains[slot] = []
            for name in entry["mainStats"].get(draft_slot, []):
                stat = main_stat_key(name)
                if stat is None:
                    flags.append(f"unknown main stat {name!r} on {slot}")
                    log["mainUnknown"].append((display, role_name, slot, name))
                    continue
                if stat not in LEGAL_MAINS[slot]:
                    flags.append(f"illegal main stat {stat} on {slot}")
                    log["mainIllegal"].append((display, role_name, slot, stat))
                if slot == "goblet" and stat.endswith("_dmg_") and stat not in ("physical_dmg_", f"{char_ele}_dmg_"):
                    flags.append(f"goblet {stat} differs from character element {char_ele}")
                    log["gobletElement"].append((display, role_name, stat, char_ele))
                if stat not in mains[slot]:
                    mains[slot].append(stat)

        sets = []
        for s in entry["sets"]:
            set_key, set_how = set_matcher.match(s["name"])
            if set_how == "fuzzy":
                log["setFuzzy"].append((s["name"], set_key))
            elif set_how == "unmatched":
                log["setUnmatched"].append((display, role_name, s["name"]))
                flags.append(f"unmatched set {s['name']!r}")
            sets.append({"setKey": set_key, "draftName": s["name"], "draftScore": s["score"]})

        subs = convert_substats(entry["substats"], base, weapon_atk)
        for flat, pct in FLAT_TO_PERCENT.items():
            fv, pv = subs[flat]["draft"], subs[pct]["draft"]
            if fv == 0:
                continue
            log["flatDraft"].append((display, role_name, flat, fv, pct, pv, subs[flat]["weight"]))
            # Same tier or higher (e.g. HP 8 vs HP% 10, both "core") overstates flat value.
            if level_for(fv)[1] >= level_for(pv)[1]:
                flags.append(f"draft flat {flat} ({fv}) rated at or above {pct} ({pv}) tier; draft value ignored")
                log["flatOverPct"].append((display, role_name, flat, fv, pct, pv, subs[flat]["weight"]))
        cr, cd = subs["critRate_"]["weight"], subs["critDMG_"]["weight"]
        if (cr > 0) != (cd > 0):
            flags.append(f"only one crit stat valued (CR {subs['critRate_']['draft']}, CD {subs['critDMG_']['draft']})")
            log["singleCrit"].append((display, role_name, subs["critRate_"]["draft"], subs["critDMG_"]["draft"]))
        if not any(v["level"] == "core" for v in subs.values()):
            flags.append("no core substats")
            log["noCore"].append((display, role_name))

        role_id = f"{slug(key)}.{slug(role_name)}"
        seen_ids[role_id] += 1
        if seen_ids[role_id] > 1:
            role_id += f"-{seen_ids[role_id]}"
            flags.append("duplicate role name for character; roleID suffixed")

        roles.append({
            "roleID": role_id,
            "characterKey": key,
            "characterName": display,
            "roleName": role_name,
            "draftCharacterName": draft_char,
            "draftRoleName": draft_role,
            "baseStats": {k: round(v, 2) for k, v in base.items()},
            "mains": mains,
            "sets": sets,
            "substats": subs,
            "flags": flags,
        })

    playable = non_traveler + traveler_keys
    return roles, log, playable, char_names


# ---------------------------------------------------------------- report

def profile_signature(role: dict) -> tuple:
    return tuple(role["substats"][k]["level"] for k in PROFILE_KEYS)


def describe_signature(sig: tuple) -> str:
    parts = defaultdict(list)
    for key, level in zip(PROFILE_KEYS, sig):
        parts[level].append(key)
    order = ["core", "secondary", "requirement"]
    return "; ".join(f"{lvl}: {', '.join(parts[lvl])}" for lvl in order if parts[lvl]) or "(nothing valued)"


def write_report(path: Path, roles: list, log: dict, playable: list, char_names: dict, meta: dict, checks: list):
    per_char = Counter(r["characterKey"] for r in roles)
    multi = sorted((k, n) for k, n in per_char.items() if n > 1)
    L = []
    w = L.append
    w("# Role weights draft: review report\n")
    w(f"Generated {meta['generatedOn']} from draft `{meta['sources']['draft']['repo']}` "
      f"(commit `{meta['sources']['draft']['commitSHA']}`, blob `{meta['sources']['draft']['blobSHA']}`, no license) "
      f"and Genshin Optimizer commit `{meta['sources']['gameData']['commitSHA']}` (MIT).\n")
    w("Local only: the draft is unlicensed, so neither this report nor the JSON may be committed.\n")

    w("## Counts\n")
    w(f"- Roles: {len(roles)}")
    w(f"- Characters (GO keys; each Traveler element counted separately): {len(per_char)}")
    w(f"- Multi-role characters: {len(multi)}: " + ", ".join(f"{k} ({n})" for k, n in multi))
    w(f"- Roles with at least one flag: {sum(1 for r in roles if r['flags'])}\n")

    w("## Base-stat check (Lv90, ascension 6)\n")
    w("| Character | Stat | Expected | Computed | OK |\n|---|---|---|---|---|")
    for c in checks:
        w(f"| {c['character']} | {c['stat']} | {c['expected']} | {c['computed']:.2f} | {'yes' if c['ok'] else 'NO'} |")
    w("")

    w("## Name matching\n")
    w("All draft characters matched to a GO key except those listed as unmatched. "
      "Traveler roles are assigned to `Traveler<Element>` from the element named in the role.\n")
    w("Corrected (fuzzy) character matches:\n")
    for d, k in sorted(set(log["charFuzzy"])) or [("none", "")]:
        w(f"- {d} -> {k}" if k else "- none")
    w("\nUnmatched characters:\n")
    for d in sorted(set(log["charUnmatched"])) or ["none"]:
        w(f"- {d}")
    w("\nCorrected (fuzzy) set names:\n")
    for d, k in sorted(set(log["setFuzzy"])) or [("none", "")]:
        w(f"- {d} -> {k}" if k else "- none")
    w("\nRole-name spelling fixes applied to `roleName` (originals kept in `draftRoleName`): "
      + ", ".join(f"{a.strip(chr(92)+'b')}->{b}" for a, b in ROLE_TYPOS) + ".\n")

    w("## Coverage gaps\n")
    covered = set(per_char)
    missing = [k for k in playable if k not in covered]
    missing_trav = [k for k in missing if k.startswith("Traveler")]
    missing_other = [k for k in missing if not k.startswith("Traveler")]
    w(f"GO playable characters with no draft role ({len(missing_other)}), in GO release order where known:\n")
    order = list(char_names)
    for k in sorted(missing_other, key=lambda k: order.index(k) if k in order else 10**6):
        w(f"- {k} ({char_names.get(k, k)})")
    w(f"\nTraveler: GO models each element as its own key; draft roles exist for "
      f"{', '.join(sorted(k for k in covered if k.startswith('Traveler')))}. "
      f"Missing: {', '.join(missing_trav) or 'none'}. Traveler base stats use GO's shared `Traveler` entry.\n")

    w("## Anomalies\n")
    w("### Flat stat rated in the same tier as (or above) its % stat\n")
    w("Draft tiers: 8-10 core, 4-6 secondary, 0-2 none. The draft number for flat HP/ATK/DEF is "
      "ignored; weights are derived from the % stat (derived weight shown).\n")
    for c, r, f, fv, p, pv, dw in log["flatOverPct"] or [(None,) * 7]:
        w(f"- {c} / {r}: {f} {fv} vs {p} {pv} -> derived {dw}" if c else "- none")
    w(f"\n### All non-zero flat stat draft values ({len(log['flatDraft'])})\n")
    w("| Character | Role | Flat | Draft | % stat | Draft | Derived weight |\n|---|---|---|---|---|---|---|")
    for c, r, f, fv, p, pv, dw in log["flatDraft"]:
        w(f"| {c} | {r} | {f} | {fv} | {p} | {pv} | {dw} |")
    w("\n### Exactly one of Crit Rate / Crit DMG valued\n")
    for c, r, cr, cd in log["singleCrit"] or [(None,) * 4]:
        w(f"- {c} / {r}: CR {cr}, CD {cd}" if c else "- none")
    w("\n### Roles with no core substats\n")
    for c, r in log["noCore"] or [(None, None)]:
        w(f"- {c} / {r}" if c else "- none")
    w("\n### Main stats illegal for the slot\n")
    for c, r, s, st in log["mainIllegal"] or [(None,) * 4]:
        w(f"- {c} / {r}: {st} on {s}" if c else "- none")
    if log["mainUnknown"]:
        w("\n### Unrecognised main stat names\n")
        for c, r, s, n in log["mainUnknown"]:
            w(f"- {c} / {r}: {n!r} on {s}")
    w("\n### Goblet element differs from character element\n")
    for c, r, st, e in log["gobletElement"] or [(None,) * 4]:
        w(f"- {c} / {r}: {st} (character is {e})" if c else "- none")
    w("\n### Unmatched sets\n")
    for c, r, n in log["setUnmatched"] or [(None,) * 3]:
        w(f"- {c} / {r}: {n!r}" if c else "- none")

    w("\n## Stat-profile groups\n")
    w("Roles grouped by identical substat levels over "
      f"{', '.join(PROFILE_KEYS)} (flat stats excluded). Largest first.\n")
    groups = defaultdict(list)
    for r in roles:
        groups[profile_signature(r)].append(r)
    ranked = sorted(groups.items(), key=lambda kv: (-len(kv[1]), describe_signature(kv[0])))
    w(f"{len(ranked)} distinct profiles across {len(roles)} roles.\n")
    for i, (sig, members) in enumerate(ranked, 1):
        w(f"### {i}. {describe_signature(sig)} ({len(members)})\n")
        w(", ".join(f"{m['characterName']} ({m['roleName']})" for m in members) + "\n")

    path.write_text("\n".join(L) + "\n", "utf-8")
    return ranked, missing_other, missing_trav


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--draft", help="local characters.js; default fetches the latest upstream commit via gh")
    ap.add_argument("--draft-commit", help="commit SHA to record for a local --draft file")
    ap.add_argument("--go-dir", help="directory with pre-fetched GO files (" + ", ".join(GO_FILES) + ")")
    ap.add_argument("--go-ref", default=GO_PINNED_SHA, help="genshin-optimizer commit to fetch (default pinned)")
    ap.add_argument("--weapon-atk", type=float, default=DEFAULT_WEAPON_ATK, help="assumed weapon base ATK")
    ap.add_argument("--refresh", action="store_true", help="re-fetch cached inputs")
    ap.add_argument("--offline", action="store_true", help="never call gh (requires --draft and --go-dir)")
    args = ap.parse_args()
    if args.offline and not (args.draft and args.go_dir):
        ap.error("--offline requires --draft and --go-dir")

    # Fixed, gitignored destination: the draft is unlicensed and its derivatives must not be committed.
    out_dir = REPO_ROOT / "local"
    cache = out_dir / "weights-cache"
    cache.mkdir(parents=True, exist_ok=True)

    draft_text, draft_source = load_draft(args, cache)
    go = load_game_data(args, cache)
    draft = js_array_to_json(draft_text)

    roles, log, playable, char_names = build_roles(draft, go, args.weapon_atk)

    all_stats = json.loads(go["allStat_gen.json"])
    checks = []
    for char, stat, expected in [("Furina", "hp", 15307), ("Neuvillette", "hp", 14695), ("RaidenShogun", "atk", 337)]:
        computed = base_stats(all_stats, char)[stat]
        checks.append({"character": char, "stat": stat, "expected": expected,
                       "computed": computed, "ok": abs(computed - expected) < 1})

    meta = {
        "schemaVersion": 1,
        "generatedOn": dt.date.today().isoformat(),
        "sources": {
            "draft": draft_source,
            "gameData": {"repo": f"https://github.com/{GO_REPO}", "commitSHA": args.go_ref, "license": "MIT",
                         "files": list(GO_FILES.values())},
        },
        "assumptions": {
            "characterLevel": LEVEL,
            "ascension": ASCENSION,
            "weaponBaseATK": args.weapon_atk,
            "maxRolls": MAX_ROLL,
            "levels": {"core": "draft >= 8, weight 1.0", "secondary": "draft 4-6, weight 0.5",
                       "none": "draft 0-2, weight 0",
                       "requirement": "Energy Recharge with draft > 0; weight 0, valued only up to a build requirement",
                       "derived": "flat HP/ATK/DEF: weight(% stat) * flatMaxRoll / (percentMaxRoll * base); "
                                  "base ATK includes weaponBaseATK"},
        },
        "baseStatChecks": checks,
        "roles": roles,
    }
    json_path = out_dir / "role-weights-draft.json"
    json_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", "utf-8")
    ranked, missing, missing_trav = write_report(out_dir / "role-weights-review.md", roles, log, playable, char_names, meta, checks)

    print(f"roles={len(roles)} characters={len({r['characterKey'] for r in roles})} profiles={len(ranked)}")
    print("base-stat checks: " + ", ".join(f"{c['character']} {c['stat']} {c['computed']:.1f} ({'ok' if c['ok'] else 'FAIL'})" for c in checks))
    print(f"coverage gaps: {len(missing)} characters, travelers missing: {missing_trav}")
    print(f"wrote {json_path} and {out_dir / 'role-weights-review.md'}")
    if not all(c["ok"] for c in checks):
        sys.exit("base-stat verification failed")


if __name__ == "__main__":
    main()
