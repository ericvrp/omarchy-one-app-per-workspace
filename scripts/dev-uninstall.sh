#!/bin/bash

# Local development helper. Native Omarchy plugin removals do not run this script.
set -euo pipefail

restart=true
if [[ ${1:-} == "--no-restart" ]]; then
  restart=false
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--no-restart]" >&2
  exit 2
fi

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
plugin_id="ericvrp.one-app-per-workspace"
plugin_dir="$config_home/omarchy/plugins/$plugin_id"
shell_config="$config_home/omarchy/shell.json"

if [[ -f $shell_config ]]; then
python3 - "$shell_config" "$plugin_id" <<'PY'
import json
import os
import shutil
import sys
import tempfile
import time

path = sys.argv[1]
plugin_id = sys.argv[2]
with open(path, encoding="utf-8") as handle:
    config = json.load(handle)

changed = False
bar = config.get("bar", {})
layout = bar.get("layout", {}) if isinstance(bar, dict) else {}
for section in ("left", "center", "right"):
    entries = layout.get(section, []) if isinstance(layout, dict) else []
    if not isinstance(entries, list):
        continue
    filtered = [
        entry for entry in entries
        if not (isinstance(entry, dict) and entry.get("id") == plugin_id)
    ]
    if len(filtered) != len(entries):
        layout[section] = filtered
        changed = True

plugins = config.get("plugins", [])
if isinstance(plugins, list):
    filtered = [
        entry for entry in plugins
        if not (isinstance(entry, dict) and entry.get("id") == plugin_id)
    ]
    if len(filtered) != len(plugins):
        config["plugins"] = filtered
        changed = True

if changed:
    backup = f"{path}.bak.{time.time_ns()}"
    shutil.copy2(path, backup)
    directory = path.rsplit("/", 1)[0]
    descriptor, temporary = tempfile.mkstemp(dir=directory, prefix="shell.json.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=2)
            handle.write("\n")
        shutil.copymode(path, temporary)
        shutil.move(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    print(f"Disabled {plugin_id}; backup: {backup}")
else:
    print(f"{plugin_id} is already disabled")
PY
fi

rm -rf "$plugin_dir"

if $restart; then
  command -v omarchy >/dev/null || { echo "omarchy is required to restart the shell" >&2; exit 1; }
  omarchy restart shell
fi

echo "Uninstalled local development build"
