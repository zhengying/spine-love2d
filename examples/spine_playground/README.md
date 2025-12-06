# Spine Playground - Interactive Animation Viewer

An interactive demo for loading and playing Spine animations with a visual UI. **Simply drag & drop your Spine files to play any character!**

## Quick Start

### Method 1: Drag & Drop (Recommended)
1. Run the demo: `cd examples/spine_playground && love .`
2. Drag your Spine export files (.json, .atlas, .png) into the window
3. Watch your character load automatically!
4. Click any animation to play it

### Method 2: Manual Configuration
Edit `main.lua` to change the default asset (see "Loading Different Assets" below)

## Features

- 📋 **Animation List**: See all available animations from any Spine export
- 🖱️ **Click to Play**: Simply click on an animation name to play it
- ⌨️ **Keyboard Shortcuts**: Quick access with number keys 1-9
- 🎮 **Interactive Controls**: Move, scale, and debug your skeleton
- 🎨 **Clean UI**: Modern interface with panels and visual feedback

## How to Run

```bash
cd examples/spine_playground
love .
```

## Controls

### Animation Selection
- **Click** on any animation in the list to play it
- **1-9**: Quick select animations by number
- **Up/Down Arrow**: Navigate through animation list

### Skeleton Manipulation
- **Arrow Keys**: Move the skeleton around
- **+/-**: Zoom in/out
- **R**: Reset position and scale

### View Options
- **D**: Toggle debug rendering (shows bones, slots, attachments)
- **H**: Toggle help panel
- **ESC**: Exit

### Mouse
- **Scroll Wheel**: Scroll through animation list (when hovering over it)
- **Click**: Select animation to play

## Loading Different Assets

To load a different Spine character, edit `main.lua` and change:

```lua
local CONFIG = {
    currentAsset = "spineboy",  -- Change to "coin" or add your own
    ...
}
```

### Adding Your Own Assets

1. Add your Spine export files to `examples/assets/your_character/`
2. Edit the `CONFIG.assets` table in `main.lua`:

```lua
assets = {
    your_character = {
        atlas = "../assets/your_character/file.atlas",
        json = "../assets/your_character/file.json",
        scale = 0.5,
        x = 400,
        y = 400
    }
}
```

3. Change `currentAsset = "your_character"`

## UI Layout

- **Left Panel**: Animation list with total count
  - Green highlight = currently playing
  - Gray highlight = hover state
  
- **Right Panel**: Information and controls
  - Current asset name
  - Currently playing animation
  - FPS counter
  - Scale value
  - Controls help (press H to toggle)

## Animation Features

- **Auto-loop Detection**: Animations automatically loop unless they contain keywords like "death", "jump", or "shoot"
- **Smooth Transitions**: All animations have smooth mixing/blending between them
- **Sorted List**: Animations are alphabetically sorted for easy browsing

## Default Assets

The playground comes with two demo assets:

1. **Spineboy** (default): Character with 7 animations
2. **Coin**: Spinning coin with animation effect

Switch between them by editing `currentAsset` in the config.
