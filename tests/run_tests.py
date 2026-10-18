"""Runs the ForeverPath Lua test suite without a WoW client.

Uses the `lupa` package (pip install lupa) and prefers its Lua 5.1 runtime,
the same Lua version World of Warcraft embeds.
"""
import os
import sys


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
