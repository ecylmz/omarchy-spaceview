# Spaceview

A fullscreen workspace overview for [Omarchy](https://omarchy.org/): your ten
workspaces side by side, every window a live preview. It runs inside the
`omarchy-shell` you already have — no compositor plugin, no compiling, nothing
to rebuild when Hyprland updates.

Open it with a three-finger swipe, a keyboard shortcut, or both.

![Spaceview showing five workspaces with live window previews](preview.png)

## Features

- Each card is a true miniature of the workspace: windows are placed from
  Hyprland's own geometry, so a vertical split reads as a vertical split
- Live Wayland window previews, falling back to the app icon while a window has
  no frame yet
- Click a window to focus it, click a workspace to switch to it
- Drag a window between workspaces, or within one to rearrange it: drop it on
  the left, right, top, or bottom half of another window to land it exactly
  there, with the landing zone highlighted as you drag (dwindle only)
- Keyboard driven throughout: arrows or `hjkl`, `Enter` to switch, `1`–`9`/`0`
  to jump, `Esc` to close
- Workspaces 1–10, with 1–5 always shown and a trailing `+` card for the next
  empty one
- Follows your Omarchy theme, since every color is a theme token

## Requirements

- Omarchy 4 (Quattro) with `omarchy-shell`
- Hyprland with Omarchy 4's Lua configuration format
- Quickshell 0.3+ with the Wayland screencopy module (ships with Omarchy)

No external binaries, services, or network access.

## Install

```bash
omarchy plugin add https://github.com/ecylmz/omarchy-spaceview.git --enable --yes
```

## Open it

Every way of opening Spaceview goes through the same shell IPC call, so you can
bind it to whatever you like:

```bash
omarchy-shell shell toggle ecylmz.spaceview   # open if closed, close if open
omarchy-shell shell summon ecylmz.spaceview   # open
omarchy-shell shell hide ecylmz.spaceview     # close
```

### With a keyboard shortcut

Add this to `~/.config/hypr/bindings.lua`, then run `hyprctl reload`:

```lua
o.bind("SUPER + CTRL + G", "Workspace overview", "omarchy-shell shell toggle ecylmz.spaceview")
```

Any free combination works — `omarchy menu keybindings --print` lists the ones
already taken. To claim a key Omarchy uses by default, unbind it first:

```lua
hl.unbind("SUPER + G") -- Omarchy binds this to "Toggle window grouping"
o.bind("SUPER + G", "Workspace overview", "omarchy-shell shell toggle ecylmz.spaceview")
```

### With a trackpad gesture

Three fingers up opens Spaceview, three fingers down closes it. Add this to
`~/.config/hypr/input.lua`, then run `hyprctl reload`:

```lua
-- The table form fires on `start`, i.e. as soon as the swipe is recognized;
-- a bare `action = function() ... end` would only fire once your fingers lift.
local spaceview = function(command)
  return {
    start = function()
      hl.exec_cmd("omarchy-shell shell " .. command .. " ecylmz.spaceview")
    end,
    update = function() end,
    finish = function() end,
  }
end

hl.gesture({ fingers = 3, direction = "up", action = spaceview("summon") })
hl.gesture({ fingers = 3, direction = "down", action = spaceview("hide") })
```

## Keys

| Key | Action |
| --- | --- |
| Arrows / `h` `j` `k` `l` | Move between workspace cards |
| `Enter` / `Space` | Switch to the selected workspace |
| `1`–`9`, `0` | Switch to that workspace directly |
| `Esc` | Close |

## Remove

```bash
omarchy plugin remove ecylmz.spaceview --yes
```

Then delete the binding or the `hl.gesture(...)` block you added and run
`hyprctl reload`.

## Security

Omarchy plugins run unsandboxed with your user permissions, so review the source
before installing — it is three QML files and a manifest.

Spaceview ships no binaries and no helper scripts, spawns no processes, and
opens no sockets. It talks to Hyprland only through Quickshell's
`Hyprland.dispatch`, validating every window address against
`^(0x)?[0-9a-fA-F]+$` first, and it never writes to your Hyprland or Omarchy
configuration — the binding and gesture above are yours to add.
[SECURITY.md](SECURITY.md) lists the invariants a change has to keep.

## Credits

The grid, card, and preview layout started from the workspace overview proposed
in [omacom/omarchy#6611](https://github.com/omacom/omarchy/pull/6611) by
[@sanjyay](https://github.com/sanjyay), which was closed rather than merged.
That code is MIT licensed as part of Omarchy. Spaceview reworks it into a
standalone third-party plugin: Lua-form Hyprland dispatches, gesture-driven
summoning, a reworked focus hierarchy, and a deeper scrim for fullscreen use.

## License

MIT — see [LICENSE](LICENSE).
