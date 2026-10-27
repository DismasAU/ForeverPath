"""Runs the ForeverPath Lua test suite without a WoW client.

Uses the `lupa` package (pip install lupa) and prefers its Lua 5.1 runtime,
the same Lua version World of Warcraft embeds.
"""
import os
import re
import sys


def unlisted_specs(root: str) -> tuple[list[str], list[str]]:
    """Spec files tests/spec_list.lua does not name, and names it lists that have no file."""
    spec_dir = os.path.join(root, "tests", "spec")
    on_disk = {name[:-4] for name in os.listdir(spec_dir) if name.endswith("_spec.lua")}
    with open(os.path.join(root, "tests", "spec_list.lua"), "r", encoding="utf-8") as handle:
        listed = set(re.findall(r'"(\w+_spec)"', handle.read()))
    return sorted(on_disk - listed), sorted(listed - on_disk)


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    missing, stale = unlisted_specs(root)
    if missing or stale:
        if missing:
            print("Spec files not in tests/spec_list.lua (they would never run): " + ", ".join(missing))
        if stale:
            print("tests/spec_list.lua names specs with no file: " + ", ".join(stale))
        return 1
    try:
        import lupa.lua51 as lupa_mod  # type: ignore
    except ImportError:
        try:
            import lupa as lupa_mod  # type: ignore
        except ImportError:
            print("The 'lupa' package is required: python -m pip install lupa")
            return 2
    runtime = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    globals_table = runtime.globals()
    globals_table.FP_TEST_ROOT = root.replace("\\", "/")
    globals_table.FP_TEST_EMBEDDED = True
    runner_path = os.path.join(root, "tests", "runner.lua")
    with open(runner_path, "r", encoding="utf-8") as handle:
        source = handle.read()
    failures = runtime.execute(source)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
