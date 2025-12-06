# Spine Love2D Runtime

A complete Spine skeletal animation runtime for Love2D (LÖVE), implementing the Spine animation system with efficient rendering and comprehensive feature support.

## Features

- **Complete Spine Runtime**: Full implementation of Spine's animation system (Spine 4.2.x compatible).
- **Love2D Integration**: Native Love2D graphics API integration using Mesh.
- **Attachments**: Supports Region, Mesh, BoundingBox, and Path attachments.
- **Animation**: Timeline-based animations with mixing, blending, and events.
- **Constraints**: IK, Transform,Path constraints and Physics constraints.
- **Skins**: Runtime skin switching.
- **Performance**: Optimized rendering with automatic batching.

## Installation

1. Copy the `spine` folder and `spine-love2d.lua` file to your Love2D project directory.
2. Require the module in your code:

```lua
local spine = require "spine-love2d"
```

## Quick Start

The runtime provides a high-level API to easily load and render Spine skeletons.

```lua
local spine = require "spine-love2d"

local instance

function love.load()
    -- Load the skeleton and atlas
    -- Returns a table with { skeleton, animationState, renderer, ... }
    -- The third argument is scale (optional, default 1)
    instance = spine.loadSkeleton("assets/spineboy/spineboy.json", "assets/spineboy/spineboy.atlas", 0.5)
    
    -- Set position
    instance.skeleton.x = 400
    instance.skeleton.y = 300

    -- Set animation
    if instance.animationState then
        instance.animationState:setAnimation(0, "walk", true)
    end
end

function love.update(dt)
    -- Update animation and skeleton transforms
    spine.update(instance, dt)
end

function love.draw()
    -- Draw the skeleton
    spine.draw(instance)
end
```

## Advanced Usage

For more control, you can access the core classes directly.

```lua
local spine = require "spine-love2d"

local skeleton, animationState, renderer

function love.load()
    -- 1. Load Atlas
    local atlas = spine.TextureAtlas.new()
    atlas:loadAtlasFile(love.filesystem.read("assets/hero.atlas"), "assets")

    -- 2. Load Skeleton Data
    -- Create an attachment loader for the atlas
    local attachmentLoader = spine.atlas.AtlasAttachmentLoader.new(atlas)
    
    -- Load JSON data
    local json = spine.utils.jsonDecode(love.filesystem.read("assets/hero.json"))
    
    -- Create SkeletonData with the loader
    local skeletonData = spine.SkeletonData.new(nil, 1) -- 2nd arg is scale
    skeletonData:loadFromJson(json, attachmentLoader)

    -- 3. Create Skeleton
    skeleton = spine.Skeleton.new(skeletonData)
    skeleton:setToSetupPose()
    skeleton.x, skeleton.y = 400, 300

    -- 4. Create Animation State
    local animationStateData = spine.AnimationStateData.new(skeletonData)
    animationState = spine.AnimationState.new(animationStateData)
    animationState:setAnimation(0, "walk", true)

    -- 5. Create Renderer
    renderer = spine.SkeletonRenderer.new()
    renderer:setDebug(false) -- Toggle debug rendering
end

function love.update(dt)
    animationState:update(dt)
    animationState:apply(skeleton)
    skeleton:updateWorldTransform()
end

function love.draw()
    renderer:draw(skeleton)
end
```

## Project Structure

- `spine-love2d.lua`: Main entry point and high-level API.
- `spine/`: Core runtime modules (animation, data, skeleton, rendering, etc.).
- `examples/`: Example projects showing usage.

## Requirements

- Love2D 11.3 or higher
- Spine 4.2.x compatible JSON exports

## License

This runtime is provided for use with Spine animations. Please ensure you have the appropriate licenses for the Spine software and any Spine assets you use.
