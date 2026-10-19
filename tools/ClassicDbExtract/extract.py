"""Builds ForeverPath's classic-era database from CMaNGOS classic-db.

Reads the classic-db repository (Full_DB dump + Updates, applied in the
order InstallFullDB.sh uses) into SQLite, then writes compact Lua tables
into the ForeverPath_ClassicDB addon:

  Quests.lua   quests: title, levels, side, classes, givers, turn-ins,
               prerequisites, follow-ups, items and kills required, rewards,
               reputation, objective text
  Loot.lua     where items drop: creatures (with chances), world drops,
               skinning, pickpocketing, gathering nodes and chests, fishing
               zones, containers
  Vendors.lua  which NPCs sell an item and for how much
  Trainers.lua which trainers teach a profession recipe, cost and skill
  Npcs.lua     NPCs all of the above use, with spawn points on zone maps,
               level, rank and which faction they are friendly to
  Objects.lua  game objects (quest objects, herb / ore nodes, chests) with
               spawn points and the skill that opens them
  Maps.lua     zone map, instance and area names

World positions are placed on the client's zone maps with the bounds
tools/DbExtract writes to maps.json (UiMapAssignment from the Forever client).

Run through scripts/extract_classicdb.ps1, which fetches the pinned
classic-db snapshot first. The data is GPL-3.0 (classic-db's LICENSE.md
ships with the addon) and contains Blizzard content used non-commercially
(classic-db's COPYRIGHT.md).
"""
import argparse
import glob
import json
import math
import os
import re
import sqlite3
import sys
import time

# ---------------------------------------------------------------------------
# MySQL dump -> SQLite
# ---------------------------------------------------------------------------
TOKEN = re.compile(r"""('(?:[^'\\]|\\.|'')*')|("(?:[^"\\]|\\.)*")|(`[^`]*`)|(--[ \t][^\n]*|--\n|\#[^\n]*)|(/\*.*?\*/)|(;)""", re.S)
ESCAPES = {"0": "\0", "b": "\b", "n": "\n", "r": "\r", "t": "\t", "Z": "\x1a"}


def unescape(body):
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            out.append(ESCAPES.get(n, n))
            i += 2
        elif c == "'" and body[i:i + 2] == "''":
            out.append("'")
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def sqlite_string(raw):
    text = unescape(raw[1:-1])
    return "'" + text.replace("'", "''") + "'"


def statements(text):
    """Yields statements as lists of (is_string, chunk) pieces."""
    pieces = []
    pos = 0
    for m in TOKEN.finditer(text):
        if m.start() > pos:
            pieces.append((False, text[pos:m.start()]))
        pos = m.end()
        single, double, back, line, block, semi = m.groups()
        if single is not None:
            pieces.append((True, sqlite_string(single)))
        elif double is not None:
            pieces.append((True, sqlite_string(double)))
        elif back is not None:
            pieces.append((False, '"' + back[1:-1] + '"'))
        elif line is not None or block is not None:
            pieces.append((False, " "))
        else:
            if any(not s and chunk.strip() for s, chunk in pieces) or any(s for s, _ in pieces):
                yield pieces
            pieces = []
    if pieces and any(chunk.strip() for _, chunk in pieces):
        yield pieces


VAR = re.compile(r"@(\w+)")
SET_VAR = re.compile(r"^\s*SET\s+(@\w+\s*:?=.*)$", re.I | re.S)


def split_top(text, sep=","):
    parts, depth, cur = [], 0, []
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


class Loader:
    def __init__(self, db):
        self.db = db
        self.vars = {}
        self.stats = {"ok": 0, "failed": 0, "skipped": 0}
        self.failures = []
        self.failureKinds = {}
        self.columns = {}

    def literal(self, value):
        if value is None:
            return "NULL"
        if isinstance(value, (int, float)):
            return repr(value)
        return "'" + str(value).replace("'", "''") + "'"

    def render(self, pieces, substitute=True):
        out = []
        for is_string, chunk in pieces:
            if not is_string:
                if substitute and "@" in chunk and self.vars:
                    chunk = VAR.sub(lambda m: self.literal(self.vars[m.group(1).lower()]) if m.group(1).lower() in self.vars else m.group(0), chunk)
                # MySQL's && and || are AND and OR.
                chunk = chunk.replace("&&", " AND ").replace("||", " OR ")
            out.append(chunk)
        return "".join(out).strip()

    def create_table(self, sql):
        m = re.match(r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(\w+)"?\s*\((.*)\)[^)]*$', sql, re.I | re.S)
        if not m:
            raise ValueError("unparsed CREATE TABLE")
        name, body = m.group(1), m.group(2)
        cols, keys = [], []
        for part in split_top(body):
            part = part.strip()
            if not part:
                continue
            upper = part.upper()
            if part.startswith('"'):
                col = part[1:part.index('"', 1)]
                d = re.search(r"\bDEFAULT\s+('(?:[^']|'')*'|-?[\d.]+|NULL|CURRENT_TIMESTAMP)", part, re.I)
                default = d.group(1) if d else None
                if default and default.upper() == "CURRENT_TIMESTAMP":
                    default = None
                cols.append('"%s"%s' % (col, (" DEFAULT " + default) if default else ""))
            elif upper.startswith("PRIMARY KEY"):
                keys.append("PRIMARY KEY " + part[part.index("("):].split(")")[0] + ")")
            elif upper.startswith("UNIQUE"):
                keys.append("UNIQUE " + part[part.index("("):].split(")")[0] + ")")
        keys = [re.sub(r"\(\d+\)", "", k) for k in keys]
        self.db.execute('DROP TABLE IF EXISTS "%s"' % name)
        self.db.execute('CREATE TABLE "%s" (%s)' % (name, ", ".join(cols + keys)))
        self.columns[name] = [c.split('"')[1] for c in cols]

    def set_vars(self, body):
        for assignment in split_top(body):
            m = re.match(r"\s*@(\w+)\s*:?=\s*(.*)$", assignment, re.S)
            if not m:
                continue
            expr = VAR.sub(lambda v: self.literal(self.vars.get(v.group(1).lower())), m.group(2))
            try:
                self.vars[m.group(1).lower()] = self.db.execute("SELECT " + expr).fetchone()[0]
            except sqlite3.Error:
                self.vars[m.group(1).lower()] = None

    def alter_table(self, sql):
        """ALTER TABLE t ADD [COLUMN] c ... (other alterations change nothing we read)."""
        m = re.match(r'ALTER\s+TABLE\s+"?(\w+)"?\s+(.*)$', sql, re.I | re.S)
        if not m:
            return False
        table, body = m.group(1), m.group(2)
        added = False
        for part in split_top(body):
            a = re.match(r'\s*ADD\s+(?:COLUMN\s+)?"?(\w+)"?(.*)$', part, re.I | re.S)
            if not a or a.group(1).upper() in ("PRIMARY", "INDEX", "KEY", "UNIQUE", "CONSTRAINT"):
                continue
            d = re.search(r"\bDEFAULT\s+('(?:[^']|'')*'|-?[\d.]+|NULL)", a.group(2), re.I)
            try:
                self.db.execute('ALTER TABLE "%s" ADD COLUMN "%s"%s' % (table, a.group(1), (" DEFAULT " + d.group(1)) if d else ""))
                added = True
            except sqlite3.Error:
                pass
        return added

    def run(self, pieces, origin):
        raw = self.render(pieces, substitute=False)
        if not raw:
            return
        # Variable assignments take the new value: render them unsubstituted.
        sql = raw if re.match(r"\s*SET\s+@", raw, re.I) else self.render(pieces)
        head = sql[:40].upper()
        try:
            if head.startswith("CREATE TABLE"):
                self.create_table(sql)
            elif head.startswith("SET "):
                m = SET_VAR.match(sql)
                if m:
                    self.set_vars(m.group(1))
                else:
                    self.stats["skipped"] += 1
                    return
            elif head.startswith("ALTER TABLE"):
                if not self.alter_table(sql):
                    self.stats["skipped"] += 1
                    return
            elif re.match(r"(LOCK|UNLOCK|START|COMMIT|BEGIN|ROLLBACK|ALTER|CREATE\s+(INDEX|UNIQUE|PROCEDURE|FUNCTION|TRIGGER|VIEW|DATABASE)|USE|DROP\s+(PROCEDURE|FUNCTION|TRIGGER|INDEX|VIEW)|DELIMITER|CALL|OPTIMIZE|ANALYZE|FLUSH|SELECT)\b", head):
                self.stats["skipped"] += 1
                return
            else:
                if head.startswith("TRUNCATE"):
                    sql = re.sub(r"^TRUNCATE\s+(TABLE\s+)?", "DELETE FROM ", sql, flags=re.I)
                sql = re.sub(r"^INSERT\s+IGNORE\b", "INSERT OR IGNORE", sql, flags=re.I)
                self.db.execute(sql)
            self.stats["ok"] += 1
        except (sqlite3.Error, ValueError) as e:
            self.stats["failed"] += 1
            kind = re.sub(r"\d+", "N", str(e))[:60]
            self.failureKinds[kind] = self.failureKinds.get(kind, 0) + 1
            if self.failureKinds[kind] <= 3:
                self.failures.append("%s: %s: %s" % (origin, e, sql[:140].replace("\n", " ")))

    def load_file(self, path):
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        name = os.path.basename(path)
        for pieces in statements(text):
            self.run(pieces, name)


def load_database(src, sqlite_path):
    dumps = glob.glob(os.path.join(src, "Full_DB", "*.sql.gz")) + glob.glob(os.path.join(src, "Full_DB", "*.sql"))
    if not dumps:
        sys.exit("No Full_DB dump under " + src)
    if os.path.exists(sqlite_path):
        os.remove(sqlite_path)
    db = sqlite3.connect(sqlite_path, isolation_level=None)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    loader = Loader(db)
    db.execute("BEGIN")
    dump = sorted(dumps)[0]
    t0 = time.time()
    if dump.endswith(".gz"):
        import gzip
        with gzip.open(dump, "rt", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for pieces in statements(text):
            loader.run(pieces, os.path.basename(dump))
    else:
        loader.load_file(dump)
    base = dict(loader.stats)
    print("  dump %s: %d statements (%d failed, %d skipped) in %.0fs" % (os.path.basename(dump), base["ok"], base["failed"], base["skipped"], time.time() - t0))
    updates = sorted(glob.glob(os.path.join(src, "Updates", "[0-9]*.sql"))) + sorted(glob.glob(os.path.join(src, "Updates", "Instances", "[0-9]*.sql")))
    for path in updates:
        loader.load_file(path)
    db.execute("COMMIT")
    stats = {k: loader.stats[k] - base[k] for k in loader.stats}
    print("  %d update files: %d statements (%d failed, %d skipped)" % (len(updates), stats["ok"], stats["failed"], stats["skipped"]))
    kinds = sorted(loader.failureKinds.items(), key=lambda kv: -kv[1])
    for kind, n in kinds[:12]:
        print("    %5d x %s" % (n, kind))
    return db, {"dump": os.path.basename(dump), "updates": len(updates), "base": base, "updatesApplied": stats, "failureKinds": dict(kinds), "failures": loader.failures}


# ---------------------------------------------------------------------------
# World position -> zone map
# ---------------------------------------------------------------------------
class MapPlacer:
    def __init__(self, maps):
        self.uiMaps = {m["id"]: m for m in maps["uiMaps"]}
        self.byMap = {}
        for a in maps["assignments"]:
            ui = self.uiMaps.get(a["uiMapID"])
            # Zone maps (type 3) and battleground maps (6); continents only as a fallback.
            if not ui or ui["type"] not in (2, 3, 6):
                continue
            r = a["region"]
            if len(r) < 6:
                continue
            self.byMap.setdefault(a["mapID"], []).append((ui["type"] != 2, a, r))
        self.instances = {m["id"]: m for m in maps["maps"]}

    def place(self, mapID, x, y):
        """-> (uiMapID, x 0-1, y 0-1) or (-mapID, None, None) for instances, None when nowhere."""
        best = None
        for is_zone, a, r in self.byMap.get(mapID, []):
            minX, minY, maxX, maxY = r[0], r[1], r[3], r[4]
            if minX <= x <= maxX and minY <= y <= maxY:
                area = (maxX - minX) * (maxY - minY)
                key = (0 if is_zone else 1, area)
                if best is None or key < best[0]:
                    best = (key, a, r)
        if best:
            _, a, r = best
            minX, minY, maxX, maxY = r[0], r[1], r[3], r[4]
            u = (maxY - y) / (maxY - minY)
            v = (maxX - x) / (maxX - minX)
            ux = a["uiMin"][0] + u * (a["uiMax"][0] - a["uiMin"][0])
            uy = a["uiMin"][1] + v * (a["uiMax"][1] - a["uiMin"][1])
            return a["uiMapID"], ux, uy
        if mapID in self.instances and mapID not in (0, 1):
            return -mapID, None, None
        return None


MAX_POINTS = 10


def compact_spawns(points):
    """points: [(uiMapID, x, y)] -> flat [uiMapID, x*1000, y*1000, ...], clustered on a 2% grid."""
    cells = {}
    order = []
    for ui, x, y in points:
        if x is None:
            key = (ui, None, None)
        else:
            key = (ui, int(x * 50), int(y * 50))
        cell = cells.get(key)
        if not cell:
            cell = cells[key] = [ui, 0.0, 0.0, 0]
            order.append(key)
        if x is not None:
            cell[1] += x
            cell[2] += y
        cell[3] += 1
    chosen = sorted(order, key=lambda k: -cells[k][3])[:MAX_POINTS]
    chosen.sort(key=lambda k: order.index(k))
    flat = []
    for key in chosen:
        ui, sx, sy, n = cells[key]
        if key[1] is None:
            flat += [ui, 0, 0]
        else:
            flat += [ui, int(round(sx / n * 1000)), int(round(sy / n * 1000))]
    return flat


# ---------------------------------------------------------------------------
# Loot
# ---------------------------------------------------------------------------
TOP_SOURCES = 5
MIN_CHANCE = 0.01          # percent; rarer drops are not listed
WORLD_REF_USERS = 25       # a reference table this many loot tables share is a world drop


def loot_table(db, table):
    t = {}
    for r in rows(db, 'SELECT entry, item, ChanceOrQuestChance AS chance, groupid, mincountOrRef AS ref, maxcount FROM "%s"' % table):
        t.setdefault(int(r["entry"]), []).append(r)
    return t


class LootResolver:
    """Flattens loot entries into {itemID: (chance percent, quest)} per loot id,
    expanding references; references shared by many tables are world drops."""

    def __init__(self, refs, world_refs):
        self.refs = refs
        self.world_refs = world_refs
        self.ref_cache = {}

    def expand(self, entries, depth=0, world=None):
        out = {}
        groups = {}

        def add(item, chance, quest):
            prev = out.get(item)
            if prev is None or chance > prev[0]:
                out[item] = (min(100.0, chance), quest)

        for r in entries:
            ref = int(r["ref"] or 0)
            chance = float(r["chance"] or 0)
            if ref < 0:
                ref_id = -ref
                if depth > 3 or ref_id not in self.refs:
                    continue
                times = max(1, int(r["maxcount"] or 1))
                if world is not None and ref_id in self.world_refs:
                    for item, (c, q) in self.expand_ref(ref_id, depth).items():
                        world.add(item)
                    continue
                for item, (c, q) in self.expand_ref(ref_id, depth).items():
                    add(item, abs(chance) / 100.0 * c * times, q)
            elif int(r["groupid"] or 0) > 0:
                groups.setdefault(int(r["groupid"]), []).append(r)
            else:
                add(int(r["item"]), abs(chance), chance < 0)
        for members in groups.values():
            explicit = sum(abs(float(m["chance"] or 0)) for m in members)
            zero = [m for m in members if float(m["chance"] or 0) == 0]
            share = max(0.0, 100.0 - explicit) / len(zero) if zero else 0.0
            for m in members:
                c = float(m["chance"] or 0)
                add(int(m["item"]), abs(c) if c != 0 else share, c < 0)
        return out

    def expand_ref(self, ref_id, depth):
        if ref_id not in self.ref_cache:
            self.ref_cache[ref_id] = self.expand(self.refs[ref_id], depth + 1)
        return self.ref_cache[ref_id]


def permyriad(chance, quest):
    v = max(1, int(round(chance * 100)))
    return -v if quest else v


def top_sources(by_item, limit=TOP_SOURCES):
    """by_item: {itemID: {sourceID: (chance, quest)}} -> {itemID: [total, id, chance, ...]}"""
    out = {}
    for item, sources in by_item.items():
        ranked = sorted(sources.items(), key=lambda kv: (-kv[1][0], kv[0]))
        flat = [len(ranked)]
        for ident, (chance, quest) in ranked[:limit]:
            flat += [ident, permyriad(chance, quest)]
        out[item] = flat
    return out


def extract_loot(db, item_quality):
    """-> drops, worldDrops, skinned, pickpocketed, gathered, fished, contained (+ npc / object ids used)."""
    refs = loot_table(db, "reference_loot_template")
    creature = loot_table(db, "creature_loot_template")
    users = {}
    for table in (creature, loot_table(db, "gameobject_loot_template"), loot_table(db, "item_loot_template")):
        for lid, entries in table.items():
            for r in entries:
                if int(r["ref"] or 0) < 0:
                    users.setdefault(-int(r["ref"]), set()).add(lid)
    world_refs = {ref for ref, who in users.items() if len(who) >= WORLD_REF_USERS}
    resolver = LootResolver(refs, world_refs)

    def keep(item, chance, quest):
        return (quest or item_quality.get(item, 0) >= 1) and chance >= MIN_CHANCE and item in item_quality

    templates = list(rows(db, "SELECT Entry, MinLevel, MaxLevel, LootId, SkinningLootId, PickpocketLootId FROM creature_template"))
    drops, skinned, picked = {}, {}, {}
    world_levels = {}
    for t in templates:
        npc = int(t["Entry"])
        for field, table, target, world in (("LootId", creature, drops, True), ("SkinningLootId", None, skinned, False), ("PickpocketLootId", None, picked, False)):
            lid = int(t[field] or 0)
            if not lid:
                continue
            if table is None:
                table = loot_table.cache.setdefault(field, loot_table(db, "skinning_loot_template" if field == "SkinningLootId" else "pickpocketing_loot_template"))
            entries = table.get(lid)
            if not entries:
                continue
            worldset = set() if world else None
            for item, (chance, quest) in resolver.expand(entries, world=worldset).items():
                if keep(item, chance, quest):
                    target.setdefault(item, {})[npc] = (chance, quest)
            for item in worldset or ():
                if item_quality.get(item, 0) >= 1:
                    lo, hi = world_levels.get(item, (999, 0))
                    world_levels[item] = (min(lo, int(t["MinLevel"] or 0)), max(hi, int(t["MaxLevel"] or 0)))

    go_loot = loot_table(db, "gameobject_loot_template")
    gathered = {}
    for g in rows(db, "SELECT entry, type, data0, data1 FROM gameobject_template WHERE type IN (3, 25)"):
        lid = int(g["data1"] or 0)
        entries = go_loot.get(lid)
        if not entries:
            continue
        for item, (chance, quest) in resolver.expand(entries).items():
            if keep(item, chance, quest):
                gathered.setdefault(item, {})[int(g["entry"])] = (chance, quest)

    fished = {}
    for area, entries in loot_table(db, "fishing_loot_template").items():
        for item, (chance, quest) in resolver.expand(entries).items():
            if keep(item, chance, quest):
                fished.setdefault(item, {})[area] = (chance, quest)

    contained = {}
    for container, entries in loot_table(db, "item_loot_template").items():
        for item, (chance, quest) in resolver.expand(entries).items():
            if keep(item, chance, quest):
                contained.setdefault(item, {})[container] = (chance, quest)

    world = {item: [lo, hi] for item, (lo, hi) in world_levels.items() if item not in drops}
    return {
        "drops": top_sources(drops), "worldDrops": world, "skinned": top_sources(skinned), "pickpocketed": top_sources(picked),
        "gathered": top_sources(gathered), "fished": top_sources(fished), "contained": top_sources(contained),
    }


loot_table.cache = {}


def extract_vendors(db):
    """-> vendors {itemID: [price per unit, stack, npcID, limited, ...]} (at most 12 NPCs per item)."""
    price = {}
    for r in rows(db, "SELECT entry, BuyPrice, BuyCount FROM item_template"):
        count = max(1, int(r["BuyCount"] or 1))
        price[int(r["entry"])] = (int(round((r["BuyPrice"] or 0) / count)), count)
    by_item = {}
    templates = {}
    for r in rows(db, "SELECT entry, item, maxcount FROM npc_vendor_template"):
        templates.setdefault(int(r["entry"]), []).append(r)
    stock = []
    for r in rows(db, "SELECT entry, item, maxcount FROM npc_vendor"):
        stock.append((int(r["entry"]), int(r["item"]), int(r["maxcount"] or 0)))
    for t in rows(db, "SELECT Entry, VendorTemplateId FROM creature_template WHERE VendorTemplateId > 0"):
        for r in templates.get(int(t["VendorTemplateId"]), []):
            stock.append((int(t["Entry"]), int(r["item"]), int(r["maxcount"] or 0)))
    for npc, item, limited in stock:
        if item <= 0:
            continue
        by_item.setdefault(item, {})[npc] = 1 if limited > 0 else 0
    out = {}
    for item, npcs in by_item.items():
        unit, count = price.get(item, (0, 1))
        flat = [unit, count]
        for npc in sorted(npcs)[:12]:
            flat += [npc, npcs[npc]]
        out[item] = flat
    return out


def extract_trainers(db):
    """-> trainers {recipeSpellID: [skillLine, skill, cost, npcID, ...]} for profession recipes."""
    teaches = {}
    for r in rows(db, "SELECT Id, Effect1, Effect2, Effect3, EffectTriggerSpell1, EffectTriggerSpell2, EffectTriggerSpell3 FROM spell_template"):
        for i in (1, 2, 3):
            if int(r["Effect%d" % i] or 0) == 36 and int(r["EffectTriggerSpell%d" % i] or 0) > 0:
                teaches[int(r["Id"])] = int(r["EffectTriggerSpell%d" % i])
                break
    offers = []
    templates = {}
    for r in rows(db, "SELECT entry, spell, spellcost, reqskill, reqskillvalue FROM npc_trainer_template"):
        templates.setdefault(int(r["entry"]), []).append(r)
    for r in rows(db, "SELECT entry, spell, spellcost, reqskill, reqskillvalue FROM npc_trainer"):
        offers.append((int(r["entry"]), r))
    for t in rows(db, "SELECT Entry, TrainerTemplateId FROM creature_template WHERE TrainerTemplateId > 0"):
        for r in templates.get(int(t["TrainerTemplateId"]), []):
            offers.append((int(t["Entry"]), r))
    out = {}
    for npc, r in offers:
        skill = int(r["reqskill"] or 0)
        if skill <= 0:
            continue
        spell = int(r["spell"] or 0)
        recipe = teaches.get(spell, spell)
        row = out.get(recipe)
        if not row:
            row = out[recipe] = [skill, int(r["reqskillvalue"] or 0), int(r["spellcost"] or 0)]
        if npc not in row[3:]:
            row.append(npc)
    return out


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------
ALLIANCE, HORDE = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128
BAD_TITLE = re.compile(r"^\s*<|\[?(UNUSED|DEPRECATED|NYI|TEST|PH)\b|\bZZOLD|^\s*\[", re.I)


def side_of(races):
    races = races or 0
    a, h = races & ALLIANCE, races & HORDE
    if races == 0 or (a and h):
        return 0
    return 1 if a else (2 if h else 0)


def clean_text(text):
    if not text:
        return None
    text = re.sub(r"\$[Bb]", " ", text)
    text = re.sub(r"\$[Nn]", "<name>", text)
    text = re.sub(r"\$[Cc]", "<class>", text)
    text = re.sub(r"\$[Rr]", "<race>", text)
    text = re.sub(r"\$[Gg]([^:;]*):([^;]*);", r"\1/\2", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text or None


def rows(db, sql, *args):
    cur = db.execute(sql, args)
    names = [d[0] for d in cur.description]
    for r in cur:
        yield dict(zip(names, r))


def pairs(row, id_fmt, count_fmt, n):
    out = []
    for i in range(1, n + 1):
        ident, count = row.get(id_fmt % i) or 0, row.get(count_fmt % i) or 0
        if ident:
            out += [int(ident), int(count) if count else 1]
    return out


def npc_side(template, templates):
    """0 usable by both factions, 1 Alliance only, 2 Horde only, 3 hostile to both, None unknown."""
    t = templates.get(template)
    if not t:
        return None
    enemy = t.get("enemyGroup", 0)
    alliance_ok = not (enemy & 2)
    horde_ok = not (enemy & 4)
    if alliance_ok and horde_ok:
        return 0
    if alliance_ok:
        return 1
    if horde_ok:
        return 2
    return 3


LOCK_SKILLS = {2: 1, 3: 2, 19: 3, 1: 4}   # lock type -> 1 Herbalism, 2 Mining, 3 Fishing, 4 Lockpicking


def object_lock(lock_id, locks):
    for lock_type, skill in locks.get(lock_id, []):
        if lock_type in LOCK_SKILLS:
            return LOCK_SKILLS[lock_type], skill
    return None, None


def extract(db, placer, client):
    starters_npc, starters_go, enders_npc, enders_go = {}, {}, {}, {}
    for table, target in (("creature_questrelation", starters_npc), ("gameobject_questrelation", starters_go),
                          ("creature_involvedrelation", enders_npc), ("gameobject_involvedrelation", enders_go)):
        for r in rows(db, 'SELECT id, quest FROM "%s"' % table):
            target.setdefault(int(r["quest"]), []).append(int(r["id"]))
    starter_items = {}
    for r in rows(db, 'SELECT entry, startquest FROM item_template WHERE startquest > 0'):
        starter_items.setdefault(int(r["startquest"]), int(r["entry"]))

    quests = {}
    raw = {int(r["entry"]): r for r in rows(db, "SELECT * FROM quest_template")}
    for qid, r in raw.items():
        title = r.get("Title") or ""
        if not title or BAD_TITLE.search(title):
            continue
        if qid not in starters_npc and qid not in starters_go and qid not in starter_items and qid not in enders_npc and qid not in enders_go:
            continue
        quests[qid] = r

    # Prerequisites: PrevQuestId > 0, and every quest whose NextQuestId points
    # here (grouped by ExclusiveGroup: > 0 any one of the group, else each).
    pre = {qid: [] for qid in quests}
    for qid, r in quests.items():
        prev = int(r.get("PrevQuestId") or 0)
        if prev > 0 and prev in quests:
            pre[qid].append([prev])
    pointing = {}
    for qid, r in quests.items():
        nxt = int(r.get("NextQuestId") or 0)
        if nxt > 0 and nxt in quests:
            pointing.setdefault(nxt, []).append(qid)
    for target, sources in pointing.items():
        groups = {}
        for s in sources:
            g = int(quests[s].get("ExclusiveGroup") or 0)
            if g > 0:
                groups.setdefault(g, []).append(s)
            elif not any(s in grp for grp in pre[target]):
                pre[target].append([s])
        for g in sorted(groups):
            members = sorted(groups[g])
            if not any(set(members) == set(grp) for grp in pre[target]):
                pre[target].append(members)

    out_quests = {}
    npc_ids, go_ids = set(), set()
    for qid, r in sorted(quests.items()):
        req_kills = []
        for i in range(1, 5):
            ident, count = int(r.get("ReqCreatureOrGOId%d" % i) or 0), int(r.get("ReqCreatureOrGOCount%d" % i) or 0)
            if ident:
                req_kills += [ident, count or 1]
                (npc_ids if ident > 0 else go_ids).add(abs(ident))
        rep = []
        for i in range(1, 6):
            f, v = int(r.get("RewRepFaction%d" % i) or 0), int(r.get("RewRepValue%d" % i) or 0)
            if f and v:
                rep += [f, v]
        for n in starters_npc.get(qid, []) + enders_npc.get(qid, []):
            npc_ids.add(n)
        for g in starters_go.get(qid, []) + enders_go.get(qid, []):
            go_ids.add(g)
        skill = int(r.get("RequiredSkill") or 0)
        out_quests[qid] = [
            r["Title"].strip(),                                   # 1 title
            int(r.get("QuestLevel") or 0),                        # 2 quest level
            int(r.get("MinLevel") or 0),                          # 3 required level
            side_of(int(r.get("RequiredRaces") or 0)),            # 4 0 both / 1 Alliance / 2 Horde
            int(r.get("RequiredClasses") or 0),                   # 5 class mask (0 = any)
            int(r.get("ZoneOrSort") or 0),                        # 6 zone (AreaTable) or -sort
            sorted(set(starters_npc.get(qid, []))) or None,       # 7 starter NPCs
            sorted(set(starters_go.get(qid, []))) or None,        # 8 starter objects
            starter_items.get(qid),                               # 9 item that starts it
            sorted(set(enders_npc.get(qid, []))) or None,         # 10 turn-in NPCs
            sorted(set(enders_go.get(qid, []))) or None,          # 11 turn-in objects
            pairs(r, "ReqItemId%d", "ReqItemCount%d", 4) or None, # 12 items to bring {id, count, ...}
            req_kills or None,                                    # 13 kills / object uses {id (neg = object), count, ...}
            pairs(r, "RewChoiceItemId%d", "RewChoiceItemCount%d", 6) or None,  # 14 choice rewards
            pairs(r, "RewItemId%d", "RewItemCount%d", 4) or None,              # 15 fixed rewards
            rep or None,                                          # 16 reputation {faction, value, ...}
            pre[qid] or None,                                     # 17 prerequisites { {any of ids}, ... }
            int(r.get("NextQuestInChain") or 0) or None,          # 18 follow-up
            int(r.get("SrcItemId") or 0) or None,                 # 19 item provided at start
            clean_text(r.get("Objectives")),                      # 20 objective text
            int(r.get("SuggestedPlayers") or 0) or None,          # 21 suggested group size
            [skill, int(r.get("RequiredSkillValue") or 0)] if skill else None,  # 22 required skill
            int(r.get("BreadcrumbForQuestId") or 0) or None,      # 23 breadcrumb for
            int(r.get("Type") or 0) or None,                      # 24 type (1 group, 41 PvP, 62 raid, 81 dungeon)
        ]

    # Spawns: creature rows by id, plus random-entry spawns (creature_spawn_entry).
    def spawns(table, ids, entry_table=None):
        points = {i: [] for i in ids}
        missed = 0
        for r in rows(db, 'SELECT guid, id, map, position_x, position_y FROM "%s"' % table):
            ident = int(r["id"] or 0)
            if ident in points:
                p = placer.place(int(r["map"]), float(r["position_x"]), float(r["position_y"]))
                if p:
                    points[ident].append(p)
                else:
                    missed += 1
        if entry_table:
            guids = {}
            for r in rows(db, 'SELECT guid, entry FROM "%s"' % entry_table):
                if int(r["entry"]) in points:
                    guids.setdefault(int(r["guid"]), []).append(int(r["entry"]))
            if guids:
                for r in rows(db, 'SELECT guid, map, position_x, position_y FROM "%s" WHERE id = 0' % table):
                    for ident in guids.get(int(r["guid"]), []):
                        p = placer.place(int(r["map"]), float(r["position_x"]), float(r["position_y"]))
                        if p:
                            points[ident].append(p)
        return points, missed

    # Loot, vendors and trainers, and the NPCs / objects they name.
    item_quality = {int(r["entry"]): int(r["Quality"] or 0) for r in rows(db, "SELECT entry, Quality FROM item_template")}
    loot = extract_loot(db, item_quality)
    vendors = extract_vendors(db)
    trainers = extract_trainers(db)
    for key in ("drops", "skinned", "pickpocketed"):
        for flat in loot[key].values():
            for i in range(1, len(flat), 2):
                npc_ids.add(flat[i])
    for flat in loot["gathered"].values():
        for i in range(1, len(flat), 2):
            go_ids.add(flat[i])
    for flat in vendors.values():
        for i in range(2, len(flat), 2):
            npc_ids.add(flat[i])
    for row in trainers.values():
        for npc in row[3:]:
            npc_ids.add(npc)

    npc_points, npc_missed = spawns("creature", npc_ids, "creature_spawn_entry")
    go_points, go_missed = spawns("gameobject", go_ids, "gameobject_spawn_entry")
    templates = {t["id"]: t for t in client.get("factionTemplates", [])}
    locks = {l["id"]: l["keys"] for l in client.get("locks", [])}
    npcs = {}
    for r in rows(db, 'SELECT Entry, Name, SubName, MinLevel, MaxLevel, NpcFlags, Faction, Rank FROM creature_template'):
        ident = int(r["Entry"])
        if ident in npc_ids:
            npcs[ident] = [r["Name"], r["SubName"] or None, int(r["MinLevel"] or 0), int(r["MaxLevel"] or 0), int(r["NpcFlags"] or 0),
                           compact_spawns(npc_points.get(ident, [])) or None, npc_side(int(r["Faction"] or 0), templates), int(r["Rank"] or 0) or None]
    objects = {}
    for r in rows(db, 'SELECT entry, name, type, data0 FROM gameobject_template'):
        ident = int(r["entry"])
        if ident in go_ids:
            skill, value = object_lock(int(r["data0"] or 0), locks) if int(r["type"] or 0) == 3 else (None, None)
            objects[ident] = [r["name"], int(r["type"] or 0), compact_spawns(go_points.get(ident, [])) or None, skill, value]
    # Drop sources whose NPC never spawns anywhere are noise.
    for key in ("drops", "skinned", "pickpocketed"):
        for item in list(loot[key]):
            flat = loot[key][item]
            kept = [flat[0]]
            for i in range(1, len(flat), 2):
                if npcs.get(flat[i]) and npcs[flat[i]][5]:
                    kept += [flat[i], flat[i + 1]]
            if len(kept) > 1:
                loot[key][item] = kept
            else:
                del loot[key][item]
    stats = {"npcSpawnsOffMap": npc_missed, "objectSpawnsOffMap": go_missed}
    return out_quests, npcs, objects, loot, vendors, trainers, stats


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------
def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 4))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'
    if isinstance(v, (list, tuple)):
        items = [lua(x) for x in v]
        while items and items[-1] == "nil":
            items.pop()
        return "{" + ",".join(items) + "}"
    raise TypeError(type(v))


HEADER = """-- Generated by tools/ClassicDbExtract from CMaNGOS classic-db (%s). Do not edit.
-- GPL-3.0: see LICENSE.md. Contains Blizzard Entertainment content used
-- non-commercially, as described in COPYRIGHT.md.
-- Regenerate with scripts\\extract_classicdb.ps1.
local FP = _G.ForeverPath
if type(FP) ~= "table" then return end
FP.ClassicData = FP.ClassicData or {}
"""


def write_table(path, source, key, layout, rows_):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write("-- %s\n" % layout)
        f.write("FP.ClassicData.%s = {\n" % key)
        for ident in sorted(rows_):
            f.write("[%d]=%s,\n" % (ident, lua(rows_[ident])))
        f.write("}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="classic-db checkout")
    ap.add_argument("--maps", required=True, help="maps.json from tools/DbExtract")
    ap.add_argument("--out", required=True, help="ForeverPath_ClassicDB folder")
    ap.add_argument("--sqlite", required=True, help="SQLite working file")
    ap.add_argument("--commit", default="unknown", help="classic-db commit, for the file headers")
    ap.add_argument("--report", help="JSON report path")
    a = ap.parse_args()

    print("Loading classic-db into SQLite")
    db, load = load_database(a.src, a.sqlite)
    with open(a.maps, encoding="utf-8") as f:
        maps = json.load(f)
    placer = MapPlacer(maps)
    print("Extracting")
    quests, npcs, objects, loot, vendors, trainers, spawn_stats = extract(db, placer, maps)
    source = "classic-db %s" % a.commit[:12]
    os.makedirs(a.out, exist_ok=True)
    write_table(os.path.join(a.out, "Quests.lua"), source, "quests",
                "quests[id] = { title, level, minLevel, side (0 both, 1 Alliance, 2 Horde), classMask, zoneOrSort, starterNpcs, starterObjects, starterItem, "
                "enderNpcs, enderObjects, items {id,count,...}, kills {id (negative = object),count,...}, choiceRewards, rewards, reputation {faction,value,...}, "
                "prerequisites { {any of}, ... }, followUp, providedItem, objectives, groupSize, skill {skillLine, value}, breadcrumbFor, type }", quests)
    write_table(os.path.join(a.out, "Npcs.lua"), source, "npcs",
                "npcs[id] = { name, subName, minLevel, maxLevel, npcFlags, spawns { uiMapID, x, y, ... } (x, y in 0.1% of the zone map; uiMapID < 0 = instance -mapID), "
                "side (0 both factions, 1 Alliance, 2 Horde, 3 hostile, nil unknown), rank (1 elite, 2 rare elite, 3 boss, 4 rare) }", npcs)
    write_table(os.path.join(a.out, "Objects.lua"), source, "objects",
                "objects[id] = { name, type, spawns { uiMapID, x, y, ... }, lockSkill (1 Herbalism, 2 Mining, 3 Fishing, 4 Lockpicking), skillValue }", objects)
    with open(os.path.join(a.out, "Loot.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write("-- chances in 1/100 of a percent (negative = only while on the quest); lists keep the %d most likely sources after the total count\n" % TOP_SOURCES)
        layouts = {
            "drops": "drops[itemID] = { sourceCount, npcID, chance, ... }",
            "skinned": "skinned[itemID] = { sourceCount, npcID, chance, ... }",
            "pickpocketed": "pickpocketed[itemID] = { sourceCount, npcID, chance, ... }",
            "gathered": "gathered[itemID] = { sourceCount, objectID, chance, ... } (herb and ore nodes, chests, fishing pools)",
            "fished": "fished[itemID] = { sourceCount, areaID, chance, ... }",
            "contained": "contained[itemID] = { sourceCount, containerItemID, chance, ... }",
            "worldDrops": "worldDrops[itemID] = { minLevel, maxLevel } of the creatures whose shared loot includes it",
        }
        for key in ("drops", "worldDrops", "skinned", "pickpocketed", "gathered", "fished", "contained"):
            f.write("-- %s\nFP.ClassicData.%s = {\n" % (layouts[key], key))
            for ident in sorted(loot[key]):
                f.write("[%d]=%s,\n" % (ident, lua(loot[key][ident])))
            f.write("}\n")
    write_table(os.path.join(a.out, "Vendors.lua"), source, "vendors",
                "vendors[itemID] = { price per unit (copper), stack, npcID, limited (1 = limited stock), ... }", vendors)
    write_table(os.path.join(a.out, "Trainers.lua"), source, "trainers",
                "trainers[recipeSpellID] = { skillLine, skill required, cost (copper), trainerNpcID, ... }", trainers)
    zone_names = {m["id"]: m["name"] for m in maps["uiMaps"]}
    instance_names = {m["id"]: m["name"] for m in maps["maps"] if m["instanceType"] != 0}
    fished_areas = set()
    for flat in loot["fished"].values():
        for i in range(1, len(flat), 2):
            fished_areas.add(flat[i])
    area_names = {ar["id"]: ar["name"] for ar in maps.get("areas", []) if ar["id"] in fished_areas}
    with open(os.path.join(a.out, "Maps.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % ("Forever client %s" % maps.get("build", "?")))
        f.write("FP.ClassicData.zones = {\n")
        for ident in sorted(zone_names):
            f.write("[%d]=%s,\n" % (ident, lua(zone_names[ident])))
        f.write("}\nFP.ClassicData.instances = {\n")
        for ident in sorted(instance_names):
            f.write("[%d]=%s,\n" % (ident, lua(instance_names[ident])))
        f.write("}\nFP.ClassicData.areas = {\n")
        for ident in sorted(area_names):
            f.write("[%d]=%s,\n" % (ident, lua(area_names[ident])))
        f.write("}\n")
    # Which item ids classic-db knows, as ranges: anything else the client lists is new in Forever.
    ids = sorted(int(r["entry"]) for r in rows(db, "SELECT entry FROM item_template"))
    ranges = []
    for ident in ids:
        if ranges and ident == ranges[-1][1] + 1:
            ranges[-1][1] = ident
        else:
            ranges.append([ident, ident])
    with open(os.path.join(a.out, "Items.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write("-- itemRanges = { first, last, first, last, ... }: the item ids classic-db knows (sorted)\n")
        f.write("FP.ClassicData.itemRanges = {\n")
        for first, last in ranges:
            f.write("%d,%d,\n" % (first, last))
        f.write("}\n")
    with open(os.path.join(a.out, "Meta.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write('FP.ClassicData.meta = { source = %s, commit = %s, quests = %d, npcs = %d, objects = %d, dropItems = %d, vendorItems = %d, trainerRecipes = %d }\n'
                % (lua("CMaNGOS classic-db"), lua(a.commit), len(quests), len(npcs), len(objects), len(loot["drops"]), len(vendors), len(trainers)))
    counts = {"quests": len(quests), "npcs": len(npcs), "objects": len(objects), "vendorItems": len(vendors), "trainerRecipes": len(trainers)}
    counts.update({k: len(v) for k, v in loot.items()})
    report = {"commit": a.commit, "counts": counts, "spawns": spawn_stats, "load": load}
    print("Wrote %d quests, %d NPCs, %d objects to %s" % (len(quests), len(npcs), len(objects), a.out))
    print("  loot: " + ", ".join("%s %d" % (k, len(v)) for k, v in loot.items()) + "; vendor items %d, trainer recipes %d" % (len(vendors), len(trainers)))
    for item in (2447, 2770, 2589, 2318):
        for key in ("drops", "gathered", "skinned"):
            if item in loot[key]:
                print("  check item %d %s: %s" % (item, key, loot[key][item][:7]))
    for item in (2320, 2321):
        if item in vendors:
            print("  check vendor item %d: %s" % (item, vendors[item][:6]))
    for spell in (2392, 3915, 2963):
        if spell in trainers:
            print("  check trainer recipe %d: %s" % (spell, trainers[spell][:6]))
    print("  spawns off any zone map: %d NPC, %d object" % (spawn_stats["npcSpawnsOffMap"], spawn_stats["objectSpawnsOffMap"]))
    for check in (5905, 4722, 6176):
        if check in npcs:
            n = npcs[check]
            print("  check npc %d %s: %s" % (check, n[0], n[5]))
    if a.report:
        with open(a.report, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)


if __name__ == "__main__":
    main()
