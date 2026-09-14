# Security Policy

## Scope

Spaceview is a read-mostly overlay: it renders Hyprland's workspaces and windows
and asks Hyprland to focus or move them. Reports involving command or argument
injection into Hyprland dispatches, a window left stranded on the hidden parking
workspace, or a keyboard grab that outlives the overlay are security-sensitive.

## Design invariants

Changes should preserve these invariants:

- No bundled binaries, helper scripts, or `sudo` / `pkexec` / `systemctl` use.
- No network access, no file reads or writes outside the shell's own state.
- Never spawn a process; the only side channel is Quickshell's
  `Hyprland.dispatch`.
- Every window address is validated against `^(0x)?[0-9a-fA-F]+$` and normalized
  to a `0x` prefix before it is interpolated into a dispatch. An address that
  fails the check is dropped, never dispatched.
- Only workspace ids `1`-`10` are ever dispatched, plus the plugin's own
  `special:spaceview-move` parking workspace.
- A window parked for repositioning is always brought back: on the timer, when
  another reposition starts, when the overlay closes, and — as a safety net for
  a session that was cut short — when it next opens.
- Keyboard focus is exclusive only while the overlay is open; closing it always
  releases the layer surface.
- Never write to the user's Hyprland or Omarchy configuration. Gesture and
  keybinding setup stays documented in the README for the user to apply.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when
available.
