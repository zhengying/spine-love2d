-- Spine Love2D Runtime - Interactive Playground
-- Load any Spine export files and play animations interactively

-- Add parent directories to package path so we can require spine-love2d
package.path = package.path .. ";../../?.lua"
local spine = require("spine-love2d")

-- Configuration: Change these to load different Spine characters
local CONFIG = {
    -- Current asset to load (options: "spineboy", "coin", "windmill", "mix_and_match")
    currentAsset = "powerup",
    
    -- Asset paths
    assets = {
        mix_and_match = {
            atlas = "assets/mix-and-match/mix-and-match-pro.atlas",
            json = "assets/mix-and-match/mix-and-match-pro.json",
            scale = 0.5,
            x = 400,
            y = 500
        },
        spineboy_pro = {
            atlas = "assets/spineboy-pro/spineboy-pro.atlas",
            json = "assets/spineboy-pro/spineboy-pro.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        spineboy_ess = {
            atlas = "assets/spineboy_ess/spineboy.atlas",
            json = "assets/spineboy_ess/spineboy-ess.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        stretchyman = {
            atlas = "assets/stretchyman/stretchyman-pro.atlas",
            json = "assets/stretchyman/stretchyman-pro.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        
        coin = {
            atlas = "assets/coin/coin.atlas",
            json = "assets/coin/coin-pro.json",
            scale = 0.3,
            x = 400,
            y = 400
        },
        alien = {
            atlas = "assets/alien/alien.atlas",
            json = "assets/alien/alien.json",
            scale = 0.3,
            x = 400,
            y = 400
        },
        alien_pro = {
            atlas = "assets/alien-pro/alien-pro.atlas",
            json = "assets/alien-pro/alien-pro.json",
            scale = 0.3,
            x = 400,
            y = 400
        },
        windmill = {
            atlas = "assets/windmill/windmill-pma.atlas",
            json = "assets/windmill/windmill-ess.json",
            scale = 0.5,
            x = 500,
            y = 500
        },  
        tank = {
            atlas = "assets/tank/tank-pro.atlas",
            json = "assets/tank/tank-pro.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        sack = {
            atlas = "assets/sack/sack.atlas",
            json = "assets/sack/sack-pro.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        cloud_pot = {
            atlas = "assets/cloud-pot/cloud-pot.atlas",
            json = "assets/cloud-pot/cloud-pot.json",
            scale = 0.5,
            x = 400,
            y = 550
        },
        powerup = {
            atlas = "assets/powerup/powerup.atlas",
            json = "assets/powerup/powerup-pro.json",
            scale = 1,
            x = 400,
            y = 550
        },
    }
}

-- Demo state
local playground = {
    skeleton = nil,
    animationState = nil,
    renderer = nil,
    atlas = nil,
    skeletonData = nil,
    
    -- Animation list
    animations = {},
    currentAnimation = nil,
    currentAnimationIndex = 1,
    
    -- UI state
    showDebug = false,
    showHelp = true,
    loadError = nil,
    
    -- Performance tracking
    fps = 0,
    frameTime = 0,
    
    -- Visual settings
    backgroundColor = {0.15, 0.15, 0.25},
    skeletonX = 400,
    skeletonY = 400,
    scale = 0.5,
    
    -- UI layout
    animationListWidth = 250,
    animationListX = 10,
    animationListY = 10,
    animationItemHeight = 30,
    scrollOffset = 0,
    maxVisibleItems = 15,
    
    -- Mouse interaction
    hoveredAnimationIndex = nil,
    
    -- Drag-and-drop state
    droppedFiles = {},
    isDragging = false,
    currentAssetName = nil
}

function love.load()
    -- Set up window
    love.window.setTitle("Spine Playground - Interactive Animation Viewer")
    love.window.setMode(1024, 768)
    love.graphics.setBackgroundColor(playground.backgroundColor)
    
    -- Update CONFIG to center assets on screen
    local centerX = love.graphics.getWidth() / 2
    local centerY = love.graphics.getHeight() * 0.8
    for _, asset in pairs(CONFIG.assets) do
        asset.x = centerX
        asset.y = centerY
    end
    
    -- Load current asset
    local success, err = loadSpineAsset(CONFIG.currentAsset)
    if not success then
        print("Failed to load Spine assets: " .. (err or "unknown error"))
        playground.loadError = err or "Failed to load assets"
    end
    
    print("Spine Playground loaded successfully!")
    print("Press H for help or drag Spine files into window")
    print("Click on animations to play them")
    if #playground.animations > 0 then
        print("Found " .. #playground.animations .. " animations")
    end
end

function loadSpineAsset(assetName, customPaths, fileContents)
    local asset
    local atlasText, skeletonJson
    
    if fileContents then
        -- Load from provided file contents (for drag-and-drop)
        atlasText = fileContents.atlas
        skeletonJson = fileContents.json
        asset = customPaths or {scale = 0.5, x = 400, y = 400}
    elseif customPaths then
        -- Load from custom paths
        asset = customPaths
        atlasText = love.filesystem.read(asset.atlas)
        if not atlasText then
            return nil, "Could not load atlas file: " .. asset.atlas
        end
        skeletonJson = love.filesystem.read(asset.json)
        if not skeletonJson then
            return nil, "Could not load skeleton JSON: " .. asset.json
        end
    else
        -- Load from CONFIG
        asset = CONFIG.assets[assetName]
        if not asset then
            return nil, "Unknown asset: " .. assetName
        end
        atlasText = love.filesystem.read(asset.atlas)
        if not atlasText then
            return nil, "Could not load atlas file: " .. asset.atlas
        end
        skeletonJson = love.filesystem.read(asset.json)
        if not skeletonJson then
            return nil, "Could not load skeleton JSON: " .. asset.json
        end
    end
    
    playground.currentAssetName = assetName
    print("Loading asset: " .. (assetName or "custom"))
    
    
    -- Create Atlas from text
    playground.atlas = spine.atlas.Atlas.new()
    local basePath = ""
    if asset.atlas then
        basePath = string.match(asset.atlas, "(.*/)[^/]*$") or ""
    end
    local atlasSuccess, atlasErr = playground.atlas:loadAtlasFile(atlasText, basePath)
    if not atlasSuccess then
        return nil, "Failed to load atlas: " .. (atlasErr or "unknown error")
    end
    
    -- Create attachment loader
    local attachmentLoader = spine.atlas.AtlasAttachmentLoader.new(playground.atlas)
    
    -- Create skeleton data
    playground.skeletonData = spine.SkeletonData.new()
    local loadSuccess, loadErr = pcall(function()
        local jsonTable, decodeErr = spine.utils.jsonDecode(skeletonJson)
        if not jsonTable then
            error("Failed to decode skeleton JSON: " .. tostring(decodeErr))
        end
        playground.skeletonData:loadFromJson(jsonTable, attachmentLoader)
    end)
    
    if not loadSuccess then
        return nil, "Failed to parse skeleton JSON: " .. (loadErr or "unknown error")
    end
    
    -- Extract animation names
    playground.animations = {}
    if playground.skeletonData.animations then
        for name, _ in pairs(playground.skeletonData.animations) do
            table.insert(playground.animations, name)
        end
        table.sort(playground.animations)
    end
    
    if #playground.animations == 0 then
        return nil, "No animations found in skeleton data"
    end
    
    -- Create skeleton instance
    playground.skeleton = spine.skeleton.Skeleton.new(playground.skeletonData)
    
    -- Apply mix and match if applicable
    if assetName == "mix_and_match" then
        setupMixAndMatch(playground.skeleton, playground.skeletonData)
    end
    
    playground.skeleton:setToSetupPose()
    playground.skeleton:updateWorldTransform()
    
    -- Create animation state
    local animationStateData = spine.data.AnimationStateData.new(playground.skeletonData)
    
    -- Configure animation mixing for smooth transitions (all to all)
    for i, anim1 in ipairs(playground.animations) do
        for j, anim2 in ipairs(playground.animations) do
            if i ~= j then
                animationStateData:setMix(anim1, anim2, 0.2)
            end
        end
    end
    
    playground.animationState = spine.animation.AnimationState.new(animationStateData)
    
    -- Create renderer
    playground.renderer = spine.rendering.SkeletonRenderer.new()
    
    -- Set initial position and scale
    -- Force center of screen (X) and lower ground (Y)
    playground.skeletonX = love.graphics.getWidth() / 2
    playground.skeletonY = love.graphics.getHeight() * 0.8
    playground.scale = asset.scale
    
    print("Skeleton positioned at: " .. playground.skeletonX .. ", " .. playground.skeletonY)
    print("Window dimensions: " .. love.graphics.getWidth() .. "x" .. love.graphics.getHeight())
    
    -- Play first animation by default
    if #playground.animations > 0 then
        setAnimation(1)
    end
    
    return true
end

function setAnimation(index)
    if index < 1 or index > #playground.animations then
        return
    end
    
    playground.currentAnimationIndex = index
    playground.currentAnimation = playground.animations[index]
    
    -- Determine if animation should loop (non-action animations loop)
    local shouldLoop = not string.match(playground.currentAnimation:lower(), "death") 
                   and not string.match(playground.currentAnimation:lower(), "jump")
                   and not string.match(playground.currentAnimation:lower(), "shoot")
    
    playground.animationState:setAnimation(0, playground.currentAnimation, shouldLoop)
    print("Playing animation: " .. playground.currentAnimation .. (shouldLoop and " (looping)" or ""))
end

function love.update(dt)
    -- Skip updates if assets failed to load
    if playground.loadError then
        return
    end
    
    -- Update performance tracking
    playground.fps = love.timer.getFPS()
    playground.frameTime = dt
    
    -- Update animation
    playground.skeleton:update(dt)
    playground.skeleton:setBonesToSetupPose()
    playground.skeleton:setSlotsToSetupPose()
    playground.skeleton:setConstraintsToSetupPose()
    playground.animationState:update(dt)
    playground.animationState:apply(playground.skeleton)
    
    -- Update skeleton transforms
    playground.skeleton:updateWorldTransform()
    
    -- Update skeleton position
    -- playground.skeleton.x = playground.skeletonX
    -- playground.skeleton.y = playground.skeletonY
    
    -- Handle continuous input
    handleInput(dt)
end

function handleInput(dt)
    -- Movement with arrow keys
    local speed = 200 * dt
    
    if love.keyboard.isDown("left") then
        playground.skeletonX = playground.skeletonX - speed
    end
    if love.keyboard.isDown("right") then
        playground.skeletonX = playground.skeletonX + speed
    end
    if love.keyboard.isDown("up") then
        playground.skeletonY = playground.skeletonY - speed
    end
    if love.keyboard.isDown("down") then
        playground.skeletonY = playground.skeletonY + speed
    end
end

function love.draw()
    -- Show error message if assets failed to load
    if playground.loadError then
        love.graphics.clear(0.1, 0.1, 0.1)
        love.graphics.setColor(1, 0.2, 0.2)
        love.graphics.print("ERROR: Failed to load Spine assets", 50, 50)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(playground.loadError, 50, 80)
        love.graphics.print("Check console for details", 50, 110)
        
        -- Highlight drag-and-drop option
        love.graphics.setColor(0.3, 0.8, 0.3)
        love.graphics.print("✓ Drag & Drop your Spine files here!", 50, 150)
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.print("Drop .json, .atlas, and .png files to load any character", 50, 175)
        return
    end
    
    -- Draw background
    love.graphics.clear(playground.backgroundColor)
    
    -- Draw skeleton
    local instance = {
        skeleton = playground.skeleton,
        renderer = playground.renderer.renderer
    }
    
    spine.draw(instance, playground.skeletonX, playground.skeletonY, playground.scale, -playground.scale)
    
    if playground.showDebug then
        spine.drawDebug(instance, playground.skeletonX, playground.skeletonY, playground.scale, -playground.scale)
    end
    
    -- Draw UI
    drawUI()
end

function drawUI()
    local mouseX, mouseY = love.mouse.getPosition()
    playground.hoveredAnimationIndex = nil
    
    -- Animation list panel
    local listX = playground.animationListX
    local listY = playground.animationListY
    local listWidth = playground.animationListWidth
    local listHeight = math.min(#playground.animations * playground.animationItemHeight + 50, 
                                 playground.maxVisibleItems * playground.animationItemHeight + 50)
    
    -- Panel background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", listX, listY, listWidth, listHeight, 5, 5)
    
    -- Panel header
    love.graphics.setColor(0.2, 0.4, 0.7)
    love.graphics.rectangle("fill", listX, listY, listWidth, 40, 5, 5)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("ANIMATIONS", listX, listY + 10, listWidth, "center")
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.printf(#playground.animations .. " total", listX, listY + 25, listWidth, "center")
    love.graphics.setFont(love.graphics.newFont(14))
    
    -- Animation list items
    local startY = listY + 50
    local visibleStart = playground.scrollOffset
    local visibleEnd = math.min(playground.scrollOffset + playground.maxVisibleItems, #playground.animations)
    
    for i = visibleStart + 1, visibleEnd do
        local itemY = startY + (i - visibleStart - 1) * playground.animationItemHeight
        local anim = playground.animations[i]
        local isCurrent = (i == playground.currentAnimationIndex)
        local isHovered = mouseX >= listX and mouseX <= listX + listWidth and
                         mouseY >= itemY and mouseY <= itemY + playground.animationItemHeight
        
        if isHovered then
            playground.hoveredAnimationIndex = i
        end
        
        -- Item background
        if isCurrent then
            love.graphics.setColor(0.2, 0.6, 0.2, 0.5)
            love.graphics.rectangle("fill", listX + 5, itemY, listWidth - 10, playground.animationItemHeight - 2)
        elseif isHovered then
            love.graphics.setColor(0.3, 0.3, 0.4, 0.5)
            love.graphics.rectangle("fill", listX + 5, itemY, listWidth - 10, playground.animationItemHeight - 2)
        end
        
        -- Item text
        local textColor = isCurrent and {0.3, 1, 0.3} or {0.9, 0.9, 0.9}
        love.graphics.setColor(textColor)
        love.graphics.print(i .. ". " .. anim, listX + 15, itemY + 5)
    end
    
    -- Info panel (top right)
    local infoX = love.graphics.getWidth() - 260
    local infoY = 10
    local infoWidth = 250
    
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", infoX, infoY, infoWidth, playground.showHelp and 350 or 150, 5, 5)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Spine Playground", infoX + 10, infoY + 10)
    love.graphics.print("Asset: " .. (playground.currentAssetName or CONFIG.currentAsset), infoX + 10, infoY + 35)
    love.graphics.print("Playing: " .. (playground.currentAnimation or "none"), infoX + 10, infoY + 60)
    love.graphics.print("FPS: " .. playground.fps, infoX + 10, infoY + 85)
    love.graphics.print("Scale: " .. string.format("%.2f", playground.scale), infoX + 10, infoY + 110)
    
    if playground.showHelp then
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.print("Controls:", infoX + 10, infoY + 140)
        love.graphics.setFont(love.graphics.newFont(12))
        love.graphics.print("Drag files to load!", infoX + 15, infoY + 160)
        love.graphics.print("Click animation to play", infoX + 15, infoY + 180)
        love.graphics.print("1-9: Quick select", infoX + 15, infoY + 200)
        love.graphics.print("Arrows: Move skeleton", infoX + 15, infoY + 220)
        love.graphics.print("+/-: Zoom in/out", infoX + 15, infoY + 240)
        love.graphics.print("D: Debug rendering", infoX + 15, infoY + 260)
        love.graphics.print("R: Reset position", infoX + 15, infoY + 280)
        love.graphics.print("H: Toggle help", infoX + 15, infoY + 300)
        love.graphics.print("ESC: Exit", infoX + 15, infoY + 320)
        love.graphics.setFont(love.graphics.newFont(14))
    else
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("Press H for help", infoX + 10, infoY + 130)
    end
    
    -- Debug indicator
    if playground.showDebug then
        love.graphics.setColor(1, 0.5, 0)
        love.graphics.print("DEBUG MODE", love.graphics.getWidth() / 2 - 50, love.graphics.getHeight() - 30)
    end
end

function love.keypressed(key)
    -- Number keys for quick animation selection
    if key >= "1" and key <= "9" then
        local index = tonumber(key)
        if index <= #playground.animations then
            setAnimation(index)
        end
    end
    
    -- Navigation
    if key == "up" and playground.currentAnimationIndex > 1 then
        setAnimation(playground.currentAnimationIndex - 1)
    end
    if key == "down" and playground.currentAnimationIndex < #playground.animations then
        setAnimation(playground.currentAnimationIndex + 1)
    end
    
    -- Reset position
    if key == "r" then
        playground.skeletonX = love.graphics.getWidth() / 2
        playground.skeletonY = love.graphics.getHeight() * 0.8
        playground.scale = CONFIG.assets[CONFIG.currentAsset].scale or 0.5
        print("Position and scale reset to center")
    end
    
    -- Scaling
    if key == "+" or key == "=" then
        playground.scale = math.min(playground.scale + 0.1, 3.0)
        print("Scale increased: " .. string.format("%.2f", playground.scale))
    end
    if key == "-" or key == "_" then
        playground.scale = math.max(playground.scale - 0.1, 0.1)
        print("Scale decreased: " .. string.format("%.2f", playground.scale))
    end
    
    -- Toggles
    if key == "d" then
        playground.showDebug = not playground.showDebug
        print("Debug rendering: " .. (playground.showDebug and "ON" or "OFF"))
    elseif key == "b" then
        -- Print bone debug info
        if playground.skeleton then
            local debug_bones = require("spine.debug_bones")
            print("\n--- Debug Bone Info ---")
            debug_bones.printBoneHierarchy(playground.skeleton)
            debug_bones.printAllBoneTransforms(playground.skeleton)
        end
    elseif key == "h" then
        playground.showHelp = not playground.showHelp
    elseif key == "y" then
        if playground.skeleton then
            playground.skeleton.flipY = not playground.skeleton.flipY
            playground.skeleton:updateWorldTransform()
            print("Skeleton Flip Y: " .. tostring(playground.skeleton.flipY))
        end
    end
    
    -- Exit
    if key == "escape" then
        love.event.quit()
    end
end

function love.mousepressed(x, y, button)
    if button == 1 and playground.hoveredAnimationIndex then
        setAnimation(playground.hoveredAnimationIndex)
    end
end

function love.wheelmoved(x, y)
    -- Scroll animation list
    local listX = playground.animationListX
    local listWidth = playground.animationListWidth
    local mouseX, mouseY = love.mouse.getPosition()
    
    if mouseX >= listX and mouseX <= listX + listWidth then
        playground.scrollOffset = math.max(0, math.min(
            playground.scrollOffset - y,
            math.max(0, #playground.animations - playground.maxVisibleItems)
        ))
    end
end

function love.resize(w, h)
    print("Window resized to: " .. w .. "x" .. h)
    -- Re-center skeleton on resize
    playground.skeletonX = w / 2
    playground.skeletonY = h * 0.8
end

function love.filedropped(file)
    local filename = file:getFilename()
    local ext = filename:match("%.([^%.]+)$")
    
    print("File dropped: " .. filename)
    
    -- Accept only spine-related files
    if ext == "json" or ext == "atlas" or ext == "png" then
        -- Store the file object (not just filename)
        if not playground.droppedFiles[ext] then
            playground.droppedFiles[ext] = {}
        end
        
        table.insert(playground.droppedFiles[ext], file)
        
        print("Stored " .. ext .. " file: " .. filename)
        
        -- Check if we have at least one atlas and one json (png is optional)
        if playground.droppedFiles.atlas and #playground.droppedFiles.atlas > 0 
           and playground.droppedFiles.json and #playground.droppedFiles.json > 0 then
            
            -- Use the first atlas and first json file objects
            local atlasFileObj = playground.droppedFiles.atlas[1]
            local jsonFileObj = playground.droppedFiles.json[1]
            
            -- Read the file contents directly
            local atlasContent = atlasFileObj:read()
            local jsonContent = jsonFileObj:read()
            
            -- Extract filenames
            local atlasFilename = atlasFileObj:getFilename()
            local jsonFilename = jsonFileObj:getFilename()
            local displayName = atlasFilename:match("([^/\\\\]+)%.atlas$") or jsonFilename:match("([^/\\\\]+)%.json$") or "custom"
            
            -- Create temporary directory for dropped files
            local tempDir = "dropped_files/"
            love.filesystem.createDirectory(tempDir)
            
            -- Write atlas and json to temp directory
            local tempAtlasPath = tempDir .. atlasFilename:match("([^/\\\\]+)$")
            local tempJsonPath = tempDir .. jsonFilename:match("([^/\\\\]+)$")
            
            love.filesystem.write(tempAtlasPath, atlasContent)
            love.filesystem.write(tempJsonPath, jsonContent)
            
            print("Wrote atlas to: " .. tempAtlasPath)
            print("Wrote json to: " .. tempJsonPath)
            
            -- Also write PNG if available
            if playground.droppedFiles.png and #playground.droppedFiles.png > 0 then
                local pngFileObj = playground.droppedFiles.png[1]
                local pngContent = pngFileObj:read()
                local pngFilename = pngFileObj:getFilename()
                local tempPngPath = tempDir .. pngFilename:match("([^/\\\\]+)$")
                love.filesystem.write(tempPngPath, pngContent)
                print("Wrote png to: " .. tempPngPath)
            end
            
            print("Complete set detected!")
            print("  Using atlas: " .. atlasFilename)
            print("  Using json: " .. jsonFilename)
            
            -- Now load from the temporary directory using regular filesystem paths
            local customAsset = {
                atlas = tempAtlasPath,
                json = tempJsonPath,
                scale = 0.5,
                x = love.graphics.getWidth() / 2,
                y = love.graphics.getHeight() * 0.8
            }
            
            -- Load without fileContents parameter, so it reads from filesystem
            local success, err = loadSpineAsset(displayName, customAsset)
            if success then
                playground.loadError = nil
                print("Successfully loaded dropped files!")
                print("Found " .. #playground.animations .. " animations")
                
                -- Clear dropped files after successful load
                playground.droppedFiles = {}
            else
                playground.loadError = "Failed to load dropped files: " .. (err or "unknown error")
                print(playground.loadError)
            end
        else
            -- Show what's missing
            local hasAtlas = playground.droppedFiles.atlas and #playground.droppedFiles.atlas > 0
            local hasJson = playground.droppedFiles.json and #playground.droppedFiles.json > 0
            
            print("Waiting for more files...")
            if not hasAtlas then print("  Missing: .atlas file") end
            if not hasJson then print("  Missing: .json file") end
            if hasAtlas and hasJson then
                print("  Ready to load!")
            end
        end
    else
        print("Ignored file with extension: " .. (ext or "none"))
    end
end

function love.directorydropped(path)
    print("Directory dropped: " .. path)
    print("Please drop individual files (.json, .atlas, .png) instead")
end

function setupMixAndMatch(skeleton, skeletonData)
    print("Applying Mix and Match skins...")
    
    -- Try to load the full skin
    local skinName = "full-skins/girl"
    -- You can also try: "full-skins/boy", "full-skins/girl-blue-cape", "full-skins/girl-spring-dress"
    
    if skeletonData.skins[skinName] then
        print("Setting skin: " .. skinName)
        skeleton:setSkin(skinName)
    else
        print("Error: Skin '" .. skinName .. "' not found!")
        -- List available skins for debugging
        print("Available skins:")
        for name, _ in pairs(skeletonData.skins) do
            print("- " .. name)
        end
        
        -- Fallback to base
        if skeletonData.skins["skin-base"] then
            print("Falling back to 'skin-base'")
            skeleton:setSkin("skin-base")
        end
    end
end
