# Developing Omarchy One App Per Workspace

This repository contains a third-party service and bar-widget plugin for the
Omarchy 4 Quickshell shell. It is not a standalone Quickshell application.

## Requirements

- Omarchy 4 with the Quickshell bar
- Hyprland
- GJS for the model tests

## Validate

Run the local checks from the repository root:

```bash
omarchy plugin validate .
./test/one-app-per-workspace-test.sh
qmllint -I "$OMARCHY_PATH/shell" Service.qml
qmllint -I "$OMARCHY_PATH/shell" Widget.qml
```

## Local Testing

The scripts under `scripts/` are local development helpers. Omarchy does not
run them during normal plugin installation, updates, or removal.

Install the current working tree:

```bash
./scripts/dev-install.sh
```

The development installer copies the runtime files to
`~/.config/omarchy/plugins/ericvrp.one-app-per-workspace`, adds the widget to
the left bar section, and restarts the Omarchy shell. It creates a timestamped
backup before changing an existing shell configuration. It does not edit
Hyprland files or remove the previous implementation.

Remove the local development installation with:

```bash
./scripts/dev-uninstall.sh
```

Pass `--no-restart` to either helper when testing configuration changes without
restarting the live shell.

## Runtime Notes

The service listens to Hyprland's `openwindow` and `closewindow` IPC events. It
waits briefly for Quickshell's Hyprland object model to settle before acting on
an event. The service dispatches standard Hyprland workspace commands when the
compositor uses its regular configuration provider. When Hyprland reports Lua
configuration mode, it uses `hyprctl repl` with the same `hl.dsp` helpers as the
existing Omarchy bindings; it does not depend on Lua layout helpers.

The off state is represented by:

```text
~/.local/state/omarchy/toggles/one-app-per-workspace-off
```

No marker means enabled. The marker is created and removed by the bar icon;
the service reads it when the shell starts and watches the existing toggle
directory for later changes.
