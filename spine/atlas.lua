-- Spine Love2D Runtime - Atlas Management
-- Handles texture atlas loading and region management

local utilsModule = require("spine.utils")

local AtlasRegion = {}
AtlasRegion.__index = AtlasRegion

function AtlasRegion.new()
    local self = setmetatable({}, AtlasRegion)
    self.name = ""
    self.x = 0
    self.y = 0
    self.width = 0
    self.height = 0
    self.u = 0
    self.v = 0
    self.u2 = 0
    self.v2 = 0
    self.rotate = false
    self.offsetX = 0
    self.offsetY = 0
    self.originalWidth = 0
    self.originalHeight = 0
    self.index = 0
    self.texture = nil
    self.page = nil
    return self
end

function AtlasRegion:setTexture(texture)
    self.texture = texture
    if texture then
        local texWidth, texHeight = texture:getDimensions()
        self.u = self.x / texWidth
        self.v = self.y / texHeight
        self.u2 = (self.x + self.width) / texWidth
        self.v2 = (self.y + self.height) / texHeight
    end
end


local AtlasPage = {}
AtlasPage.__index = AtlasPage

function AtlasPage.new(name)
    local self = setmetatable({}, AtlasPage)
    self.name = name
    self.texture = nil
    self.width = 0
    self.height = 0
    self.minFilter = "linear"
    self.magFilter = "linear"
    self.uWrap = "clamp"
    self.vWrap = "clamp"
    self.pma = false
    return self
end


local Atlas = {}
Atlas.__index = Atlas

function Atlas.new()
    local self = setmetatable({}, Atlas)
    self.pages = {}
    self.regions = {}
    self.regionsByName = {}
    return self
end

function Atlas:loadAtlasFile(atlasText, imagePath)
    local lines = {}
    for line in atlasText:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    local lineIndex = 1
    local currentPage = nil
    local currentRegion = nil
    
    while lineIndex <= #lines do
        local line = lines[lineIndex]
        lineIndex = lineIndex + 1
        
        if line == "" then
            -- Empty line - skip
        elseif not currentPage then
            -- Start of a new page
            currentPage = AtlasPage.new(line)
            table.insert(self.pages, currentPage)
        elseif not currentRegion then
            -- Check if this is a page property (key: value format)
            local key, value = line:match("^%s*(%w+):%s*(.+)$")
            if key and value then
                self:parsePageProperty(currentPage, key, value)
            else
                -- This is a region name - start new region
                currentRegion = AtlasRegion.new()
                currentRegion.name = line
                currentRegion.page = currentPage
                table.insert(self.regions, currentRegion)
                self.regionsByName[line] = currentRegion
            end
        else
            local key, value = line:match("^%s*(%w+):%s*(.+)$")
            if key and value then
                self:parseRegionProperty(currentRegion, key, value)
            else
                -- Check if this is a new region name (non-indented, non-empty)
                -- If the line doesn't start with whitespace and isn't empty, it's a new region
                if not line:match("^%s") and line ~= "" then
                    -- This is a new region name - create it
                    currentRegion = AtlasRegion.new()
                    currentRegion.name = line
                    currentRegion.page = currentPage
                    table.insert(self.regions, currentRegion)
                    self.regionsByName[line] = currentRegion
                else
                    currentRegion = nil
                end
            end
        end
    end
    
    -- Post-process regions to handle defaults and rotation
    for _, region in ipairs(self.regions) do
        if region.rotate then
            -- Swap width and height because bounds in atlas are unrotated size,
            -- but we need packed size for UV calculations.
            local w = region.width
            local h = region.height
            region.width = h
            region.height = w
            
            if region.originalWidth == 0 then
                region.originalWidth = w
            end
            if region.originalHeight == 0 then
                region.originalHeight = h
            end
        else
            if region.originalWidth == 0 and region.width > 0 then
                region.originalWidth = region.width
            end
            if region.originalHeight == 0 and region.height > 0 then
                region.originalHeight = region.height
            end
        end
    end
    
    for _, page in ipairs(self.pages) do
        local ok, err = self:loadPageTexture(page, imagePath)
        if not ok then
            return nil, err
        end
    end
    
    return true
end

function Atlas:parsePageProperty(page, key, value)
    if key == "size" then
        local width, height = value:match("(%d+),(%d+)")
        if width and height then
            page.width = tonumber(width)
            page.height = tonumber(height)
        end
    elseif key == "format" then
        -- RGBA8888, RGBA4444, etc. (not used in Love2D)
    elseif key == "filter" then
        local min, mag = value:match("(%w+),(%w+)")
        if min and mag then
            page.minFilter = min
            page.magFilter = mag
        end
    elseif key == "repeat" then
        if value == "x" then
            page.uWrap = "repeat"
        elseif value == "y" then
            page.vWrap = "repeat"
        elseif value == "xy" then
            page.uWrap = "repeat"
            page.vWrap = "repeat"
        end
    elseif key == "pma" then
        page.pma = (value == "true")
    end
end

function Atlas:parseRegionProperty(region, key, value)
    if key == "rotate" then
        region.rotate = value == "true" or value == "90"
    elseif key == "xy" then
        local x, y = value:match("(%d+)%s*,%s*(%d+)")
        if x and y then
            region.x = tonumber(x)
            region.y = tonumber(y)
        end
    elseif key == "size" then
        local width, height = value:match("(%d+)%s*,%s*(%d+)")
        if width and height then
            region.width = tonumber(width)
            region.height = tonumber(height)
        end
    elseif key == "bounds" then
        local x, y, width, height = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if x and y and width and height then
            region.x = tonumber(x)
            region.y = tonumber(y)
            region.width = tonumber(width)
            region.height = tonumber(height)
        end
    elseif key == "orig" then
        local width, height = value:match("(%d+)%s*,%s*(%d+)")
        if width and height then
            region.originalWidth = tonumber(width)
            region.originalHeight = tonumber(height)
        end
    elseif key == "offset" then
        local x, y = value:match("(%d+)%s*,%s*(%d+)")
        if x and y then
            region.offsetX = tonumber(x)
            region.offsetY = tonumber(y)
        end
    elseif key == "offsets" then
        local x, y, width, height = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if x and y and width and height then
            region.offsetX = tonumber(x)
            region.offsetY = tonumber(y)
            region.originalWidth = tonumber(width)
            region.originalHeight = tonumber(height)
        end
    elseif key == "index" then
        region.index = tonumber(value)
    end
end

function Atlas:loadPageTexture(page, imagePath)
    local textureName = page.name
    local texturePath = utilsModule.joinPath(imagePath, textureName)
    
    local texture = nil
    local triedPaths = {}
    
    -- Try the exact path first
    if love.filesystem.getInfo(texturePath) then
        texture = love.graphics.newImage(texturePath)
        table.insert(triedPaths, texturePath)
    else
        -- Try common image extensions
        local extensions = {"png", "jpg", "jpeg"}
        for _, ext in ipairs(extensions) do
            local path = texturePath .. "." .. ext
            table.insert(triedPaths, path)
            if love.filesystem.getInfo(path) then
                texture = love.graphics.newImage(path)
                break
            end
        end
    end
    
    if not texture then
        return nil, ("Could not load texture '%s' from path '%s'. Tried paths: %s"):format(
            textureName, imagePath, table.concat(triedPaths, ", "))
    end
    
    page.texture = texture
    
    -- Set texture filtering
    local minFilter = page.minFilter
    local magFilter = page.magFilter
    
    if minFilter == "nearest" then
        texture:setFilter("nearest", magFilter == "nearest" and "nearest" or "linear")
    else
        texture:setFilter("linear", magFilter == "nearest" and "nearest" or "linear")
    end
    
    -- Set texture wrapping
    local uWrap = page.uWrap
    local vWrap = page.vWrap
    
    if uWrap == "repeat" or vWrap == "repeat" then
        texture:setWrap(
            uWrap == "repeat" and "repeat" or "clamp",
            vWrap == "repeat" and "repeat" or "clamp"
        )
    end
    
    -- Update region texture coordinates
    for _, region in ipairs(self.regions) do
        if region.page == page then
            region:setTexture(texture)
        end
    end
    
    return true
end

function Atlas:findRegion(name)
    return self.regionsByName[name]
end

function Atlas:getRegions()
    return self.regions
end

function Atlas:getPages()
    return self.pages
end

function Atlas:dispose()
    for _, page in ipairs(self.pages) do
        if page.texture then
            page.texture:release()
            page.texture = nil
        end
    end
    self.pages = {}
    self.regions = {}
    self.regionsByName = {}
end


local AtlasAttachmentLoader = {}
AtlasAttachmentLoader.__index = AtlasAttachmentLoader

function AtlasAttachmentLoader.new(atlas)
    local self = setmetatable({}, AtlasAttachmentLoader)
    self.atlas = atlas
    return self
end

function AtlasAttachmentLoader:newRegionAttachment(skin, name, path)
    local region = self.atlas:findRegion(path or name)
    if not region then
        return nil, ("Region not found in atlas: %s"):format(path or name)
    end
    
    local attachment = require("spine.data").RegionAttachment.new(name)
    
    -- Set region reference
    attachment.region = region
    attachment.path = path or name
    
    -- Call updateRegion() to calculate offset and UVs with proper scaling
    attachment:updateRegion()
    
    return attachment
end

function AtlasAttachmentLoader:newMeshAttachment(skin, name, path)
    local region = self.atlas:findRegion(path or name)
    if not region then
        return nil, ("Region not found in atlas: %s"):format(path or name)
    end
    
    local attachment = require("spine.data").MeshAttachment.new(name)
    
    -- Set region properties
    attachment.region = region
    
    -- Note: We don't set width/height here because they come from the JSON (geometry size),
    -- not the region size. Region size is used for updateRegion.
    
    -- IMPORTANT: We MUST store the region UVs here because createAttachment relies on them
    -- to inverse-transform back to normalized UVs if needed.
    -- Wait, createAttachment in data.lua uses region properties (u, v, u2, v2) to do the inverse transform.
    -- It reads attachment.region.u, etc.
    -- So as long as attachment.region is set, it should be fine.
    
    return attachment
end

function AtlasAttachmentLoader:findRegion(path)
    return self.atlas:findRegion(path)
end

function AtlasAttachmentLoader:newBoundingBoxAttachment(skin, name)
    return require("spine.data").BoundingBoxAttachment.new(name)
end

function AtlasAttachmentLoader:newPathAttachment(skin, name)
    return require("spine.data").PathAttachment.new(name)
end

function AtlasAttachmentLoader:newClippingAttachment(skin, name)
    return require("spine.data").ClippingAttachment.new(name)
end

-- Module exports
local atlasModule = {
    Atlas = Atlas,
    AtlasPage = AtlasPage,
    AtlasRegion = AtlasRegion,
    AtlasAttachmentLoader = AtlasAttachmentLoader
}

return atlasModule
