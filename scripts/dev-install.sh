#!/bin/bash

# Local development helper. Native Omarchy plugin installs do not run this script.
set -euo pipefail

restart=true
if [[ ${1:-} == "--no-restart" ]]; then
  restart=false
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--no-restart]" >&2
  exit 2
fi

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
plugin_id="ericvrp.one-app-per-workspace"
plugin_dir="$config_home/omarchy/plugins/$plugin_id"
shell_config="$config_home/omarchy/shell.json"
defaults="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"

mkdir -p "$plugin_dir" "$(dirname -- "$shell_config")"

if [[ $repo_dir != "$plugin_dir" ]]; then
  install -m 0644 "$repo_dir/manifest.json" "$plugin_dir/manifest.json"
  install -m 0644 "$repo_dir/Service.qml" "$plugin_dir/Service.qml"
  install -m 0644 "$repo_dir/Widget.qml" "$plugin_dir/Widget.qml"
  install -m 0644 "$repo_dir/OneAppPerWorkspaceModel.js" "$plugin_dir/OneAppPerWorkspaceModel.js"
  install -m 0644 "$repo_dir/OneAppPerWorkspaceEarlyHook.lua" "$plugin_dir/OneAppPerWorkspaceEarlyHook.lua"
fi

if [[ ! -f $shell_config ]]; then
  if [[ ! -f $defaults ]]; then
    echo "Cannot find an Omarchy shell config at $shell_config or $defaults" >&2
    exit 1
  fi
  cp "$defaults" "$shell_config"
fi

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

bar = config.setdefault("bar", {})
layout = bar.setdefault("layout", {})
for section in ("left", "center", "right"):
    if not isinstance(layout.get(section), list):
        layout[section] = []

found = False
changed = False
for section in ("left", "center", "right"):
    entries = layout[section]
    filtered = []
    for entry in entries:
        if isinstance(entry, dict) and entry.get("id") == plugin_id:
            if found:
                changed = True
                continue
            found = True
        filtered.append(entry)
    if filtered != entries:
        layout[section] = filtered

if not found:
    layout["left"].append({"id": plugin_id})
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
    print(f"Enabled {plugin_id}; backup: {backup}")
else:
    print(f"{plugin_id} is already enabled")
PY

if $restart; then
  command -v omarchy >/dev/null || { echo "omarchy is required to restart the shell" >&2; exit 1; }
  omarchy restart shell
fi

echo "Installed local development build to $plugin_dir"
