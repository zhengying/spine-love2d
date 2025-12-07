-- Spine Love2D Runtime - Basic Usage Example
-- Demonstrates how to load and render a Spine animation
-- This is the main.lua file for the basic usage example

-- Add parent directory to package path so we can require spine-love2d
package.path = package.path .. ";../../?.lua"
local spine = require("spine-love2d")

-- Global variables for the demo
local skeleton = nil
local animationState = nil
local renderer = nil
local atlas = nil

function love.load()
    -- Set up the window
    love.window.setTitle("Spine Love2D Runtime - Basic Usage Example")
    love.window.setMode(800, 600)
    
    -- Load atlas (texture atlas)
    print("Loading atlas...")
    local atlasText = love.filesystem.read("assets/spineboy/spineboy.atlas")
    if not atlasText then
        print("ERROR: Could not load atlas file")
        return
    end
    
    atlas = spine.atlas.Atlas.new()
    local success, err = atlas:loadAtlasFile(atlasText, "assets/spineboy")
    if not success then
        print("ERROR: Failed to load atlas:", err)
        return
    end
    print("Atlas loaded successfully, pages:", #atlas.pages)
    print("Atlas regions:", #atlas.regions)
    
    -- Create attachment loader
    local attachmentLoader = spine.atlas.AtlasAttachmentLoader.new(atlas)
    
    -- Load skeleton data
    print("Loading skeleton data...")
    local skeletonJsonText = love.filesystem.read("assets/spineboy/spineboy.json")
    if not skeletonJsonText then
        print("ERROR: Could not load skeleton JSON")
        return
    end
    
    local skeletonJson, decodeErr = spine.utils.jsonDecode(skeletonJsonText)
    if not skeletonJson then
        print("ERROR: Failed to parse JSON:", decodeErr)
        return
    end
    
    local skeletonData = spine.SkeletonData.new()
    local loadSuccess, loadErr = pcall(function()
        skeletonData:loadFromJson(skeletonJson, attachmentLoader)
    end)
    
    if not loadSuccess then
        print("ERROR: Failed to parse skeleton JSON:", loadErr)
        return
    end
    
    print("Skeleton data loaded successfully")
    print("Bones:", #skeletonData.bones)
    print("Slots:", #skeletonData.slots)
    print("Animations:", skeletonData.animations and "available" or "none")
    
    -- Create skeleton instance
    skeleton = spine.skeleton.Skeleton.new(skeletonData)
    skeleton:setToSetupPose()
    skeleton:updateWorldTransform()
    
    -- Create animation state
    local animationStateData = spine.data.AnimationStateData.new(skeletonData)
    animationState = spine.animation.AnimationState.new(animationStateData)
    
    -- Set initial animation
    animationState:setAnimation(0, "walk", true)
    
    -- Create renderer
    renderer = spine.rendering.SkeletonRenderer.new()
    
    -- Set skeleton position (will be handled by translate in draw)
    skeleton.x = 0
    skeleton.y = 0
    
    print("Basic usage demo loaded successfully!")
    print("Press SPACE to cycle through animations")
    print("Press D to toggle debug rendering")
end

function love.update(dt)
    -- Update animation
    animationState:update(dt)
    animationState:apply(skeleton)
    
    -- Update skeleton
    skeleton:updateWorldTransform()
end

function love.draw()
    -- Clear screen
    love.graphics.clear(0.2, 0.2, 0.2)
    
    -- Draw skeleton
    local instance = {
        skeleton = skeleton,
        renderer = renderer.renderer
    }
    spine.draw(instance, 400, 500)
    
    if renderer.debug then
        spine.drawDebug(instance, 400, 500)
    end
    
    -- Draw UI
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Spine Love2D Runtime Demo", 10, 10)
    love.graphics.print("Animation: walk (looping)", 10, 30)
    love.graphics.print("Press SPACE to change animation", 10, 50)
    love.graphics.print("Press D to toggle debug rendering", 10, 70)
end

function love.keypressed(key)
    if key == "space" then
        -- Cycle through animations
        local animations = {"walk", "run", "jump", "idle"}
        local currentAnim = animationState.tracks[0] and animationState.tracks[0].animation.name or "walk"
        
        local nextIndex = 1
        for i, anim in ipairs(animations) do
            if anim == currentAnim then
                nextIndex = i + 1
                if nextIndex > #animations then
                    nextIndex = 1
                end
                break
            end
        end
        
        animationState:setAnimation(0, animations[nextIndex], true)
        
    elseif key == "d" then
        -- Toggle debug rendering
        renderer:setDebug(not renderer.debug)
        
    elseif key == "escape" then
        love.event.quit()
    end
end
