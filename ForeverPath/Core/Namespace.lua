-- ForeverPath: shared addon namespace.
-- Every file listed in the TOC receives (addonName, namespaceTable) through `...`.
local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.16.2"          -- replaced by the TOC "Version" field at load when available
ns.SCHEMA_VERSION = 2         -- SavedVariables schema version; bump together with a migration
ns.PREFIX = "|cff4fc3f7ForeverPath|r"
ns.loaded = false

-- The single intentional global. It lets players inspect the addon (/dump ForeverPath)
-- and lets future companion addons integrate. Everything else lives in `ns`.
_G.ForeverPath = ns
