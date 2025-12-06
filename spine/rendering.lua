-- Spine Love2D Runtime - Rendering System
-- Handles drawing Spine skeletons using Love2D's graphics API

local mathModule = require("spine.math")
local utilsModule = require("spine.utils")

-- Helper to check for valid numbers
local function isValidNumber(n)
    return n == n and n ~= math.huge and n ~= -math.huge
end

local Renderer = {}
Renderer.__index = Renderer

function Renderer:begin()
    self.vertexCount = 0
    self.batches = {}
    self.currentBatch = nil
    love.graphics.push()
end

function Renderer:end_()
    self:flush()
    love.graphics.pop()
end

function Renderer:flush()
    if self.currentBatch and self.vertexCount > 0 then
        local batch = {
            texture = self.currentBatch.texture,
            vertices = {},
            vertexCount = self.vertexCount
        }
        
        for i = 1, self.vertexCount * 8 do
            batch.vertices[i] = self.vertexBuffer[i]
        end
        
        table.insert(self.batches, batch)
        self.vertexCount = 0
        self.currentBatch = nil
    end
end

function Renderer:addVertex(x, y, u, v, r, g, b, a)
    local index = self.vertexCount * 8 + 1
    self.vertexBuffer[index] = x
    self.vertexBuffer[index + 1] = y
    self.vertexBuffer[index + 2] = u
    self.vertexBuffer[index + 3] = v
    self.vertexBuffer[index + 4] = r
    self.vertexBuffer[index + 5] = g
    self.vertexBuffer[index + 6] = b
    self.vertexBuffer[index + 7] = a
    self.vertexCount = self.vertexCount + 1
end

function Renderer:setTexture(texture)
    if self.currentBatch and self.currentBatch.texture ~= texture then
        self:flush()
    end
    
    if not self.currentBatch then
        self.currentBatch = {texture = texture}
    end
end

function Renderer:drawSkeleton(skeleton)
    self:begin()
    
    -- Apply skeleton transform
    love.graphics.push()
    
    -- Set skeleton color
    love.graphics.setColor(skeleton.r, skeleton.g, skeleton.b, skeleton.a)
    
    -- Update world transforms before rendering
    -- skeleton:updateWorldTransform() -- Already called in update
    
    local drawOrder = skeleton.drawOrder
    local orderedSlots = {}
    local rainSlots = {}
    for i, slot in ipairs(drawOrder) do
        local sname = slot.data.name or ""
        local aname = (slot.attachment and slot.attachment.name) or ""
        if string.find(sname, "rain") or string.find(aname, "rain") then
            table.insert(rainSlots, slot)
        else
            table.insert(orderedSlots, slot)
        end
    end
    for i = 1, #rainSlots do
        table.insert(orderedSlots, rainSlots[i])
    end
    local clipper = nil
    local clippingEndSlot = nil
    local shouldEndClipping = false
    local clippingStartIndex = nil
    
    for i, slot in ipairs(orderedSlots) do
        local attachment = slot.attachment
        
        -- Check if we should end clipping from previous iteration
        if shouldEndClipping then
            love.graphics.setStencilTest()
            clipper = nil
            clippingEndSlot = nil
            shouldEndClipping = false
            clippingStartIndex = nil
        end
        
        if attachment then
            -- Handle clipping start
            if attachment.type == "clipping" then
                local clipping = attachment
                clippingEndSlot = clipping.endSlot
                clippingStartIndex = i
                
                -- Start stencil
                love.graphics.stencil(function()
                    self:drawClipping(slot, clipping)
                end, "replace", 1)
                
                love.graphics.setStencilTest("greater", 0)
                clipper = clipping
            else
                self:drawAttachment(slot, attachment)
            end
        end
        
        -- Check if this is the end slot for clipping
        -- We check AFTER rendering the slot, so clipping affects this slot
        -- BUT: don't end at the same slot that started clipping
        if clipper and slot.data.name == clippingEndSlot and i ~= clippingStartIndex then
            shouldEndClipping = true
        end
    end
    
    -- Ensure stencil is disabled if we finished
    love.graphics.setStencilTest()
    
    -- Debug rendering
    if self.debug then
        self:drawDebug(skeleton)
        
        -- Draw clipping polygons for debug
        for i, slot in ipairs(drawOrder) do
            if slot.attachment and slot.attachment.type == "clipping" then
                local worldVertices = {}
                slot.attachment:computeWorldVertices(slot, worldVertices)
                love.graphics.setColor(1, 0, 0, 0.5) -- Red semi-transparent
                if #worldVertices >= 6 then
                    love.graphics.polygon("line", worldVertices)
                end
            end
        end
    end
    
    self:end_()
    love.graphics.pop()
end

function Renderer:drawClipping(slot, clipping)
    local worldVertices = {}
    clipping:computeWorldVertices(slot, worldVertices)
    
    -- The love.graphics.stencil function should handle color masking automatically
    -- But we'll be explicit just to be safe
    if #worldVertices >= 6 then
        -- Check vertices for NaNs
        local valid = true
        for i = 1, #worldVertices do
            if not isValidNumber(worldVertices[i]) then
                valid = false
                break
            end
        end
        
        if valid then
            love.graphics.polygon("fill", worldVertices)
        else
            print("WARNING: Invalid vertices for clipping attachment: " .. (clipping.name or "unknown"))
        end
    end
end

function Renderer:drawAttachment(slot, attachment)
    local bone = slot.bone
    local skeleton = bone.skeleton
    
    -- Apply slot color
    local color = slot.color
    love.graphics.setColor(color.r, color.g, color.b, color.a)

    local type = attachment.type
    
    if type == "region" then
        self:drawRegionAttachment(slot, attachment)
    elseif type == "mesh" then
        self:drawMeshAttachment(slot, attachment)
    elseif type == "boundingbox" then
        -- Bounding boxes are not rendered
    end
end

function Renderer:drawRegionAttachment(slot, attachment)
    local region = attachment.region
    if not region then return end
    
    local texture = region.texture
    if not texture then return end
    
    self:setTexture(texture)
    
    -- Calculate world vertices
    local worldVertices = {}
    attachment:computeWorldVertices(slot.bone, worldVertices)
    
    -- Check for invalid vertices
    for i = 1, #worldVertices do
        if not isValidNumber(worldVertices[i]) then
            print("WARNING: Invalid vertex in region attachment: " .. (attachment.name or "unknown"))
            return
        end
    end
    
    -- Removed rain debug red dot
    local r, g, b, a = 255, 255, 255, 255
    
    local meshData = {
        {worldVertices[1], worldVertices[2], worldVertices[3], worldVertices[4], r, g, b, a}, -- Top-left
        {worldVertices[5], worldVertices[6], worldVertices[7], worldVertices[8], r, g, b, a}, -- Bottom-left
        {worldVertices[9], worldVertices[10], worldVertices[11], worldVertices[12], r, g, b, a}, -- Bottom-right
        {worldVertices[13], worldVertices[14], worldVertices[15], worldVertices[16], r, g, b, a} -- Top-right
    }
    
    -- Create or reuse mesh
    local mesh = attachment.rendererObject
    if not mesh then
        mesh = love.graphics.newMesh(meshData, "fan", "stream")
        attachment.rendererObject = mesh
    else
        mesh:setVertices(meshData)
    end
    
    mesh:setTexture(texture)

    local alphaMode = (region.page and region.page.pma) and "premultiplied" or "alphamultiply"
    local blendMode = slot.data.blendMode or "normal"
    if blendMode == "multiply" then
        love.graphics.setColor(1, 1, 1, 1)
    end
    if blendMode == "additive" then
        love.graphics.setBlendMode("add", alphaMode)
    elseif blendMode == "multiply" then
        love.graphics.setBlendMode("multiply", alphaMode)
    elseif blendMode == "screen" then
        love.graphics.setBlendMode("screen", alphaMode)
    else
        love.graphics.setBlendMode("alpha", alphaMode)
    end
    
    local usedShader = false
    if blendMode == "multiply" then
        if self.multiplyMaskShader then
            love.graphics.setShader(self.multiplyMaskShader)
            usedShader = true
        end
    elseif slot.darkColor and self.tintBlackShader then
        love.graphics.setShader(self.tintBlackShader)
        local dr = slot.darkColor.r or 0
        local dg = slot.darkColor.g or 0
        local db = slot.darkColor.b or 0
        local da = slot.darkColor.a or 1
        self.tintBlackShader:send("darkColor", {dr, dg, db, da})
        usedShader = true
    end
    
    -- Draw mesh
    love.graphics.draw(mesh, 0, 0)
    
    -- Reset shader if we used one
    if usedShader then
        love.graphics.setShader()
    end
    
    love.graphics.setBlendMode("alpha", "alphamultiply")
end

function Renderer:drawMeshAttachment(slot, attachment)
    local texture = attachment.region and attachment.region.texture
    if not texture then 
        if not self.debugPrinted then
            print("Debug Mesh: No texture for " .. (attachment.name or "unnamed"))
        end
        return 
    end
    
    local uvs = attachment.uvs
    local indices = attachment.indices
    local triangles = attachment.triangles
    
    if not uvs or not triangles then 
        if not self.debugPrinted then
            print("Debug Mesh: No UVs or Triangles for " .. (attachment.name or "unnamed"))
            print("UVs: " .. (uvs and "Yes" or "No"))
            print("Triangles: " .. (triangles and "Yes" or "No"))
        end
        return 
    end
    
    if not self.debugPrinted then
        -- Debug print removed
    end
    
    self:setTexture(texture)
    
    -- Calculate world vertices
    local worldVertices = {}
    attachment:computeWorldVertices(slot, worldVertices)
    
    -- Check for invalid vertices
    for i = 1, #worldVertices do
        if not isValidNumber(worldVertices[i]) then
            print("WARNING: Invalid vertex in mesh attachment: " .. (attachment.name or "unknown"))
            return
        end
    end
    
    -- Removed rain debug red dot
    
    -- Use white vertex color; rely on global love.graphics.setColor for slot tint
    local r, g, b, a = 255, 255, 255, 255
    
    -- Create mesh data
    local meshData = {}
    for i = 1, #worldVertices, 2 do
        local x = worldVertices[i] or 0
        local y = worldVertices[i + 1] or 0
        local u = uvs[i] or 0
        local v = uvs[i + 1] or 0
        
        -- x, y, u, v, r, g, b, a
        table.insert(meshData, {
            x, y, 
            u, v,
            r, g, b, a
        })
    end
    
    if #meshData == 0 then return end
    
    local mesh = attachment.rendererObject
    if not mesh then
        mesh = love.graphics.newMesh(
            meshData,
            "triangles",
            "stream"
        )
        attachment.rendererObject = mesh
        
        -- Draw mesh with indices (only need to set once if static, but safe to set here)
        if #triangles > 0 then
            mesh:setVertexMap(triangles)
        end
    else
        mesh:setVertices(meshData)
    end
    
    -- Set mesh texture
    mesh:setTexture(texture)
    
    local alphaMode = (attachment.region and attachment.region.page and attachment.region.page.pma) and "premultiplied" or "alphamultiply"
    local blendMode = slot.data.blendMode or "normal"
    if blendMode == "multiply" then
        love.graphics.setColor(1, 1, 1, 1)
    end
    if blendMode == "additive" then
        love.graphics.setBlendMode("add", alphaMode)
    elseif blendMode == "multiply" then
        love.graphics.setBlendMode("multiply", alphaMode)
    elseif blendMode == "screen" then
        love.graphics.setBlendMode("screen", alphaMode)
    else
        love.graphics.setBlendMode("alpha", alphaMode)
    end
    
    local usedShader = false
    if blendMode == "multiply" then
        if self.multiplyMaskShader then
            love.graphics.setShader(self.multiplyMaskShader)
            usedShader = true
        end
    elseif slot.darkColor and self.tintBlackShader then
        love.graphics.setShader(self.tintBlackShader)
        local dr = slot.darkColor.r or 0
        local dg = slot.darkColor.g or 0
        local db = slot.darkColor.b or 0
        local da = slot.darkColor.a or 1
        self.tintBlackShader:send("darkColor", {dr, dg, db, da})
        usedShader = true
    end

    love.graphics.draw(mesh, 0, 0)
    
    -- Reset shader if we used one
    if usedShader then
        love.graphics.setShader()
    end
    
    love.graphics.setBlendMode("alpha", "alphamultiply")
end

function Renderer:drawDebugSkeleton(skeleton)
    love.graphics.push()
    love.graphics.setLineWidth(1)
    
    -- Draw bones
    love.graphics.setColor(1, 0, 0, 0.5)
    for _, bone in ipairs(skeleton.bones) do
        if bone.parent then
            if isValidNumber(bone.parent.worldX) and isValidNumber(bone.parent.worldY) and
               isValidNumber(bone.worldX) and isValidNumber(bone.worldY) then
                love.graphics.line(
                    bone.parent.worldX, bone.parent.worldY,
                    bone.worldX, bone.worldY
                )
            else
                print(string.format("WARNING: Invalid bone coordinates for %s or parent", bone.data.name))
            end
        end
    end
    
    -- Draw bone points
    love.graphics.setColor(0, 1, 0, 0.8)
    for _, bone in ipairs(skeleton.bones) do
        love.graphics.circle("fill", bone.worldX, bone.worldY, 3)
    end
    
    -- Draw attachment bounds
    love.graphics.setColor(0, 0, 1, 0.3)
    for _, slot in ipairs(skeleton.drawOrder) do
        if slot.attachment then
            self:drawDebugAttachment(slot, slot.attachment)
        end
    end
    
    love.graphics.pop()
end

function Renderer:drawDebugAttachment(slot, attachment)
    local bone = slot.bone
    
    if not (isValidNumber(bone.worldX) and isValidNumber(bone.worldY)) then
        print(string.format("WARNING: Invalid bone position for %s: %.2f, %.2f", bone.data.name, bone.worldX, bone.worldY))
        return
    end

    love.graphics.push()
    love.graphics.translate(bone.worldX, bone.worldY)
    love.graphics.rotate(math.rad(bone.worldRotation or 0))
    love.graphics.scale(bone.worldScaleX or 1, bone.worldScaleY or 1)
    
    if attachment.type == "region" then
        local vertices = attachment.offset
        if vertices and #vertices >= 8 then
            -- Check vertices
            local valid = true
            for i = 1, #vertices do
                if not isValidNumber(vertices[i]) then
                    valid = false
                    break
                end
            end
            
            if valid then
                love.graphics.polygon("line",
                    vertices[1], vertices[2],
                    vertices[3], vertices[4],
                    vertices[5], vertices[6],
                    vertices[7], vertices[8]
                )
            else
                print("WARNING: Invalid vertices for region attachment: " .. (attachment.name or "unknown"))
            end
        end
    elseif attachment.type == "mesh" then
        local vertices = attachment.vertices
        if vertices and #vertices >= 4 then
            -- Draw convex hull for debugging
            local minX, maxX = vertices[1], vertices[1]
            local minY, maxY = vertices[2], vertices[2]
            
            local valid = true
            for i = 1, #vertices do
                if not isValidNumber(vertices[i]) then
                    valid = false
                    break
                end
            end
            
            if valid then
                for i = 3, #vertices, 2 do
                    minX = math.min(minX, vertices[i])
                    maxX = math.max(maxX, vertices[i])
                    minY = math.min(minY, vertices[i + 1])
                    maxY = math.max(maxY, vertices[i + 1])
                end
                
                love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
            else
                print("WARNING: Invalid vertices for mesh attachment: " .. (attachment.name or "unknown"))
            end
        end
    elseif attachment.type == "boundingbox" then
        local vertices = attachment.vertices
        if vertices and #vertices >= 4 then
            local valid = true
            for i = 1, #vertices do
                if not isValidNumber(vertices[i]) then
                    valid = false
                    break
                end
            end
            
            if valid then
                love.graphics.polygon("line", vertices)
            else
                print("WARNING: Invalid vertices for bounding box: " .. (attachment.name or "unknown"))
            end
        end
    end
    
    love.graphics.pop()
end


local SkeletonRenderer = {}
SkeletonRenderer.__index = SkeletonRenderer

function Renderer.new()
    local self = setmetatable({}, Renderer)
    self.blendMode = 1
    self.currentTexture = nil
    self.debug = false
    
    -- Load Tint Black shader for dual-color tinting
    local success, result = pcall(function()
        return require("spine.tintblack_shader")
    end)
    
    if success then
        self.tintBlackShader = result
        print("Spine Tint Black shader loaded successfully")
    else
        print("Warning: Failed to load Tint Black shader: " .. tostring(result))
        self.tintBlackShader = nil
    end
    
    local ok2, res2 = pcall(function()
        return require("spine.multiply_mask_shader")
    end)
    if ok2 then
        self.multiplyMaskShader = res2
    else
        self.multiplyMaskShader = nil
    end
    
    return self
end

function SkeletonRenderer.new()
    local self = setmetatable({}, SkeletonRenderer)
    self.renderer = Renderer.new()
    self.debug = false
    return self
end

function SkeletonRenderer:draw(skeleton)
    self.renderer:drawSkeleton(skeleton)
    
    if self.debug then
        self.renderer:drawDebugSkeleton(skeleton)
    end
end

function SkeletonRenderer:setDebug(debug)
    self.debug = debug
end

function SkeletonRenderer:drawSlot(slot, x, y, rotation, scaleX, scaleY)
    if not slot.attachment then return end
    
    love.graphics.push()
    love.graphics.translate(x or 0, y or 0)
    love.graphics.rotate(rotation or 0)
    love.graphics.scale(scaleX or 1, scaleY or 1)
    
    self.renderer:drawAttachment(slot, slot.attachment)
    
    love.graphics.pop()
end

-- Module exports
local renderingModule = {
    Renderer = Renderer,
    SkeletonRenderer = SkeletonRenderer
}

return renderingModule
