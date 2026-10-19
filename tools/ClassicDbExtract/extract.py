"""Builds ForeverPath's classic-era database from CMaNGOS classic-db.

Reads the classic-db repository (Full_DB dump + Updates, applied in the
order InstallFullDB.sh uses) into SQLite, then writes compact Lua tables
into the ForeverPath_ClassicDB addon:

  Quests.lua   quests: title, levels, side, classes, givers, turn-ins,
               prerequisites, follow-ups, items and kills required, rewards,
               reputation, objective text
  Npcs.lua     NPCs those quests use, with spawn points on zone maps
  Objects.lua  game objects those quests use, with spawn points
  Maps.lua     zone map and instance names

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


def extract(db, placer):
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

    npc_points, npc_missed = spawns("creature", npc_ids, "creature_spawn_entry")
    go_points, go_missed = spawns("gameobject", go_ids, "gameobject_spawn_entry")
    npcs = {}
    for r in rows(db, 'SELECT Entry, Name, SubName, MinLevel, MaxLevel, NpcFlags FROM creature_template'):
        ident = int(r["Entry"])
        if ident in npc_ids:
            npcs[ident] = [r["Name"], r["SubName"] or None, int(r["MinLevel"] or 0), int(r["MaxLevel"] or 0), int(r["NpcFlags"] or 0),
                           compact_spawns(npc_points.get(ident, [])) or None]
    objects = {}
    for r in rows(db, 'SELECT entry, name, type FROM gameobject_template'):
        ident = int(r["entry"])
        if ident in go_ids:
            objects[ident] = [r["name"], int(r["type"] or 0), compact_spawns(go_points.get(ident, [])) or None]
    return out_quests, npcs, objects, {"npcSpawnsOffMap": npc_missed, "objectSpawnsOffMap": go_missed}


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
    quests, npcs, objects, spawn_stats = extract(db, placer)
    source = "classic-db %s" % a.commit[:12]
    os.makedirs(a.out, exist_ok=True)
    write_table(os.path.join(a.out, "Quests.lua"), source, "quests",
                "quests[id] = { title, level, minLevel, side (0 both, 1 Alliance, 2 Horde), classMask, zoneOrSort, starterNpcs, starterObjects, starterItem, "
                "enderNpcs, enderObjects, items {id,count,...}, kills {id (negative = object),count,...}, choiceRewards, rewards, reputation {faction,value,...}, "
                "prerequisites { {any of}, ... }, followUp, providedItem, objectives, groupSize, skill {skillLine, value}, breadcrumbFor, type }", quests)
    write_table(os.path.join(a.out, "Npcs.lua"), source, "npcs",
                "npcs[id] = { name, subName, minLevel, maxLevel, npcFlags, spawns { uiMapID, x, y, ... } (x, y in 0.1% of the zone map; uiMapID < 0 = instance -mapID) }", npcs)
    write_table(os.path.join(a.out, "Objects.lua"), source, "objects",
                "objects[id] = { name, type, spawns { uiMapID, x, y, ... } }", objects)
    zone_names = {m["id"]: m["name"] for m in maps["uiMaps"]}
    instance_names = {m["id"]: m["name"] for m in maps["maps"] if m["instanceType"] != 0}
    with open(os.path.join(a.out, "Maps.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % ("Forever client %s" % maps.get("build", "?")))
        f.write("FP.ClassicData.zones = {\n")
        for ident in sorted(zone_names):
            f.write("[%d]=%s,\n" % (ident, lua(zone_names[ident])))
        f.write("}\nFP.ClassicData.instances = {\n")
        for ident in sorted(instance_names):
            f.write("[%d]=%s,\n" % (ident, lua(instance_names[ident])))
        f.write("}\n")
    with open(os.path.join(a.out, "Meta.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write('FP.ClassicData.meta = { source = %s, commit = %s, quests = %d, npcs = %d, objects = %d }\n'
                % (lua("CMaNGOS classic-db"), lua(a.commit), len(quests), len(npcs), len(objects)))
    report = {"commit": a.commit, "counts": {"quests": len(quests), "npcs": len(npcs), "objects": len(objects)}, "spawns": spawn_stats, "load": load}
    print("Wrote %d quests, %d NPCs, %d objects to %s" % (len(quests), len(npcs), len(objects), a.out))
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
