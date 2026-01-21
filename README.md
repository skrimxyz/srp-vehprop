# SRP Vehicle Props

A powerful in-game vehicle prop attachment system for FiveM servers running the Mythic Framework.

## Features

- **Interactive 3D Gizmo** - Visual position and rotation controls with real-time feedback
- **Freecam Mode** - Hold SHIFT to freely move the camera around the vehicle (WASD + Q/E)
- **Drag Controls** - Click and drag on axis handles for precise adjustments
- **JSON Export** - Save prop configurations to JSON files for easy sharing or backup
- **Clean UI** - Modern terminal-style interface built with React

## Controls

| Key | Action |
|-----|--------|
| `F7` | Open/Close prop menu |
| `SHIFT` | Hold for freecam mode |
| `WASD` | Move camera (in freecam) |
| `Q/E` | Camera up/down (in freecam) |
| `ESC` | Close menu |

## Usage

1. Enter a vehicle
2. Press `F7` to open the prop menu
3. Enter a prop model name (e.g., `prop_lightbar_01`)
4. Use the gizmo controls to position and rotate the prop
5. Export your configuration as JSON when finished

## Dependencies

- [srp-base](https://github.com/your-org/srp-base) (Mythic Framework fork)
- [srp-pwnzor](https://github.com/your-org/srp-pwnzor) (Anti-cheat)

## Installation

1. Place `srp-vehprop` in your `resources/[mythic]/` folder
2. Add `ensure srp-vehprop` to your server.cfg
3. Build the UI: `cd ui && npm install && npm run build`

## Configuration

Edit `config.lua` to customize:

```lua
Config.OpenKey = "F7"           -- Keybind to open menu
Config.MaxPropsPerVehicle = 20  -- Maximum props per vehicle
Config.MoveStep = 0.01          -- Position adjustment step
Config.RotateStep = 1.0         -- Rotation adjustment step (degrees)
```

## License

MIT License - Feel free to use and modify.
