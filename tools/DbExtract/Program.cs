// DbExtract: builds ForeverPath's recipe catalogue from the Forever client.
//
// The client ships every profession recipe in its database tables (DB2 files
// inside the CASC store), and the server patches them through the hotfix
// cache (Cache/ADB/<locale>/DBCache.bin). This tool reads both and writes
// ForeverPath/Data/RecipeCatalogue.lua:
//
//   recipes   profession spells that create an item (SkillLineAbility +
//             SpellEffect CreateItem + SpellReagents), with skill ranks, the
//             item that teaches the spell (ItemEffect Learn) and the spell icon;
//             enchants (SpellEffect EnchantItem) are recipes with item 0
//   combines  item-use spells that create an item from other items, such as
//             Eye of Sulfuras -> Sulfuras or three lesser essences -> greater
//   items     names and quality for every item the catalogue refers to
//   professions  skill line names and categories
//   factions  every reputation faction (Faction table): name, parent, pane
//             index and the starting reputation per race mask
//
// Nothing here comes from another addon or a website; it is the game's own
// data for the exact build installed. Re-run after each client patch.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using CASCLib;
using DBCD;
using DBCD.IO;
using DBCD.Providers;

namespace DbExtract
{
    // DB2 files straight out of the CASC store, by file data id.
    class CascDbcProvider : IDBCProvider
    {
        readonly CASCHandler casc;
        readonly IReadOnlyDictionary<string, int> fileDataIds;

        public CascDbcProvider(CASCHandler casc, IReadOnlyDictionary<string, int> fileDataIds)
        {
            this.casc = casc;
            this.fileDataIds = fileDataIds;
        }

        public Stream StreamForTableName(string tableName, string build)
        {
            if (!fileDataIds.TryGetValue(tableName, out var id))
                throw new ArgumentException("no file data id known for table " + tableName);
            using var stream = casc.OpenFile(id);
            var copy = new MemoryStream();
            stream.CopyTo(copy);
            copy.Position = 0;
            return copy;
        }
    }

    // Table layouts (WoWDBDefs) from a local folder, fetched once when missing.
    class CachedDbdProvider : IDBDProvider
    {
        const string Source = "https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/";
        readonly string directory;
        readonly HttpClient http = new HttpClient();

        public CachedDbdProvider(string directory)
        {
            this.directory = directory;
            Directory.CreateDirectory(directory);
        }

        public Stream StreamForTableName(string tableName, string build = null)
        {
            var path = Path.Combine(directory, tableName + ".dbd");
            if (!File.Exists(path))
            {
                Console.WriteLine($"  fetching definition {tableName}.dbd");
                var bytes = http.GetByteArrayAsync(Source + tableName + ".dbd").GetAwaiter().GetResult();
                File.WriteAllBytes(path, bytes);
            }
            return File.OpenRead(path);
        }
    }

    class Options
    {
        public string Wow = @"D:\Blizzard Games\World of Warcraft";
        public string Product = "wow_classic_beta";
        public string Locale = "enUS";
        public string Out = "ForeverPath/Data";
        public string Defs = "tools/DbExtract/definitions";
        public string Report = "tools/DbExtract/last-run.json";
        public string Hotfix;        // explicit DBCache.bin path
        public bool NoHotfix;

        public static Options Parse(string[] args)
        {
            var o = new Options();
            for (int i = 0; i < args.Length; i++)
            {
                string Next() => i + 1 < args.Length ? args[++i] : throw new ArgumentException("missing value for " + args[i]);
                switch (args[i])
                {
                    case "--wow": o.Wow = Next(); break;
                    case "--product": o.Product = Next(); break;
                    case "--locale": o.Locale = Next(); break;
                    case "--out": o.Out = Next(); break;
                    case "--defs": o.Defs = Next(); break;
                    case "--report": o.Report = Next(); break;
                    case "--hotfix": o.Hotfix = Next(); break;
                    case "--no-hotfix": o.NoHotfix = true; break;
                    case "-h": case "--help":
                        Console.WriteLine("DbExtract --wow <install dir> [--product wow_classic_beta] [--locale enUS] [--out <dir>] [--defs <dir>] [--report <file>] [--hotfix <DBCache.bin>] [--no-hotfix]");
                        Environment.Exit(0); break;
                    default: throw new ArgumentException("unknown argument " + args[i]);
                }
            }
            return o;
        }
    }

    class Recipe
    {
        public int SpellId, SkillLine, ItemId, Quantity, MinSkill, GreenSkill, GreySkill, Icon, Acquire;
        public string Name;
        public List<int> TeachItems = new List<int>();
        public List<(int item, int count)> Reagents = new List<(int, int)>();
    }

    class Faction
    {
        public int Id, Parent, Index, Expansion;
        public string Name;
        // One slot per ReputationBase entry: races (64-bit mask as two halves), classes, starting reputation.
        public List<(long raceLow, long raceHigh, long classMask, long baseRep)> Bases = new List<(long, long, long, long)>();
    }

    class Combine
    {
        public int SpellId, ItemId, Quantity;
        public bool Consumes;
        public string Name;
        public List<int> UseItems = new List<int>();
        public List<(int item, int count)> Reagents = new List<(int, int)>();
    }

    static class Program
    {
        // File data ids of the DB2 files (WoWDBDefs manifest.json).
        static readonly Dictionary<string, int> FileDataIds = new Dictionary<string, int>
        {
            { "SkillLine", 1240935 },
            { "SkillLineAbility", 1266278 },
            { "SpellReagents", 841946 },
            { "SpellEffect", 1140088 },
            { "SpellName", 1990283 },
            { "SpellMisc", 1003144 },
            { "ItemEffect", 969941 },
            { "ItemXItemEffect", 3177687 },
            { "ItemSparse", 1572924 },
            { "Item", 841626 },
            { "Faction", 1361972 },
        };

        // Skill line categories worth cataloguing: 11 primary professions, 9 secondary.
        static readonly HashSet<int> ProfessionCategories = new HashSet<int> { 9, 11 };
        const int EffectCreateItem = 24;
        const int EffectCreateTradeskillItem = 157;
        const int EffectEnchantItem = 53;            // permanent enchant (Enchanting)
        const int EffectEnchantItemTemporary = 54;   // temporary enchant (sharpening, oils applied by spell)
        const int TriggerOnUse = 0;
        const int TriggerLearn = 6;

        static readonly Dictionary<string, string> ProductFolders = new Dictionary<string, string>
        {
            { "wow_classic_beta", "_classic_beta_" }, { "wow_classic_era", "_classic_era_" }, { "wow_classic", "_classic_" },
            { "wow", "_retail_" }, { "wow_anniversary", "_anniversary_" }, { "wowf", "_forever_" }, { "wow_beta", "_beta_" },
        };

        static int I(object o) => Convert.ToInt32(o, CultureInfo.InvariantCulture);
        static long L(object o) => Convert.ToInt64(o, CultureInfo.InvariantCulture);
        // Faction.ReputationRaceMask: one 64-bit array in older layouts, four
        // ReputationRaceMasks<i> fields of two 32-bit halves (low, high) in newer ones.
        static long[] RaceMasks(DBCDRow row)
        {
            try
            {
                var a = row["ReputationRaceMask"];
                if (a is Array arr) return arr.Cast<object>().Select(L).ToArray();
            }
            catch (Exception) { }
            var list = new List<long>();
            for (int i = 0; i < 4; i++)
            {
                try
                {
                    var v = row["ReputationRaceMasks" + i];
                    if (v is Array parts)
                    {
                        var p = parts.Cast<object>().Select(L).ToArray();
                        long low = p.Length > 0 ? (p[0] & 0xFFFFFFFFL) : 0;
                        long high = p.Length > 1 ? (p[1] & 0xFFFFFFFFL) : 0;
                        list.Add(low | (high << 32));
                    }
                    else list.Add(L(v));
                }
                catch (Exception) { break; }
            }
            return list.ToArray();
        }

        // An array field, or the same values spread over numbered scalar fields (newer layouts).
        static long[] Longs(DBCDRow row, string arrayField, string scalarPrefix, int count)
        {
            try
            {
                var a = row[arrayField];
                if (a is Array arr) return arr.Cast<object>().Select(L).ToArray();
                if (a != null) return new[] { L(a) };
            }
            catch (Exception) { }
            var list = new List<long>();
            for (int i = 0; i < count; i++)
            {
                try { list.Add(L(row[scalarPrefix + i])); }
                catch (Exception) { break; }
            }
            return list.ToArray();
        }
        static int[] Ints(object o) => ((Array)o).Cast<object>().Select(I).ToArray();
        static Dictionary<int, DBCDRow> Rows(IDBCDStorage s) => new Dictionary<int, DBCDRow>((IDictionary<int, DBCDRow>)s);

        static int Main(string[] args)
        {
            Options o;
            try { o = Options.Parse(args); }
            catch (Exception e) { Console.Error.WriteLine(e.Message); return 2; }

            Console.WriteLine($"Opening {o.Product} at {o.Wow}");
            var config = CASCConfig.LoadLocalStorageConfig(o.Wow, o.Product, null);
            Console.WriteLine($"Build {config.BuildName} ({config.VersionName})");
            var casc = CASCHandler.OpenStorage(config, null);
            var locale = (LocaleFlags)Enum.Parse(typeof(LocaleFlags), o.Locale);
            casc.Root.SetFlags(locale, false, false);

            var dbcd = new DBCD.DBCD(new CascDbcProvider(casc, FileDataIds), new CachedDbdProvider(o.Defs));
            var dbcdLocale = (Locale)Enum.Parse(typeof(Locale), o.Locale, true);

            HotfixReader hotfix = null;
            string hotfixPath = o.Hotfix;
            if (!o.NoHotfix)
            {
                if (hotfixPath == null && ProductFolders.TryGetValue(o.Product, out var folder))
                    hotfixPath = Path.Combine(o.Wow, folder, "Cache", "ADB", o.Locale, "DBCache.bin");
                if (hotfixPath != null && File.Exists(hotfixPath))
                {
                    hotfix = new HotfixReader(hotfixPath);
                    Console.WriteLine($"Hotfix cache {hotfixPath} (build {hotfix.BuildId})");
                }
                else
                {
                    Console.WriteLine("No hotfix cache found; base tables only. Log in once so the client writes Cache/ADB/<locale>/DBCache.bin.");
                }
            }

            var hotfixed = new Dictionary<string, int>();
            IDBCDStorage Load(string table)
            {
                var storage = dbcd.Load(table, config.VersionName, dbcdLocale);
                int before = storage.Count;
                if (hotfix != null) storage.ApplyingHotfixes(hotfix);
                hotfixed[table] = storage.Count - before;
                Console.WriteLine($"  {table}: {storage.Count} rows" + (hotfix != null ? $" ({storage.Count - before:+#;-#;0} from hotfixes)" : ""));
                return storage;
            }

            Console.WriteLine("Loading tables");
            var skillLine = Rows(Load("SkillLine"));
            var skillLineAbility = Rows(Load("SkillLineAbility"));
            var spellReagents = Rows(Load("SpellReagents"));
            var spellEffect = Rows(Load("SpellEffect"));
            var spellName = Rows(Load("SpellName"));
            var spellMisc = Rows(Load("SpellMisc"));
            var itemEffect = Rows(Load("ItemEffect"));
            var itemXItemEffect = Rows(Load("ItemXItemEffect"));
            var itemSparse = Rows(Load("ItemSparse"));
            // Every item this client knows. ItemSparse is partial (the server streams
            // rows into the hotfix cache as items are seen), Item is complete.
            var itemTable = Rows(Load("Item"));
            var clientItems = new HashSet<int>(itemTable.Keys);
            var factionTable = Rows(Load("Faction"));

            // Spell -> items it creates (first effect first).
            var creates = new Dictionary<int, List<(int item, int qty)>>();
            foreach (var row in spellEffect.Values.OrderBy(r => I(r["EffectIndex"])))
            {
                int effect = I(row["Effect"]);
                if (effect != EffectCreateItem && effect != EffectCreateTradeskillItem) continue;
                if (I(row["DifficultyID"]) != 0) continue;
                int item = I(row["EffectItemType"]);
                if (item <= 0) continue;
                int qty = (int)Math.Round(Convert.ToDouble(row["EffectBasePointsF"], CultureInfo.InvariantCulture));
                if (qty < 1) qty = 1;
                int spell = I(row["SpellID"]);
                if (!creates.TryGetValue(spell, out var list)) creates[spell] = list = new List<(int, int)>();
                list.Add((item, qty));
            }

            // Spells that enchant an item instead of making one (Enchanting).
            var enchants = new HashSet<int>();
            foreach (var row in spellEffect.Values)
            {
                int effect = I(row["Effect"]);
                if (effect != EffectEnchantItem && effect != EffectEnchantItemTemporary) continue;
                if (I(row["DifficultyID"]) != 0) continue;
                enchants.Add(I(row["SpellID"]));
            }

            var reagents = new Dictionary<int, List<(int item, int count)>>();
            foreach (var row in spellReagents.Values)
            {
                var reagentItems = Ints(row["Reagent"]);
                var counts = Ints(row["ReagentCount"]);
                var list = new List<(int, int)>();
                for (int i = 0; i < reagentItems.Length; i++)
                    if (reagentItems[i] > 0 && counts[i] > 0) list.Add((reagentItems[i], counts[i]));
                reagents[I(row["SpellID"])] = list;
            }

            var icons = new Dictionary<int, int>();
            foreach (var row in spellMisc.Values)
                if (I(row["DifficultyID"]) == 0) icons[I(row["SpellID"])] = I(row["SpellIconFileDataID"]);

            // Item effects: which items teach a spell, which items cast one on use.
            var teaches = new Dictionary<int, SortedSet<int>>();
            var uses = new Dictionary<int, List<(int item, int charges)>>();
            foreach (var link in itemXItemEffect.Values)
            {
                if (!itemEffect.TryGetValue(I(link["ItemEffectID"]), out var effect)) continue;
                int item = I(link["ItemID"]);
                int spell = I(effect["SpellID"]);
                int trigger = I(effect["TriggerType"]);
                if (trigger == TriggerLearn)
                {
                    if (!teaches.TryGetValue(spell, out var set)) teaches[spell] = set = new SortedSet<int>();
                    set.Add(item);
                }
                else if (trigger == TriggerOnUse)
                {
                    if (!uses.TryGetValue(spell, out var list)) uses[spell] = list = new List<(int, int)>();
                    list.Add((item, I(effect["Charges"])));
                }
            }

            // Skill lines: name, category, parent.
            var lines = new Dictionary<int, (string name, int category, int parent)>();
            foreach (var row in skillLine.Values)
                lines[I(row["ID"])] = (Convert.ToString(row["DisplayName_lang"]), I(row["CategoryID"]), I(row["ParentSkillLineID"]));

            // One SkillLineAbility row per spell: a top-level profession line first, then the lowest id.
            var abilityFor = new Dictionary<int, DBCDRow>();
            foreach (var row in skillLineAbility.Values.OrderBy(r => I(r["SkillLine"])))
            {
                int line = I(row["SkillLine"]);
                if (!lines.TryGetValue(line, out var info)) continue;
                if (!ProfessionCategories.Contains(info.category)) continue;
                if (info.name.Contains("[DNT]")) continue;
                int spell = I(row["Spell"]);
                if (abilityFor.TryGetValue(spell, out var existing))
                {
                    bool existingTop = lines[I(existing["SkillLine"])].parent == 0;
                    if (existingTop || info.parent != 0) continue;
                }
                abilityFor[spell] = row;
            }

            // True when the item and everything it needs still exist on this client.
            bool InClient(int output, List<(int item, int count)> needs) =>
                clientItems.Contains(output) && needs.All(n => clientItems.Contains(n.item));

            var recipes = new SortedDictionary<int, Recipe>();
            var skipped = new { noReagents = new List<int>(), noName = new List<int>(), extraOutputs = new List<int>(), notInClient = new List<int>() };
            foreach (var kv in abilityFor)
            {
                int spell = kv.Key;
                bool isEnchant = false;
                if (!creates.TryGetValue(spell, out var outputs))
                {
                    if (!enchants.Contains(spell)) continue;
                    isEnchant = true;
                }
                if (!spellName.TryGetValue(spell, out var nameRow)) { skipped.noName.Add(spell); continue; }
                if (!reagents.TryGetValue(spell, out var needs) || needs.Count == 0) { skipped.noReagents.Add(spell); continue; }
                if (isEnchant ? !needs.All(n => clientItems.Contains(n.item)) : !InClient(outputs[0].item, needs)) { skipped.notInClient.Add(spell); continue; }
                if (!isEnchant && outputs.Count > 1) skipped.extraOutputs.Add(spell);
                var row = kv.Value;
                int skillLineId = I(row["SkillLine"]);
                var recipe = new Recipe
                {
                    SpellId = spell,
                    Name = Convert.ToString(nameRow["Name_lang"]),
                    SkillLine = skillLineId,
                    ItemId = isEnchant ? 0 : outputs[0].item,
                    Quantity = isEnchant ? 0 : outputs[0].qty,
                    MinSkill = I(row["MinSkillLineRank"]),
                    GreenSkill = I(row["TrivialSkillLineRankLow"]),
                    GreySkill = I(row["TrivialSkillLineRankHigh"]),
                    Acquire = I(row["AcquireMethod"]),
                    Icon = icons.TryGetValue(spell, out var icon) ? icon : 0,
                    Reagents = needs,
                };
                if (teaches.TryGetValue(spell, out var teachers))
                {
                    recipe.TeachItems.AddRange(teachers.Where(clientItems.Contains));
                    // The skill a recipe needs is carried by the plans / pattern that
                    // teaches it. Trainer-only recipes keep SkillLineAbility's value
                    // (normally 1): the trainer's requirement is server-side data.
                    foreach (var teacher in recipe.TeachItems)
                    {
                        if (!itemSparse.TryGetValue(teacher, out var teachRow)) continue;
                        int reqSkill = I(teachRow["RequiredSkill"]);
                        int reqRank = I(teachRow["RequiredSkillRank"]);
                        if (reqRank > recipe.MinSkill && (reqSkill == skillLineId || reqSkill == lines[skillLineId].parent || reqSkill == 0))
                            recipe.MinSkill = reqRank;
                    }
                }
                recipes[spell] = recipe;
            }

            // Combines: an item's on-use spell that turns other items into a new one.
            var combines = new SortedDictionary<int, Combine>();
            foreach (var kv in uses)
            {
                int spell = kv.Key;
                if (recipes.ContainsKey(spell)) continue;
                if (!creates.TryGetValue(spell, out var outputs)) continue;
                if (!reagents.TryGetValue(spell, out var needs) || needs.Count == 0) continue;
                if (!spellName.TryGetValue(spell, out var nameRow)) continue;
                if (!InClient(outputs[0].item, needs) || !kv.Value.Any(u => clientItems.Contains(u.item))) { skipped.notInClient.Add(spell); continue; }
                var combine = new Combine
                {
                    SpellId = spell,
                    Name = Convert.ToString(nameRow["Name_lang"]),
                    ItemId = outputs[0].item,
                    Quantity = outputs[0].qty,
                    Consumes = kv.Value.Any(u => u.charges != 0),
                    Reagents = needs,
                };
                combine.UseItems.AddRange(kv.Value.Select(u => u.item).Where(clientItems.Contains).Distinct().OrderBy(x => x));
                combines[spell] = combine;
            }

            // Items referenced anywhere.
            var itemIds = new SortedSet<int>();
            foreach (var r in recipes.Values) { if (r.ItemId != 0) itemIds.Add(r.ItemId); itemIds.UnionWith(r.TeachItems); foreach (var x in r.Reagents) itemIds.Add(x.item); }
            foreach (var c in combines.Values) { itemIds.Add(c.ItemId); itemIds.UnionWith(c.UseItems); foreach (var x in c.Reagents) itemIds.Add(x.item); }
            // Every referenced item gets its class and subclass from the Item table
            // (complete); name, quality and binding come from ItemSparse when it has
            // the row, otherwise the name is empty and the client supplies it later.
            var items = new SortedDictionary<int, (string name, int quality, int bind, int classId, int subclassId)>();
            var unnamed = new List<int>();
            foreach (var id in itemIds)
            {
                int classId = 0, subclassId = 0;
                if (itemTable.TryGetValue(id, out var baseRow))
                {
                    classId = I(baseRow["ClassID"]);
                    subclassId = I(baseRow["SubclassID"]);
                }
                if (itemSparse.TryGetValue(id, out var row))
                    items[id] = (Convert.ToString(row["Display_lang"]), I(row["OverallQualityID"]), I(row["Bonding"]), classId, subclassId);
                else
                {
                    items[id] = ("", 0, 0, classId, subclassId);
                    unnamed.Add(id);
                }
            }

            var professions = new SortedDictionary<int, (string name, int category, int parent)>();
            foreach (var r in recipes.Values)
                if (!professions.ContainsKey(r.SkillLine)) professions[r.SkillLine] = lines[r.SkillLine];

            // Factions that can appear in the reputation pane (ReputationIndex >= 0),
            // with the starting reputation per race mask so an unmet faction's
            // standing is known before the player encounters it.
            var factions = new SortedDictionary<int, Faction>();
            foreach (var row in factionTable.Values)
            {
                int index = I(row["ReputationIndex"]);
                string name = Convert.ToString(row["Name_lang"]);
                if (index < 0 || string.IsNullOrWhiteSpace(name)) continue;
                var faction = new Faction { Id = I(row["ID"]), Name = name, Index = index };
                try { faction.Parent = I(row["ParentFactionID"]); } catch (Exception) { }
                try { faction.Expansion = I(row["Expansion"]); } catch (Exception) { }
                var masks = RaceMasks(row);
                var classes = Longs(row, "ReputationClassMask", "ReputationClassMask", 4);
                var bases = Longs(row, "ReputationBase", "ReputationBase", 4);
                for (int i = 0; i < Math.Min(masks.Length, bases.Length); i++)
                    faction.Bases.Add((masks[i] & 0xFFFFFFFFL, (masks[i] >> 32) & 0xFFFFFFFFL, i < classes.Length ? classes[i] & 0xFFFFL : 0, bases[i]));
                factions[faction.Id] = faction;
            }

            Directory.CreateDirectory(o.Out);
            var outPath = Path.Combine(o.Out, "RecipeCatalogue.lua");
            var generated = DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            WriteLua(outPath, config, o, hotfix, generated, professions, recipes, combines, items, factions);
            int enchantCount = recipes.Values.Count(r => r.ItemId == 0);
            Console.WriteLine($"Wrote {outPath}: {recipes.Count} recipes ({enchantCount} enchants), {combines.Count} combines, {items.Count} items, {professions.Count} professions, {factions.Count} factions");
            foreach (var p in professions.OrderByDescending(p => recipes.Values.Count(r => r.SkillLine == p.Key)))
                Console.WriteLine($"  {p.Value.name}: {recipes.Values.Count(r => r.SkillLine == p.Key)}");
            Console.WriteLine($"  skipped: {skipped.notInClient.Count} whose item or reagents no longer exist on this client, {skipped.noReagents.Count} without reagents, {skipped.noName.Count} without a name; {skipped.extraOutputs.Count} create more than one item (first kept); {unnamed.Count} items without a cached name (the client names them at runtime)");

            if (recipes.TryGetValue(21161, out var sample))
                Console.WriteLine($"  check Sulfuron Hammer: {sample.Name} skill {sample.MinSkill}/{sample.GreenSkill}/{sample.GreySkill} -> item {sample.ItemId} x{sample.Quantity}, taught by {string.Join(",", sample.TeachItems)}, reagents {string.Join(" ", sample.Reagents.Select(r => r.item + "x" + r.count))}");
            if (recipes.TryGetValue(20034, out var sampleEnchant))
                Console.WriteLine($"  check Enchant Weapon - Crusader: {sampleEnchant.Name} skill {sampleEnchant.MinSkill}/{sampleEnchant.GreenSkill}/{sampleEnchant.GreySkill} -> item {sampleEnchant.ItemId}, taught by {string.Join(",", sampleEnchant.TeachItems)}, reagents {string.Join(" ", sampleEnchant.Reagents.Select(r => r.item + "x" + r.count))}");
            foreach (int id in new[] { 72, 609, 576, 87 })
                if (factions.TryGetValue(id, out var f))
                    Console.WriteLine($"  check faction {id}: {f.Name} parent {f.Parent} index {f.Index} bases {string.Join(" ", f.Bases.Select(b => b.raceLow + "/" + b.raceHigh + "/" + b.classMask + ":" + b.baseRep))}");
            if (combines.TryGetValue(21160, out var sampleCombine))
                Console.WriteLine($"  check Eye of Sulfuras: {sampleCombine.Name} -> {sampleCombine.ItemId} from {string.Join(" ", sampleCombine.Reagents.Select(r => r.item + "x" + r.count))} (use item consumed: {sampleCombine.Consumes})");

            if (!string.IsNullOrEmpty(o.Report))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(o.Report)));
                var report = new
                {
                    build = config.VersionName, buildName = config.BuildName, product = o.Product, locale = o.Locale, generated,
                    hotfixBuild = hotfix?.BuildId ?? 0, hotfixRows = hotfixed,
                    counts = new { recipes = recipes.Count, enchants = enchantCount, combines = combines.Count, items = items.Count, professions = professions.Count, factions = factions.Count },
                    perProfession = professions.ToDictionary(p => p.Value.name, p => recipes.Values.Count(r => r.SkillLine == p.Key)),
                    skippedNotInClient = skipped.notInClient, skippedNoReagents = skipped.noReagents, skippedNoName = skipped.noName, multipleOutputs = skipped.extraOutputs, unnamedItems = unnamed,
                };
                File.WriteAllText(o.Report, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine($"Report {o.Report}");
            }
            return 0;
        }

        static string Q(string s)
        {
            var b = new StringBuilder("\"");
            foreach (var ch in s ?? "")
            {
                switch (ch)
                {
                    case '\\': b.Append("\\\\"); break;
                    case '"': b.Append("\\\""); break;
                    case '\n': b.Append("\\n"); break;
                    case '\r': break;
                    default: b.Append(ch); break;
                }
            }
            return b.Append('"').ToString();
        }

        static string Flat(List<(int item, int count)> list) =>
            "{ " + string.Join(", ", list.Select(r => r.item.ToString(CultureInfo.InvariantCulture) + ", " + r.count.ToString(CultureInfo.InvariantCulture))) + " }";

        static string IdList(IEnumerable<int> ids) => "{ " + string.Join(", ", ids.Select(i => i.ToString(CultureInfo.InvariantCulture))) + " }";

        static void WriteLua(string path, CASCConfig config, Options o, HotfixReader hotfix, string generated,
            SortedDictionary<int, (string name, int category, int parent)> professions, SortedDictionary<int, Recipe> recipes,
            SortedDictionary<int, Combine> combines, SortedDictionary<int, (string name, int quality, int bind, int classId, int subclassId)> items,
            SortedDictionary<int, Faction> factions)
        {
            var w = new StringBuilder();
            w.AppendLine("-- Generated by tools/DbExtract from the World of Warcraft: Forever client database. Do not edit.");
            w.AppendLine($"-- Build {config.VersionName} ({config.BuildName}), product {o.Product}, locale {o.Locale}, hotfix cache build {hotfix?.BuildId ?? 0}, generated {generated}.");
            w.AppendLine("-- Regenerate with scripts\\extract_db.ps1 after a client patch.");
            w.AppendLine("--");
            w.AppendLine("-- recipes[spellID]  = { name, skillLine, itemID, quantity, minSkill, yellowSkill, greySkill, icon, teachItem, acquire, { reagentItemID, count, ... } }");
            w.AppendLine("--   minSkill: skill required by the plans / pattern that teaches the spell; 1 when only a trainer teaches it (that requirement is server-side).");
            w.AppendLine("--   yellowSkill / greySkill: SkillLineAbility trivial ranks (recipe turns yellow, then grey; green is midway).");
            w.AppendLine("--   teachItem: the item that teaches the spell, a list when several do, false when none (trainer or auto-learned).");
            w.AppendLine("--   acquire: SkillLineAbility.AcquireMethod as shipped by the client.");
            w.AppendLine("--   itemID and quantity are 0 when the spell enchants an item instead of making one (Enchanting).");
            w.AppendLine("--   Recipes whose item or reagents no longer exist on this client are left out.");
            w.AppendLine("-- combines[spellID] = { name, itemID, quantity, consumesUseItem, { useItemID, ... }, { reagentItemID, count, ... } }");
            w.AppendLine("--   the item's on-use spell makes itemID from the reagents; consumesUseItem is 1 when the used item is spent.");
            w.AppendLine("-- items[itemID]     = { name, quality, bind, classID, subclassID }   (bind: 1 binds when picked up, 2 when equipped, 3 when used, 4 quest item, 0 none)");
            w.AppendLine("--   name is \"\" (and quality / bind 0) when the client had no cached row for the item; it is named at runtime. Class and subclass are always known.");
            w.AppendLine("-- professions[skillLine] = { name, category, parentSkillLine }   (category 11 primary, 9 secondary)");
            w.AppendLine("-- factions[factionID] = { name, parentFactionID, reputationIndex, expansion, { raceMaskLow, raceMaskHigh, classMask, startingReputation, ... } }");
            w.AppendLine("--   every faction the reputation pane can show. Slots are tried in order: the first whose race mask (bit raceID-1, split");
            w.AppendLine("--   into the low and high 32 bits) includes the player's race and whose class mask is 0 or includes the class gives the");
            w.AppendLine("--   starting reputation before the faction is met. A slot with race mask 0 is unused.");
            w.AppendLine("local _, ns = ...");
            w.AppendLine();
            w.AppendLine("ns.Data = ns.Data or {}");
            w.AppendLine("local Catalogue = {");
            w.AppendLine($"  build = {Q(config.VersionName)},");
            w.AppendLine($"  buildName = {Q(config.BuildName)},");
            w.AppendLine($"  product = {Q(o.Product)},");
            w.AppendLine($"  locale = {Q(o.Locale)},");
            w.AppendLine($"  hotfixBuild = {hotfix?.BuildId ?? 0},");
            w.AppendLine($"  generated = {Q(generated)},");
            w.AppendLine($"  counts = {{ recipes = {recipes.Count}, enchants = {recipes.Values.Count(r => r.ItemId == 0)}, combines = {combines.Count}, items = {items.Count}, professions = {professions.Count}, factions = {factions.Count} }},");
            w.AppendLine("}");
            w.AppendLine("ns.Data.Catalogue = Catalogue");
            w.AppendLine();

            w.AppendLine("Catalogue.professions = {");
            foreach (var p in professions)
                w.AppendLine($"  [{p.Key}] = {{ {Q(p.Value.name)}, {p.Value.category}, {p.Value.parent} }},");
            w.AppendLine("}");
            w.AppendLine();

            w.AppendLine("Catalogue.recipes = {");
            foreach (var r in recipes.Values)
            {
                string teach = r.TeachItems.Count == 0 ? "false" : r.TeachItems.Count == 1 ? r.TeachItems[0].ToString(CultureInfo.InvariantCulture) : IdList(r.TeachItems);
                w.AppendLine($"  [{r.SpellId}] = {{ {Q(r.Name)}, {r.SkillLine}, {r.ItemId}, {r.Quantity}, {r.MinSkill}, {r.GreenSkill}, {r.GreySkill}, {r.Icon}, {teach}, {r.Acquire}, {Flat(r.Reagents)} }},");
            }
            w.AppendLine("}");
            w.AppendLine();

            w.AppendLine("Catalogue.combines = {");
            foreach (var c in combines.Values)
                w.AppendLine($"  [{c.SpellId}] = {{ {Q(c.Name)}, {c.ItemId}, {c.Quantity}, {(c.Consumes ? 1 : 0)}, {IdList(c.UseItems)}, {Flat(c.Reagents)} }},");
            w.AppendLine("}");
            w.AppendLine();

            w.AppendLine("Catalogue.items = {");
            foreach (var it in items)
                w.AppendLine($"  [{it.Key}] = {{ {Q(it.Value.name)}, {it.Value.quality}, {it.Value.bind}, {it.Value.classId}, {it.Value.subclassId} }},");
            w.AppendLine("}");
            w.AppendLine();

            w.AppendLine("Catalogue.factions = {");
            foreach (var f in factions.Values)
            {
                string bases = "{ " + string.Join(", ", f.Bases.Select(b => string.Join(", ", new[] { b.raceLow, b.raceHigh, b.classMask, b.baseRep }.Select(x => x.ToString(CultureInfo.InvariantCulture))))) + " }";
                w.AppendLine($"  [{f.Id}] = {{ {Q(f.Name)}, {f.Parent}, {f.Index}, {f.Expansion}, {bases} }},");
            }
            w.AppendLine("}");

            File.WriteAllText(path, w.ToString(), new UTF8Encoding(false));
        }
    }
}
