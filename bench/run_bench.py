#!/usr/bin/env python3
"""Run the Aicore synthetic benchmark via lupa (LuaJIT runtime).

Runs bench.lua, which loads the REAL core Lua (server/player.lua,
server/storage.lua) under stubbed FiveM globals. No lua binary needed.
"""
import os
import sys
from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.environ.get("AICORE_CORE", os.path.abspath(os.path.join(HERE, "..", "resources", "aicore")))

lua = LuaRuntime()
lua.execute("arg = {%r}" % CORE)
with open(os.path.join(HERE, "bench.lua")) as f:
    lua.execute(f.read())
