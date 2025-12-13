-- Spine Love2D Runtime - Main Entry Point
-- Version: 1.0.0
-- Author: zhengying

-- Project root directory
local spine = {}

-- Version information
spine.version = "1.0.0"
spine.spineVersion = "4.2.x"
spine.love2dVersion = "11.3+"

-- Core module loading
spine.utils = require("spine.utils")
spine.math = require("spine.math")
spine.data = require("spine.data")
spine.skeleton = require("spine.skeleton")
spine.animation = require("spine.animation")
spine.rendering = require("spine.rendering")
spine.atlas = require("spine.atlas")
spine.constraint = require("spine.constraint")

-- Convenient API wrappers
spine.Skeleton = spine.skeleton.Skeleton
spine.SkeletonData = spine.data.SkeletonData
spine.AnimationState = spine.animation.AnimationState
spine.AnimationStateData = spine.data.AnimationStateData
spine.TextureAtlas = spine.atlas.Atlas
spine.Renderer = spine.rendering.Renderer
spine.SkeletonRenderer = spine.rendering.SkeletonRenderer

-- Error handling
spine.errors = {
  INVALID_JSON = "spine_invalid_json_format",
  MISSING_BONE = "spine_bone_not_found",
  MISSING_ATTACHMENT = "spine_attachment_not_found",
  INVALID_ANIMATION = "spine_invalid_animation_data",
  TEXTURE_LOAD_FAILED = "spine_texture_load_failed",
  UNSUPPORTED_FEATURE = "spine_unsupported_feature",
  VERSION_MISMATCH = "spine_version_mismatch",
  INVALID_ATLAS = "spine_invalid_atlas_format"
}

-- Debug mode
spine.debug = false
spine.debugOptions = {
  showBones = false,
  showSlots = false,
  showAttachments = false,
  showBounds = false,
  showMesh = false,
  performanceStats = false
}

-- Performance monitoring
spine.performance = {
  skeletonUpdateTime = 0,
  animationUpdateTime = 0,
  renderTime = 0,
  drawCalls = 0,
  vertexCount = 0,
  triangleCount = 0
}

-- Initialization function
function spine.init()
  print(string.format("Spine Love2D Runtime v%s initialized", spine.version))
  print(string.format("Compatible with Spine %s and Love2D %s", 
    spine.spineVersion, spine.love2dVersion))
  
  -- Check Love2D version
  local major, minor, revision = love.getVersion()
  if major < 11 then
    error("Spine Love2D Runtime requires Love2D 11.0 or higher")
  end
  
  -- Initialize math library (if needed)
  if spine.math.init then
    spine.math.init()
  end
  
  return true
end

-- Load Spine data files
function spine.loadSkeleton(jsonFile, atlasFile, scale)
  scale = scale or 1
  
  -- Load JSON data
  local jsonData
  if type(jsonFile) == "string" then
    local fileData = love.filesystem.read(jsonFile)
    if not fileData then
      error(string.format("Failed to read JSON file: %s", jsonFile))
    end
    jsonData = spine.utils.jsonDecode(fileData)
  else
    jsonData = jsonFile
  end
  
  if not jsonData then
    error("Invalid JSON data")
  end
  
  -- Load atlas
  local atlas
  if atlasFile then
    local atlasData
    if type(atlasFile) == "string" then
      atlasData = love.filesystem.read(atlasFile)
      if not atlasData then
        error(string.format("Failed to read atlas file: %s", atlasFile))
      end
    else
      atlasData = atlasFile
    end
    atlas = spine.TextureAtlas.new()
    local imageRoot = nil
    if type(atlasFile) == "string" then
      imageRoot = atlasFile:match("^(.*)/[^/]+$") or ""
    end
    local ok, err = atlas:loadAtlasFile(atlasData, imageRoot)
    if not ok then
      error(string.format("Failed to load atlas: %s", err or "unknown error"))
    end
  end
  
  -- Create data objects
  local skeletonData = spine.data.SkeletonData.new(jsonData, scale)
  
  -- Create runtime objects
  local skeleton = spine.skeleton.Skeleton.new(skeletonData)
  local renderer = spine.Renderer.new()
  
  -- Create animation state if animations exist
  local animationState = nil
  if jsonData.animations and next(jsonData.animations) then
    local AnimationState = spine.animation.AnimationState
    animationState = AnimationState.new(skeletonData)
  end
  
  return {
    skeleton = skeleton,
    animationState = animationState,
    renderer = renderer,
    skeletonData = skeletonData,
    atlas = atlas
  }
end

-- Update animation state
function spine.update(instance, deltaTime)
  local startTime = love.timer.getTime()
  
  -- Update animation state if it exists
  if instance.animationState then
    instance.animationState:update(deltaTime)
    instance.animationState:apply(instance.skeleton)
  end
  
  -- -- Update skeleton time (required for physics)
  -- instance.skeleton:update(deltaTime)
  
  -- Update skeleton world transforms
  instance.skeleton:updateWorldTransform()
  
  spine.performance.animationUpdateTime = love.timer.getTime() - startTime
end

-- Render Spine instance
function spine.draw(instance, x, y, scaleX, scaleY, rotation)
  x = x or 0
  y = y or 0
  scaleX = scaleX or 1
  scaleY = scaleY or -1
  rotation = rotation or 0
  
  local startTime = love.timer.getTime()
  
  -- Reset performance counters
  spine.performance.drawCalls = 0
  spine.performance.vertexCount = 0
  spine.performance.triangleCount = 0
  
  -- Render skeleton
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(rotation)
  love.graphics.scale(scaleX, scaleY)
  
  instance.renderer:drawSkeleton(instance.skeleton)
  
  -- Debug rendering
  if spine.debug then
    spine.drawDebug(instance, x, y, scaleX, scaleY, rotation)
  end
  
  love.graphics.pop()
  
  spine.performance.renderTime = love.timer.getTime() - startTime
end

-- Debug rendering
function spine.drawDebug(instance, x, y, scaleX, scaleY, rotation)
  x = x or 0
  y = y or 0
  scaleX = scaleX or 1
  scaleY = scaleY or -1
  rotation = rotation or 0

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(rotation)
  love.graphics.scale(scaleX, scaleY)
  
  -- Use the renderer's debug rendering
  instance.renderer:drawDebugSkeleton(instance.skeleton)
  
  love.graphics.pop()
end

-- Performance statistics
function spine.getPerformanceStats()
  return {
    skeletonUpdateTime = spine.performance.skeletonUpdateTime,
    animationUpdateTime = spine.performance.animationUpdateTime,
    renderTime = spine.performance.renderTime,
    totalTime = spine.performance.skeletonUpdateTime + 
               spine.performance.animationUpdateTime + 
               spine.performance.renderTime,
    drawCalls = spine.performance.drawCalls,
    vertexCount = spine.performance.vertexCount,
    triangleCount = spine.performance.triangleCount,
    fps = 1.0 / (spine.performance.skeletonUpdateTime + 
                 spine.performance.animationUpdateTime + 
                 spine.performance.renderTime)
  }
end

-- Error handling function
function spine.handleError(errorType, message, ...)
  local errorMessage = string.format("[Spine Runtime Error: %s] %s", errorType, message)
  if spine.debug then
    print(debug.traceback(errorMessage, 2))
  end
  return error(errorMessage)
end

-- Version compatibility check
function spine.checkVersion(spineVersion)
  local major, minor = spineVersion:match("(%d+)%.(%d+)")
  major = tonumber(major)
  minor = tonumber(minor)
  
  if major < 4 or (major == 4 and minor < 2) then
    spine.handleError(spine.errors.VERSION_MISMATCH,
      string.format("Spine version %s is not supported. Minimum required: 4.2.x", spineVersion))
  end
end

-- Set debug mode
function spine.setDebug(enabled, options)
  spine.debug = enabled
  if options then
    for key, value in pairs(options) do
      spine.debugOptions[key] = value
    end
  end
end

-- Utility function: Load JSON from file
function spine.loadJsonFromFile(filePath)
  local fileData = love.filesystem.read(filePath)
  if not fileData then
    return nil, "Failed to read file: " .. filePath
  end
  
  local success, result = pcall(spine.utils.jsonDecode, fileData)
  if not success then
    return nil, "Failed to parse JSON: " .. result
  end
  
  return result
end

-- Utility function: Load atlas from file
function spine.loadAtlasFromFile(filePath)
  local atlasData = love.filesystem.read(filePath)
  if not atlasData then
    return nil, "Failed to read atlas file: " .. filePath
  end
  
  local atlas = spine.TextureAtlas.new()
  local imageRoot = filePath:match("^(.*)/[^/]+$") or ""
  local ok, err = atlas:loadAtlasFile(atlasData, imageRoot)
  if not ok then
    return nil, err
  end
  return atlas
end

-- Utility function: Create test skeleton
function spine.createTestSkeleton()
  local testData = {
    skeleton = {
      hash = "test_skeleton",
      spine = "4.2.00",
      x = -50, y = -50,
      width = 100, height = 100
    },
    bones = {
      { name = "root", x = 0, y = 0 },
      { name = "torso", parent = "root", length = 30, x = 0, y = 0, rotation = 90 },
      { name = "head", parent = "torso", length = 20, x = 0, y = 30, rotation = 0 }
    },
    slots = {
      { name = "torso_slot", bone = "torso", attachment = "torso_img" },
      { name = "head_slot", bone = "head", attachment = "head_img" }
    },
    skins = {
      default = {
        torso_slot = { torso_img = { type = "region", x = 0, y = 0, width = 30, height = 40 } },
        head_slot = { head_img = { type = "region", x = 0, y = 0, width = 25, height = 25 } }
      }
    },
    animations = {
      idle = {
        bones = {
          head = {
            rotate = {
              { time = 0, angle = -5 },
              { time = 1, angle = 5 },
              { time = 2, angle = -5 }
            }
          }
        }
      }
    }
  }
  
  return spine.loadSkeleton(testData)
end

-- Initialize runtime
spine.init()

return spine
