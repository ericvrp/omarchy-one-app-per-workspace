#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

gjs "$ROOT/test/one-app-per-workspace-test.js"
luac -p "$ROOT/OneAppPerWorkspaceEarlyHook.lua"
lua "$ROOT/test/one-app-per-workspace-early-hook-test.lua" "$ROOT/OneAppPerWorkspaceEarlyHook.lua"
