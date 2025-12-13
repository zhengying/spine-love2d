-- Spine Love2D Runtime - 数据加载模块
-- 负责解析和加载Spine JSON数据格式

local data = {}
local utils = require("spine.utils")
local math_module = require("spine.math")

-- 基础数据类
local BaseData = {}
BaseData.__index = BaseData

function BaseData.new()
  return setmetatable({}, BaseData)
end

-- 骨骼数据
local BoneData = setmetatable({}, {__index = BaseData})
BoneData.__index = BoneData

function BoneData.new(name, parent)
  local self = setmetatable(BaseData.new(), BoneData)
  self.name = name
  self.parent = parent
  self.length = 0
  self.x = 0
  self.y = 0
  self.rotation = 0
  self.scaleX = 1
  self.scaleY = 1
  self.shearX = 0
  self.shearY = 0
  self.transformMode = "normal"
  self.skinRequired = false
  self.color = "ffffffff"
  return self
end

function BoneData:copy()
  local copy = BoneData.new(self.name, self.parent)
  copy.length = self.length
  copy.x = self.x
  copy.y = self.y
  copy.rotation = self.rotation
  copy.scaleX = self.scaleX
  copy.scaleY = self.scaleY
  copy.shearX = self.shearX
  copy.shearY = self.shearY
  copy.transformMode = self.transformMode
  copy.skinRequired = self.skinRequired
  copy.color = self.color
  return copy
end

-- 插槽数据
local SlotData = setmetatable({}, {__index = BaseData})
SlotData.__index = SlotData

function SlotData.new(name, boneData)
  local self = setmetatable(BaseData.new(), SlotData)
  self.name = name
  self.boneData = boneData
  self.color = math_module.Color.new(1, 1, 1, 1)
  self.darkColor = nil
  self.attachmentName = nil
  self.blendMode = "normal"
  return self
end

function SlotData:copy()
  local copy = SlotData.new(self.name, self.boneData)
  copy.color = self.color:clone()
  if self.darkColor then
    copy.darkColor = self.darkColor:clone()
  end
  copy.attachmentName = self.attachmentName
  copy.blendMode = self.blendMode
  return copy
end

-- 附件数据基类
local Attachment = setmetatable({}, {__index = BaseData})
Attachment.__index = Attachment

function Attachment.new(name)
  local self = setmetatable(BaseData.new(), Attachment)
  self.name = name
  return self
end

-- 区域附件
local RegionAttachment = setmetatable({}, {__index = Attachment})
RegionAttachment.__index = RegionAttachment

function RegionAttachment.new(name)
  local self = setmetatable(Attachment.new(name), RegionAttachment)
  self.type = "region"
  self.x = 0
  self.y = 0
  self.rotation = 0
  self.scaleX = 1
  self.scaleY = 1
  self.width = 0
  self.height = 0
  self.color = math_module.Color.new(1, 1, 1, 1)
  self.path = nil
  self.rendererObject = nil
  self.region = nil
  self.sequence = nil
  self.offset = {}
  self.uvs = {}
  self.tempColor = math_module.Color.new()
  return self
end

function RegionAttachment:updateRegion()
  local region = self.region
  if not region then
    return
  end

  -- Atlas values (handle trimming)
  local regionWidth = region.width
  local regionHeight = region.height
  local regionOffsetX = region.offsetX or 0
  local regionOffsetY = region.offsetY or 0
  local originalWidth = region.originalWidth or regionWidth
  local originalHeight = region.originalHeight or regionHeight

  -- If rotated in atlas, width/height are swapped in region size
  if region.rotate then
     regionWidth = region.height
     regionHeight = region.width
  end

  -- Calculate scale factors to convert pixels to world units
  -- self.width/height comes from JSON (world units)
  -- originalWidth/Height comes from Atlas (pixels)
  local scaleX = 1
  local scaleY = 1
  if originalWidth > 0 then scaleX = self.width / originalWidth end
  if originalHeight > 0 then scaleY = self.height / originalHeight end

  -- Calculate local coordinates of the trimmed quad relative to the original image center
  -- Spine atlas offsets are usually from bottom-left of original image (or top-left? Spine uses BL usually)
  -- But standard formula:
  -- localX = -width / 2 + regionOffsetX * scaleX

  local localX = -self.width / 2 + regionOffsetX * scaleX
  local localY = -self.height / 2 + regionOffsetY * scaleY
  local localX2 = localX + regionWidth * scaleX
  local localY2 = localY + regionHeight * scaleY

  -- Store these local coords in self.offset (reusing this field for local vertices)
  -- Order: BL, BR, TR, TL (CCW from BL)
  -- 1: BL (x, y)
  -- 2: BR (x2, y)
  -- 3: TR (x2, y2)
  -- No, better to store the 4 corners explicitly.

  local offset = self.offset

  -- Scale is applied in computeWorldVertices or here?
  -- Standard runtime applies scale to these offsets.
  -- But scaleX/scaleY are properties of the attachment, not the region.
  -- So we should store unscaled local coords here.

  -- Corner 1: Bottom-Left (localX, localY)
  offset[1] = localX
  offset[2] = localY

  -- Corner 2: Bottom-Right (localX2, localY)
  offset[3] = localX2
  offset[4] = localY

  -- Corner 3: Top-Right (localX2, localY2)
  offset[5] = localX2
  offset[6] = localY2

  -- Corner 4: Top-Left (localX, localY2)
  offset[7] = localX
  offset[8] = localY2

  -- UVs
  local uvs = self.uvs
  local u = region.u
  local v = region.v
  local u2 = region.u2
  local v2 = region.v2

  if region.rotate then
    -- Rotated 90 deg CW in atlas
    -- Correct mapping derived:
    -- V1 (BL) -> Atlas TL (u, v)
    -- V2 (BR) -> Atlas BL (u, v2)
    -- V3 (TR) -> Atlas BR (u2, v2)
    -- V4 (TL) -> Atlas TR (u2, v)

    uvs[1] = u2
    uvs[2] = v2
    uvs[3] = u2
    uvs[4] = v
    uvs[5] = u
    uvs[6] = v
    uvs[7] = u
    uvs[8] = v2
  else
    uvs[1] = u
    uvs[2] = v2
    uvs[3] = u2
    uvs[4] = v2
    uvs[5] = u2
    uvs[6] = v
    uvs[7] = u
    uvs[8] = v
  end

  -- DEBUG
  -- if self.name == "front-shin" or self.name == "rear-shin" then
  --    print(string.format("Region: %s. Rotate: %s. Atlas: %d x %d. Calc: %d x %d. Off: %.2f, %.2f",
  --        self.name, tostring(region.rotate), region.width, region.height, regionWidth, regionHeight, regionOffsetX, regionOffsetY))
  --    print(string.format("UVs: %.2f,%.2f  %.2f,%.2f  %.2f,%.2f  %.2f,%.2f",
  --        uvs[1], uvs[2], uvs[3], uvs[4], uvs[5], uvs[6], uvs[7], uvs[8]))
  -- end
end

function RegionAttachment:computeWorldVertices(bone, worldVertices)
  local offset = self.offset
  local uvs = self.uvs
  local x = self.x or 0
  local y = self.y or 0
  local rotation = self.rotation or 0
  local scaleX = self.scaleX or 1
  local scaleY = self.scaleY or 1

  -- Get bone transform
  local boneX = bone.worldX
  local boneY = bone.worldY
  local a = bone.a
  local b = bone.b
  local c = bone.c
  local d = bone.d

  -- Calculate attachment's local transform
  local radians = math.rad(rotation)
  local cos = math.cos(radians)
  local sin = math.sin(radians)

  -- Helper to transform a local point
  local function transformPoint(lx, ly)
      -- Apply scale
      lx = lx * scaleX
      ly = ly * scaleY

      -- Apply rotation and offset
      local x1 = lx * cos - ly * sin + x
      local y1 = lx * sin + ly * cos + y

      -- Apply bone transform
      local wx = x1 * a + y1 * b + boneX
      local wy = x1 * c + y1 * d + boneY
      return wx, wy
  end

  -- We need to output vertices in the order expected by the renderer (TL, BL, BR, TR for fan?)
  -- Renderer uses:
  -- 1: TL
  -- 2: BL
  -- 3: BR
  -- 4: TR

  -- self.offset contains:
  -- 1: BL (indices 1,2)
  -- 2: BR (indices 3,4)
  -- 3: TR (indices 5,6)
  -- 4: TL (indices 7,8)

  -- TL (Offset 4)
  local wx, wy = transformPoint(offset[7], offset[8])
  worldVertices[1] = wx
  worldVertices[2] = wy
  worldVertices[3] = uvs[7]
  worldVertices[4] = uvs[8]

  -- BL (Offset 1)
  wx, wy = transformPoint(offset[1], offset[2])
  worldVertices[5] = wx
  worldVertices[6] = wy
  worldVertices[7] = uvs[1]
  worldVertices[8] = uvs[2]

  -- BR (Offset 2)
  wx, wy = transformPoint(offset[3], offset[4])
  worldVertices[9] = wx
  worldVertices[10] = wy
  worldVertices[11] = uvs[3]
  worldVertices[12] = uvs[4]

  -- TR (Offset 3)
  wx, wy = transformPoint(offset[5], offset[6])
  worldVertices[13] = wx
  worldVertices[14] = wy
  worldVertices[15] = uvs[5]
  worldVertices[16] = uvs[6]
end

-- 网格附件
local MeshAttachment = setmetatable({}, {__index = Attachment})
MeshAttachment.__index = MeshAttachment

function MeshAttachment.new(name)
  local self = setmetatable(Attachment.new(name), MeshAttachment)
  self.type = "mesh"
  self.path = nil
  self.color = math_module.Color.new(1, 1, 1, 1)
  self.width = 0
  self.height = 0
  self.hullLength = 0
  self.edges = {}
  self.parentMesh = nil
  self.sequence = nil
  self.tempColor = math_module.Color.new()
  self.region = nil
  self.sequence = nil
  self.vertices = {}
  self.worldVertices = {}
  self.uvs = {}
  self.regionUVs = nil
  self.triangles = {}
  self.bones = {}
  self.weights = {}
  return self
end

function MeshAttachment:updateRegion()
  if not self.region then
    return
  end

  local region = self.region
  local uvs = self.uvs
  local regionUVs = self.regionUVs

  if not regionUVs then
    -- Fallback if regionUVs not set (e.g. manually created mesh)
    -- But usually we want to avoid modifying uvs in place if we can't restore them
    -- Assuming uvs currently hold the source UVs if regionUVs is nil?
    -- No, better to require regionUVs for updateRegion to work correctly with multiple updates
    return
  end

  -- Resize uvs if needed
  if #uvs ~= #regionUVs then
    for i = 1, #regionUVs do uvs[i] = 0 end
  end

  local u = region.u
  local v = region.v
  local width = region.u2 - region.u
  local height = region.v2 - region.v

  if region.rotate then
    for i = 1, #regionUVs, 2 do
      local textureX = regionUVs[i]
      local textureY = regionUVs[i+1]
      -- 90 degrees CW rotation
      -- u = v (from bottom)
      -- v = u (from left)
      uvs[i] = u + textureY * width
      uvs[i + 1] = v + height - textureX * height
    end
  else
    for i = 1, #regionUVs, 2 do
      local textureX = regionUVs[i]
      local textureY = regionUVs[i+1]
      uvs[i] = u + textureX * width
      uvs[i + 1] = v + textureY * height
    end
  end
end

-- 路径附件
local PathAttachment = setmetatable({}, {__index = Attachment})
PathAttachment.__index = PathAttachment

function PathAttachment.new(name)
  local self = setmetatable(Attachment.new(name), PathAttachment)
  self.type = "path"
  self.lengths = {}
  self.closed = false
  self.constantSpeed = false
  self.color = math_module.Color.new(1, 0.5, 0, 1)
  self.vertices = {}
  self.bones = {}
  self.weights = {}
  self.worldVerticesLength = 0
  return self
end

-- Reuse computeWorldVertices logic from MeshAttachment?
-- PathAttachment computeWorldVertices is basically same as MeshAttachment but it doesn't use UVs?
-- No, MeshAttachment computeWorldVertices uses UVs only if region is set?
-- Actually MeshAttachment computeWorldVertices transforms vertices.
-- PathAttachment should do the same.
-- I can copy MeshAttachment:computeWorldVertices to PathAttachment.

function PathAttachment:computeWorldVertices(slot, start, count, worldVertices, offset, stride)
  local skeleton = slot.bone.skeleton
  local deform = slot.attachmentVertices
  local vertices = self.vertices
  local bones = self.bones
  local weights = self.weights

  -- Argument normalization for compatibility with old calls
  if type(start) == "table" then
    -- Old signature: computeWorldVertices(slot, worldVertices)
    worldVertices = start
    start = 0
    count = self.worldVerticesLength
    offset = 0
    stride = 2
  else
    -- New signature: computeWorldVertices(slot, start, count, worldVertices, offset, stride)
    -- Adjust 0-based Java arguments to 1-based Lua
    -- start is index in 'vertices' (or derived), offset is index in 'worldVertices'
    -- In Java: vertices[start], worldVertices[offset]
    -- In Lua: vertices[start+1], worldVertices[offset+1]
    start = start or 0
    count = count or self.worldVerticesLength
    offset = offset or 0
    stride = stride or 2
  end

  if #bones == 0 then
    -- No bone weights - transform vertices by slot's bone
    local bone = slot.bone
    local x = bone.worldX
    local y = bone.worldY
    local a = bone.a
    local b = bone.b
    local c = bone.c
    local d = bone.d

    if deform and #deform > 0 then
      for i = 0, count - 1, 2 do
        local v = start + i + 1
        local w = offset + (i / 2) * stride + 1
        local vx = vertices[v] + deform[v]
        local vy = vertices[v + 1] + deform[v + 1]
        worldVertices[w] = vx * a + vy * b + x
        worldVertices[w + 1] = vx * c + vy * d + y
      end
    else
      for i = 0, count - 1, 2 do
        local v = start + i + 1
        local w = offset + (i / 2) * stride + 1
        local vx = vertices[v]
        local vy = vertices[v + 1]
        worldVertices[w] = vx * a + vy * b + x
        worldVertices[w + 1] = vx * c + vy * d + y
      end
    end
  else
    -- Weighted vertices
    local v = 1
    local b = 1
    local w = 1
    
    -- Skip to start
    for i = 0, start - 1, 2 do
      local n = bones[b]
      b = b + n + 1
      v = v + n * 2
      w = w + n
    end

    local skeletonBones = skeleton.bones
    
    if deform and #deform > 0 then
      for i = 0, count - 1, 2 do
        local wx, wy = 0, 0
        local boneCount = bones[b]
        b = b + 1
        
        if not boneCount then break end
        
        for ii = 1, boneCount do
          local boneIndex = bones[b]
          b = b + 1
          local bone = skeletonBones[boneIndex]
          local vx = vertices[v] + deform[v]
          local vy = vertices[v + 1] + deform[v + 1]
          local weight = weights[w]
          v = v + 2
          w = w + 1
          
          wx = wx + (vx * bone.a + vy * bone.b + bone.worldX) * weight
          wy = wy + (vx * bone.c + vy * bone.d + bone.worldY) * weight
        end
        
        local dest = offset + (i / 2) * stride + 1
        worldVertices[dest] = wx
        worldVertices[dest + 1] = wy
      end
    else
      for i = 0, count - 1, 2 do
        local wx, wy = 0, 0
        local boneCount = bones[b]
        b = b + 1
        
        if not boneCount then break end
        
        for ii = 1, boneCount do
          local boneIndex = bones[b]
          b = b + 1
          local bone = skeletonBones[boneIndex]
          local vx = vertices[v]
          local vy = vertices[v + 1]
          local weight = weights[w]
          v = v + 2
          w = w + 1
          
          wx = wx + (vx * bone.a + vy * bone.b + bone.worldX) * weight
          wy = wy + (vx * bone.c + vy * bone.d + bone.worldY) * weight
        end
        
        local dest = offset + (i / 2) * stride + 1
        worldVertices[dest] = wx
        worldVertices[dest + 1] = wy
      end
    end
  end
end

function MeshAttachment:computeWorldVertices(slot, worldVertices)
  local skeleton = slot.bone.skeleton
  local deform = slot.attachmentVertices
  local vertices = self.vertices
  local bones = self.bones
  local weights = self.weights

  if #bones == 0 then
    -- No bone weights - transform vertices by slot's bone
    local bone = slot.bone
    local x = bone.worldX
    local y = bone.worldY
    local a = bone.a
    local b = bone.b
    local c = bone.c
    local d = bone.d

    if deform and #deform > 0 then
      for i = 1, #vertices, 2 do
        local vx = vertices[i] + deform[i]
        local vy = vertices[i + 1] + deform[i + 1]
        worldVertices[i] = vx * a + vy * b + x
        worldVertices[i + 1] = vx * c + vy * d + y
      end
    else
      for i = 1, #vertices, 2 do
        local vx = vertices[i]
        local vy = vertices[i + 1]
        worldVertices[i] = vx * a + vy * b + x
        worldVertices[i + 1] = vx * c + vy * d + y
      end
    end
  else
    -- 有骨骼权重，需要计算
    local w = 0
    local v = 1
    local b = 1

    local limit = #self.uvs
    for i = 1, limit, 2 do
      local wx = 0
      local wy = 0

      local boneCount = bones[b]
      local nn = b + boneCount
      b = b + 1

      for n = b, nn do
        local boneIndex = bones[n]
        local bone = skeleton.bones[boneIndex]
        local vx = vertices[v]
        local vy = vertices[v + 1]
        if deform and #deform > 0 then
          vx = vx + (deform[v] or 0)
          vy = vy + (deform[v + 1] or 0)
        end
        local weight = weights[w + 1]

        wx = wx + (vx * bone.a + vy * bone.b + bone.worldX) * weight
        wy = wy + (vx * bone.c + vy * bone.d + bone.worldY) * weight

        v = v + 2
        w = w + 1
      end
      b = nn + 1

      worldVertices[i] = wx
      worldVertices[i + 1] = wy
    end

  end
end

-- 边界框附件
local BoundingBoxAttachment = setmetatable({}, {__index = Attachment})
BoundingBoxAttachment.__index = BoundingBoxAttachment

function BoundingBoxAttachment.new(name)
  local self = setmetatable(Attachment.new(name), BoundingBoxAttachment)
  self.type = "boundingbox"
  self.color = math_module.Color.new(1, 1, 1, 1)
  self.vertices = {}
  self.worldVertices = {}
  return self
end

-- 剪裁附件
local ClippingAttachment = setmetatable({}, {__index = Attachment})
ClippingAttachment.__index = ClippingAttachment

function ClippingAttachment.new(name)
  local self = setmetatable(Attachment.new(name), ClippingAttachment)
  self.type = "clipping"
  self.endSlot = nil
  self.vertexCount = 0
  self.vertices = {}
  self.bones = {}
  self.weights = {}
  self.worldVerticesLength = 0
  return self
end

function ClippingAttachment:computeWorldVertices(slot, worldVertices)
  local skeleton = slot.bone.skeleton
  local vertices = self.vertices
  local bones = self.bones
  local weights = self.weights
  local vertexCount = self.vertexCount

  if #bones == 0 then
    -- No bone weights - transform vertices by slot's bone
    local bone = slot.bone
    local x = bone.worldX
    local y = bone.worldY
    local a = bone.a
    local b = bone.b
    local c = bone.c
    local d = bone.d

    for i = 1, #vertices, 2 do
        local vx = vertices[i]
        local vy = vertices[i + 1]
        worldVertices[i] = vx * a + vy * b + x
        worldVertices[i + 1] = vx * c + vy * d + y
    end
  else
    -- Weighted vertices
    local w = 0
    local v = 1
    local b = 1

    for i = 1, vertexCount * 2, 2 do
      local wx = 0
      local wy = 0
      
      local boneCount = bones[b]
      local nn = b + boneCount
      b = b + 1

      for n = b, nn do
        local boneIndex = bones[n]
        local bone = skeleton.bones[boneIndex]
        local vx = vertices[v]
        local vy = vertices[v + 1]
        local weight = weights[w + 1]

        wx = wx + (vx * bone.a + vy * bone.b + bone.worldX) * weight
        wy = wy + (vx * bone.c + vy * bone.d + bone.worldY) * weight

        v = v + 2
        w = w + 1
      end
      b = nn + 1

      worldVertices[i] = wx
      worldVertices[i + 1] = wy
    end
  end
end

function BoundingBoxAttachment:computeWorldVertices(slot, worldVertices)
  local skeleton = slot.bone.skeleton
  local vertices = self.vertices
  local bones = self.bones
  local weights = self.weights

  if #bones == 0 then
    -- 无骨骼权重
    for i = 1, #vertices do
      worldVertices[i] = vertices[i]
    end
  else
    -- 有骨骼权重
    local w = 0
    local v = 1
    local b = 1

    for i = 1, #vertices, 2 do
      local wx = 0
      local wy = 0
      local nn = bones[b] + b
      b = b + 1

      for n = b, nn do
        local bone = skeleton.bones[bones[n]]
        local vx = vertices[v]
        local vy = vertices[v + 1]
        local weight = weights[w + 1]

        wx = wx + (vx * bone.a + vy * bone.b + bone.worldX) * weight
        wy = wy + (vx * bone.c + vy * bone.d + bone.worldY) * weight

        v = v + 2
        w = w + 1
      end

      worldVertices[i] = wx
      worldVertices[i + 1] = wy
    end
  end
end

-- 皮肤数据
local Skin = setmetatable({}, {__index = BaseData})
Skin.__index = Skin

function Skin.new(name)
  local self = setmetatable(BaseData.new(), Skin)
  self.name = name
  self.attachments = {}
  self.bones = {}
  self.constraints = {}
  self.color = math_module.Color.new(1, 1, 1, 1)
  return self
end

function Skin:addSkin(skin)
  for k, v in pairs(skin.attachments) do
    self.attachments[k] = v
  end

  for _, bone in ipairs(skin.bones) do
    table.insert(self.bones, bone)
  end

  for _, constraint in ipairs(skin.constraints) do
    table.insert(self.constraints, constraint)
  end
end

function Skin:setAttachment(slotIndex, name, attachment)
  if not self.attachments[slotIndex] then
    self.attachments[slotIndex] = {}
  end
  self.attachments[slotIndex][name] = attachment
end

function Skin:addAttachment(slotIndex, name, attachment)
  self:setAttachment(slotIndex, name, attachment)
end

function Skin:getAttachment(slotIndex, name)
  local slotAttachments = self.attachments[slotIndex]
  if slotAttachments then
    return slotAttachments[name]
  end
  return nil
end

function Skin:findNamesForSlot(slotIndex, names)
  names = names or {}
  local slotAttachments = self.attachments[slotIndex]
  if slotAttachments then
    for name, _ in pairs(slotAttachments) do
      table.insert(names, name)
    end
  end
  return names
end

function Skin:findAttachmentsForSlot(slotIndex, attachments)
  attachments = attachments or {}
  local slotAttachments = self.attachments[slotIndex]
  if slotAttachments then
    for _, attachment in pairs(slotAttachments) do
      table.insert(attachments, attachment)
    end
  end
  return attachments
end

function Skin:clear()
  self.attachments = {}
  self.bones = {}
  self.constraints = {}
end

-- 事件数据
local EventData = setmetatable({}, {__index = BaseData})
EventData.__index = EventData

function EventData.new(name)
  local self = setmetatable(BaseData.new(), EventData)
  self.name = name
  self.intValue = 0
  self.floatValue = 0
  self.stringValue = nil
  self.audioPath = nil
  self.volume = 1
  self.balance = 0
  return self
end

function EventData:copy()
  local copy = EventData.new(self.name)
  copy.intValue = self.intValue
  copy.floatValue = self.floatValue
  copy.stringValue = self.stringValue
  copy.audioPath = self.audioPath
  copy.volume = self.volume
  copy.balance = self.balance
  return copy
end

-- Constraint Data Classes
local IkConstraintData = setmetatable({}, {__index = BaseData})
IkConstraintData.__index = IkConstraintData

function IkConstraintData.new(name)
  local self = setmetatable(BaseData.new(), IkConstraintData)
  self.name = name
  self.order = 0
  self.bones = {}
  self.target = nil
  self.mix = 1
  self.bendDirection = 1
  self.compress = false
  self.stretch = false
  self.uniform = false
  return self
end

local TransformConstraintData = setmetatable({}, {__index = BaseData})
TransformConstraintData.__index = TransformConstraintData

function TransformConstraintData.new(name)
  local self = setmetatable(BaseData.new(), TransformConstraintData)
  self.name = name
  self.order = 0
  self.bones = {}
  self.target = nil
  self.local_ = false
  self.relative = false
  self.offsetRotation = 0
  self.offsetX = 0
  self.offsetY = 0
  self.offsetScaleX = 0
  self.offsetScaleY = 0
  self.offsetShearY = 0
  self.rotateMix = 1
  self.translateMix = 1
  self.scaleMix = 1
  self.shearMix = 1
  return self
end

local PathConstraintData = setmetatable({}, {__index = BaseData})
PathConstraintData.__index = PathConstraintData

function PathConstraintData.new(name)
  local self = setmetatable(BaseData.new(), PathConstraintData)
  self.name = name
  self.order = 0
  self.bones = {}
  self.target = nil
  self.positionMode = "percent"
  self.spacingMode = "length"
  self.rotateMode = "tangent"
  self.offsetRotation = 0
  self.position = 0
  self.spacing = 0
  self.rotateMix = 1
  self.translateMix = 1
  return self
end

local PhysicsConstraintData = setmetatable({}, {__index = BaseData})
PhysicsConstraintData.__index = PhysicsConstraintData

function PhysicsConstraintData.new(name)
  local self = setmetatable(BaseData.new(), PhysicsConstraintData)
  self.name = name
  self.order = 0
  self.bone = nil
  self.target = nil
  self.rotateMix = 0
  self.translateMix = 0
  self.scaleMix = 0
  self.shearMix = 0
  self.inertia = 0
  self.strength = 0
  self.damping = 0
  self.massInverse = 0
  self.wind = 0
  self.gravity = 0
  self.mix = 1
  self._x = 0
  self._y = 0
  self._rotate = 0
  self._scaleX = 0
  self._shearX = 0
  self._limit = 0
  self._step = 0
  return self
end

-- 骨架数据
local SkeletonData = setmetatable({}, {__index = BaseData})
SkeletonData.__index = SkeletonData

function SkeletonData.new(jsonData, scale)
  local self = setmetatable(BaseData.new(), SkeletonData)
  self.scale = scale or 1
  self.name = nil
  self.bones = {}
  self.slots = {}
  self.skins = {}
  self.events = {}
  self.animations = {}
  self.ikConstraints = {}
  self.transformConstraints = {}
  self.pathConstraints = {}
  self.physicsConstraints = {}
  self.linkedMeshes = {}
  self.defaultSkin = nil
  self.width = 0
  self.height = 0
  self.version = nil
  self.hash = nil
  self.imagesPath = nil
  self.audioPath = nil
  self.fps = 30

  if jsonData then
    self:loadFromJson(jsonData, nil)
  end

  return self
end

function SkeletonData:loadFromJson(json, attachmentLoader)
  -- 解析骨架元数据
  if json.skeleton then
    local skeleton = json.skeleton
    self.hash = skeleton.hash
    self.version = skeleton.spine
    self.width = skeleton.width or 0
    self.height = skeleton.height or 0
    self.imagesPath = skeleton.images
    self.audioPath = skeleton.audio
    self.fps = skeleton.fps or 30
  end

  -- 解析骨骼数据
  if json.bones then
    for _, boneJson in ipairs(json.bones) do
      local parent = nil
      if boneJson.parent then
        parent = self:findBone(boneJson.parent)
        if not parent then
          error("Parent bone not found: " .. boneJson.parent)
        end
      end

      local boneData = BoneData.new(boneJson.name, parent)
      boneData.length = (boneJson.length or 0) * self.scale
      boneData.x = (boneJson.x or 0) * self.scale
      boneData.y = (boneJson.y or 0) * self.scale
      boneData.rotation = boneJson.rotation or 0
      boneData.scaleX = boneJson.scaleX or 1
      boneData.scaleY = boneJson.scaleY or 1
      boneData.shearX = boneJson.shearX or 0
      boneData.shearY = boneJson.shearY or 0
      boneData.transformMode = boneJson.inherit or boneJson.transform or "normal"
      boneData.skinRequired = boneJson.skin or false
      boneData.color = boneJson.color or "ffffffff"

      table.insert(self.bones, boneData)
    end
  end

  -- 解析插槽数据
  if json.slots then
    for _, slotJson in ipairs(json.slots) do
      local boneData = self:findBone(slotJson.bone)
      if not boneData then
        error("Slot bone not found: " .. slotJson.bone)
      end

      local slotData = SlotData.new(slotJson.name, boneData)

      if slotJson.color then
        slotData.color:fromHex(slotJson.color)
      end

      if slotJson.dark then
        slotData.darkColor = math_module.Color.new()
        slotData.darkColor:fromHex(slotJson.dark)
      end

      slotData.attachmentName = slotJson.attachment
      slotData.blendMode = slotJson.blend or "normal"

      table.insert(self.slots, slotData)
    end
  end

  -- Parse skins
  if json.skins then
    if #json.skins > 0 then
        -- Array format (new Spine versions)
        for _, skinMap in ipairs(json.skins) do
            local skinName = skinMap.name
            local skin = Skin.new(skinName)

            -- Parse attachments
            if skinMap.attachments then
                for slotName, slotMap in pairs(skinMap.attachments) do
                    local slotIndex = self:findSlotIndex(slotName)
                    if slotIndex ~= -1 then
                        for attachmentName, attachmentMap in pairs(slotMap) do
                            local attachment = self:createAttachment(attachmentMap, attachmentName, attachmentLoader, slotName)
                            if attachment then
                                skin:setAttachment(slotIndex, attachmentName, attachment)
                            end
                        end
                    else
                        print("Warning: Skin slot not found: " .. slotName)
                    end
                end
            end

            self.skins[skinName] = skin
            if skinName == "default" then
                self.defaultSkin = skin
            end
        end
    else
        -- Map format (legacy)
        for skinName, skinMap in pairs(json.skins) do
            local skin = Skin.new(skinName)

            for slotName, slotMap in pairs(skinMap) do
                local slotIndex = self:findSlotIndex(slotName)
                if slotIndex == -1 then
                    error("Skin slot not found: " .. slotName)
                end

                for attachmentName, attachmentMap in pairs(slotMap) do
                local attachment = self:createAttachment(attachmentMap, attachmentName, attachmentLoader, slotName)
                if attachment then
                    skin:setAttachment(slotIndex, attachmentName, attachment)
                end
                end
            end

            self.skins[skinName] = skin
      if skinName == "default" then
        self.defaultSkin = skin
      end
    end
  end
  end

  -- 解析事件数据
  if json.events then
    for eventName, eventJson in pairs(json.events) do
      local eventData = EventData.new(eventName)
      eventData.intValue = eventJson.int or 0
      eventData.floatValue = eventJson.float or 0
      eventData.stringValue = eventJson.string
      eventData.audioPath = eventJson.audio
      eventData.volume = eventJson.volume or 1
      eventData.balance = eventJson.balance or 0
      self.events[eventName] = eventData
    end
  end

  -- Parse IK constraints
  if json.ik then
    for _, ikJson in ipairs(json.ik) do
      local ikData = IkConstraintData.new(ikJson.name)
      ikData.order = ikJson.order or 0
      ikData.bones = {}
      for _, boneName in ipairs(ikJson.bones) do
        local boneData = self:findBone(boneName)
        if boneData then
          table.insert(ikData.bones, boneData)
        end
      end
      ikData.target = self:findBone(ikJson.target)
      ikData.mix = (ikJson.mix ~= nil) and ikJson.mix or 1
      ikData.bendDirection = ikJson.bendPositive == false and -1 or 1
      ikData.compress = ikJson.compress or false
      ikData.stretch = ikJson.stretch or false
      ikData.uniform = ikJson.uniform or false
      table.insert(self.ikConstraints, ikData)
    end
  end

  -- Parse Transform constraints
  if json.transform then
    for _, transformJson in ipairs(json.transform) do
      local transformData = TransformConstraintData.new(transformJson.name)
      transformData.order = transformJson.order or 0
      transformData.bones = {}
      for _, boneName in ipairs(transformJson.bones) do
        local boneData = self:findBone(boneName)
        if boneData then
          table.insert(transformData.bones, boneData)
        end
      end
      transformData.target = self:findBone(transformJson.target)
      transformData.offsetX = (transformJson.x or 0) * self.scale
      transformData.offsetY = (transformJson.y or 0) * self.scale
      transformData.offsetRotation = transformJson.rotation or 0
      transformData.offsetScaleX = transformJson.scaleX or 0
      transformData.offsetScaleY = transformJson.scaleY or 0
      transformData.offsetShearY = transformJson.shearY or 0
      transformData.mixRotate = (transformJson.mixRotate ~= nil) and transformJson.mixRotate or 1
      local hasMixX = transformJson.mixX ~= nil
      local hasMixY = transformJson.mixY ~= nil
      local translateMix = transformJson.translateMix
      if hasMixX or hasMixY then
        transformData.mixX = hasMixX and transformJson.mixX or 0
        transformData.mixY = hasMixY and transformJson.mixY or 0
      elseif translateMix ~= nil then
        transformData.mixX = translateMix
        transformData.mixY = translateMix
      else
        transformData.mixX = 1
        transformData.mixY = 1
      end
      -- Scale/shear mixes: support unified keys if present; otherwise keep disabled by default
      local scaleMix = transformJson.scaleMix
      if scaleMix ~= nil then
        transformData.mixScaleX = scaleMix
        transformData.mixScaleY = scaleMix
      else
        transformData.mixScaleX = (transformJson.mixScaleX ~= nil) and transformJson.mixScaleX or 0
        transformData.mixScaleY = (transformJson.mixScaleY ~= nil) and transformJson.mixScaleY or 0
      end
      local shearMix = transformJson.shearMix
      transformData.mixShearY = (shearMix ~= nil) and shearMix or ((transformJson.mixShearY ~= nil) and transformJson.mixShearY or 0)
      table.insert(self.transformConstraints, transformData)
    end
  end

  -- Parse Path constraints
  if json.path then
    for _, pathJson in ipairs(json.path) do
      local pathData = PathConstraintData.new(pathJson.name)
      pathData.order = pathJson.order or 0
      pathData.bones = {}
      for _, boneName in ipairs(pathJson.bones) do
        local boneData = self:findBone(boneName)
        if boneData then
          table.insert(pathData.bones, boneData)
        end
      end
      pathData.target = self:findSlot(pathJson.target)
      pathData.positionMode = pathJson.positionMode or "percent"
      pathData.spacingMode = pathJson.spacingMode or "length"
      pathData.rotateMode = pathJson.rotateMode or "tangent"
      pathData.offsetRotation = pathJson.rotation or 0
      pathData.position = pathJson.position or 0
      pathData.spacing = pathJson.spacing or 0
      pathData.mixRotate = (pathJson.mixRotate ~= nil) and pathJson.mixRotate or 1
      pathData.mixX = (pathJson.mixX ~= nil) and pathJson.mixX or 1
      pathData.mixY = (pathJson.mixY ~= nil) and pathJson.mixY or 1
      table.insert(self.pathConstraints, pathData)
    end
  end

  -- Parse Physics constraints
  if json.physics then
    for _, physicsJson in ipairs(json.physics) do
      local physicsData = PhysicsConstraintData.new(physicsJson.name)
      physicsData.order = physicsJson.order or 0
      physicsData.bone = self:findBone(physicsJson.bone)
      
      physicsData._x = (physicsJson.x or 0) * self.scale
      physicsData._y = (physicsJson.y or 0) * self.scale
      physicsData._rotate = physicsJson.rotate or 0
      physicsData._scaleX = physicsJson.scaleX or 0
      physicsData._shearX = physicsJson.shearX or 0
      physicsData._limit = (physicsJson.limit or 5000) * self.scale
      physicsData._step = 1 / (physicsJson.fps or 60)
      
      physicsData.inertia = physicsJson.inertia or 1
      physicsData.strength = physicsJson.strength or 100
      physicsData.damping = physicsJson.damping or 1
      
      local mass = physicsJson.mass or 1
      physicsData.massInverse = 1 / mass
      
      physicsData.wind = physicsJson.wind or 0
      physicsData.gravity = physicsJson.gravity or 0
      physicsData.mix = (physicsJson.mix ~= nil) and physicsJson.mix or 1
      
      table.insert(self.physicsConstraints, physicsData)
    end
  end

  -- 解析动画数据
  if json.animations then
    local animationModule = require("spine.animation")

    for animName, animJson in pairs(json.animations) do
      local timelines = {}
      local duration = 0

      -- Parse bone timelines
      if animJson.bones then
        for boneName, boneTimelines in pairs(animJson.bones) do
          local boneIndex = self:findBoneIndex(boneName)

          if boneIndex ~= -1 then
            -- Parse rotate timeline
            if boneTimelines.rotate then
              local frameCount = #boneTimelines.rotate
              local timeline = animationModule.RotateTimeline.new(frameCount)
              timeline.boneIndex = boneIndex

              for i, frame in ipairs(boneTimelines.rotate) do
                local time = frame.time or 0
                local angle = frame.value or 0
                timeline:setFrame(i - 1, time, angle)

                -- Set linear by default, then override if curve is specified
                timeline:setLinear(i - 1)



                if frame.curve then
                  if frame.curve == "stepped" then
                    timeline:setStepped(i - 1)
                  elseif type(frame.curve) == "table" then
                    local nextFrame = boneTimelines.rotate[i+1]
                    if nextFrame then
                        local frameDuration = nextFrame.time - time
                        local valChange = (nextFrame.value or 0) - angle
                        while valChange > 180 do valChange = valChange - 360 end
                        while valChange < -180 do valChange = valChange + 360 end
                        
                        local c = frame.curve
                        local cx1 = (c[1] - time) / frameDuration
                        local cy1 = (valChange == 0) and 0 or (c[2] - angle) / valChange
                        local cx2 = (c[3] - time) / frameDuration
                        local cy2 = (valChange == 0) and 0 or (c[4] - angle) / valChange
                        timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                    end
                  end
                end

                if time > duration then duration = time end
              end

              table.insert(timelines, timeline)
            end

            -- Parse translate timeline
            if boneTimelines.translate then
              local frameCount = #boneTimelines.translate
              if frameCount > 0 then
                local timeline = animationModule.TranslateTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.translate) do
                  local time = frame.time or 0
                  local x = (frame.x or 0) * self.scale
                  local y = (frame.y or 0) * self.scale
                  timeline:setFrame(i - 1, time, x, y)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.translate[i+1]
                      if nextFrame then
                        local c = frame.curve
                        if #c == 8 then
                            local frameDuration = nextFrame.time - time
                            local xChange = (nextFrame.x or 0) * self.scale - x
                            local yChange = (nextFrame.y or 0) * self.scale - y
                            
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = (xChange == 0) and 0 or (c[2] * self.scale - x) / xChange
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = (xChange == 0) and 0 or (c[4] * self.scale - x) / xChange
                            
                            local cx3 = (c[5] - time) / frameDuration
                            local cy3 = (yChange == 0) and 0 or (c[6] * self.scale - y) / yChange
                            local cx4 = (c[7] - time) / frameDuration
                            local cy4 = (yChange == 0) and 0 or (c[8] * self.scale - y) / yChange
                            
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2, cx3, cy3, cx4, cy4)
                        else
                            timeline:setCurve(i - 1, c[1], c[2], c[3], c[4])
                        end
                      end
                    end
                  end

                  if time > duration then duration = time end
                end

                table.insert(timelines, timeline)
              end
            end

            -- Parse translatex timeline
            if boneTimelines.translatex then
              local frameCount = #boneTimelines.translatex
              if frameCount > 0 then
                local timeline = animationModule.TranslateXTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.translatex) do
                  local time = frame.time or 0
                  local val = (frame.value or 0) * self.scale
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.translatex[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) * self.scale - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] * self.scale - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] * self.scale - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end

            -- Parse translatey timeline
            if boneTimelines.translatey then
              local frameCount = #boneTimelines.translatey
              if frameCount > 0 then
                local timeline = animationModule.TranslateYTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.translatey) do
                  local time = frame.time or 0
                  local val = (frame.value or 0) * self.scale
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.translatey[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) * self.scale - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] * self.scale - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] * self.scale - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end

            -- Parse scale timeline
            if boneTimelines.scale then
              local frameCount = #boneTimelines.scale
              if frameCount > 0 then
                local timeline = animationModule.ScaleTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.scale) do
                  local time = frame.time or 0
                  local x = frame.x or 1
                  local y = frame.y or 1
                  timeline:setFrame(i - 1, time, x, y)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.scale[i+1]
                      if nextFrame then
                        local c = frame.curve
                        if #c == 8 then
                            local frameDuration = nextFrame.time - time
                            local xChange = (nextFrame.x or 1) - x
                            local yChange = (nextFrame.y or 1) - y
                            
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = (xChange == 0) and 0 or (c[2] - x) / xChange
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = (xChange == 0) and 0 or (c[4] - x) / xChange
                            
                            local cx3 = (c[5] - time) / frameDuration
                            local cy3 = (yChange == 0) and 0 or (c[6] - y) / yChange
                            local cx4 = (c[7] - time) / frameDuration
                            local cy4 = (yChange == 0) and 0 or (c[8] - y) / yChange
                            
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2, cx3, cy3, cx4, cy4)
                        else
                            timeline:setCurve(i - 1, c[1], c[2], c[3], c[4])
                        end
                      end
                    end
                  end

                  if time > duration then duration = time end
                end

                table.insert(timelines, timeline)
              end
            end

            -- Parse scalex timeline
            if boneTimelines.scalex then
              local frameCount = #boneTimelines.scalex
              if frameCount > 0 then
                local timeline = animationModule.ScaleXTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.scalex) do
                  local time = frame.time or 0
                  local val = frame.value or 0
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.scalex[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end

            -- Parse scaley timeline
            if boneTimelines.scaley then
              local frameCount = #boneTimelines.scaley
              if frameCount > 0 then
                local timeline = animationModule.ScaleYTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.scaley) do
                  local time = frame.time or 0
                  local val = frame.value or 0
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.scaley[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end

            -- Parse shear timeline
            if boneTimelines.shear then
              local frameCount = #boneTimelines.shear
              if frameCount > 0 then
                local timeline = animationModule.ShearTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.shear) do
                  local time = frame.time or 0
                  local x = frame.x or 0
                  local y = frame.y or 0
                  timeline:setFrame(i - 1, time, x, y)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.shear[i+1]
                      if nextFrame then
                        local c = frame.curve
                        if #c == 8 then
                            local frameDuration = nextFrame.time - time
                            local xChange = (nextFrame.x or 0) - x
                            local yChange = (nextFrame.y or 0) - y
                            
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = (xChange == 0) and 0 or (c[2] - x) / xChange
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = (xChange == 0) and 0 or (c[4] - x) / xChange
                            
                            local cx3 = (c[5] - time) / frameDuration
                            local cy3 = (yChange == 0) and 0 or (c[6] - y) / yChange
                            local cx4 = (c[7] - time) / frameDuration
                            local cy4 = (yChange == 0) and 0 or (c[8] - y) / yChange
                            
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2, cx3, cy3, cx4, cy4)
                        else
                            timeline:setCurve(i - 1, c[1], c[2], c[3], c[4])
                        end
                      end
                    end
                  end

                  if time > duration then duration = time end
                end

                table.insert(timelines, timeline)
              end
            end

            -- Parse shearx timeline
            if boneTimelines.shearx then
              local frameCount = #boneTimelines.shearx
              if frameCount > 0 then
                local timeline = animationModule.ShearXTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.shearx) do
                  local time = frame.time or 0
                  local val = frame.value or 0
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.shearx[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end

            -- Parse sheary timeline
            if boneTimelines.sheary then
              local frameCount = #boneTimelines.sheary
              if frameCount > 0 then
                local timeline = animationModule.ShearYTimeline.new(frameCount)
                timeline.boneIndex = boneIndex

                for i, frame in ipairs(boneTimelines.sheary) do
                  local time = frame.time or 0
                  local val = frame.value or 0
                  timeline:setFrame(i - 1, time, val)

                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = boneTimelines.sheary[i+1]
                      if nextFrame then
                          local frameDuration = nextFrame.time - time
                          local valChange = (nextFrame.value or 0) - val
                          
                          local c = frame.curve
                          local cx1 = (c[1] - time) / frameDuration
                          local cy1 = (valChange == 0) and 0 or (c[2] - val) / valChange
                          local cx2 = (c[3] - time) / frameDuration
                          local cy2 = (valChange == 0) and 0 or (c[4] - val) / valChange
                          timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end
          end
        end
      end

      -- Parse IK timelines
            if animJson.ik then
              for constraintName, timelineMap in pairs(animJson.ik) do
                local constraintIndex = -1
                for i, c in ipairs(self.ikConstraints) do
                  if c.name == constraintName then
                    constraintIndex = i
                    break
                  end
                end

                if constraintIndex ~= -1 then
                  local frameCount = #timelineMap
                  local timeline = animationModule.IkConstraintTimeline.new(frameCount)
                  timeline.ikConstraintIndex = constraintIndex

                  for i, frame in ipairs(timelineMap) do
                    local time = frame.time or 0
                    local mix = frame.mix or 1
                    local bendPositive = frame.bendPositive
                    if bendPositive == nil then bendPositive = true end
                    local bendDirection = bendPositive and 1 or -1
                    local compress = frame.compress or false
                    local stretch = frame.stretch or false

                    timeline:setFrame(i - 1, time, mix, bendDirection, compress, stretch)

                    if frame.curve then
                      if frame.curve == "stepped" then
                        timeline:setStepped(i - 1)
                      elseif type(frame.curve) == "table" then
                        local nextFrame = timelineMap[i+1]
                        if nextFrame then
                            local frameDuration = nextFrame.time - time
                            local valChange = (nextFrame.mix or 1) - mix
                            local c = frame.curve
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = (valChange == 0) and 0 or (c[2] - mix) / valChange
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = (valChange == 0) and 0 or (c[4] - mix) / valChange
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                        end
                      end
                    end

                    if time > duration then duration = time end
                  end
                  table.insert(timelines, timeline)
                end
              end
            end

      -- Parse Transform timelines
            if animJson.transform then
              for constraintName, timelineMap in pairs(animJson.transform) do
                local constraintIndex = -1
                for i, c in ipairs(self.transformConstraints) do
                  if c.name == constraintName then
                    constraintIndex = i
                    break
                  end
                end

                if constraintIndex ~= -1 then
                  local frameCount = #timelineMap
                  local timeline = animationModule.TransformConstraintTimeline.new(frameCount)
                  timeline.transformConstraintIndex = constraintIndex

                  for i, frame in ipairs(timelineMap) do
                    local time = frame.time or 0
                    local rotateMix = frame.mixRotate or frame.rotateMix or 1
                    local translateMix = frame.mixX or frame.translateMix or 1
                    local scaleMix = frame.mixScaleX or frame.scaleMix or 1
                    local shearMix = frame.mixShearY or frame.shearMix or 1

                    timeline:setFrame(i - 1, time, rotateMix, translateMix, scaleMix, shearMix)

                    if frame.curve then
                      if frame.curve == "stepped" then
                        timeline:setStepped(i - 1)
                      elseif type(frame.curve) == "table" then
                        local nextFrame = timelineMap[i+1]
                        if nextFrame then
                            local frameDuration = nextFrame.time - time
                            local c = frame.curve
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = c[2]
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = c[4]
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                        end
                      end
                    end

                    if time > duration then duration = time end
                  end
                  table.insert(timelines, timeline)
                end
              end
            end

      -- Parse Path timelines
      if animJson.path then
        for constraintName, timelineMap in pairs(animJson.path) do
          local constraintIndex = -1
          for i, c in ipairs(self.pathConstraints) do
            if c.name == constraintName then
              constraintIndex = i
              break
            end
          end

          if constraintIndex ~= -1 then
            local defaultData = self.pathConstraints[constraintIndex]
            local isArray = type(timelineMap) == "table" and (#timelineMap > 0)
            if isArray then
              local frameCount = #timelineMap
              if frameCount > 0 then
                local timeline = animationModule.PathConstraintTimeline.new(frameCount)
                timeline.pathConstraintIndex = constraintIndex
                for i, frame in ipairs(timelineMap) do
                  local time = frame.time or 0
                  local position = frame.position or frame.value or (defaultData.position or 0)
                  local spacing = frame.spacing or (defaultData.spacing or 0)
                  local rotateMix = frame.rotateMix or frame.mixRotate or 1
                  local translateMix = frame.translateMix or frame.mixX or frame.mixY or (defaultData.mixX or 1)
                  timeline:setFrame(i - 1, time, position, spacing, rotateMix, translateMix)
                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = timelineMap[i+1]
                      if nextFrame then
                        local frameDuration = nextFrame.time - time
                        local c = frame.curve
                        local cx1 = (c[1] - time) / frameDuration
                        local cy1 = c[2]
                        local cx2 = (c[3] - time) / frameDuration
                        local cy2 = c[4]
                        timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            else
              local positions = timelineMap.position
              local spacings = timelineMap.spacing
              local mixRotates = timelineMap.mixRotate or timelineMap.rotateMix
              local mixXs = timelineMap.mixX
              local mixYs = timelineMap.mixY
              local translateMixes = timelineMap.translateMix

              local sourceType, source
              if positions and #positions > 0 then
                sourceType, source = "position", positions
              elseif spacings and #spacings > 0 then
                sourceType, source = "spacing", spacings
              elseif mixRotates and #mixRotates > 0 then
                sourceType, source = "rotateMix", mixRotates
              elseif translateMixes and #translateMixes > 0 then
                sourceType, source = "translateMix", translateMixes
              elseif mixXs and #mixXs > 0 then
                sourceType, source = "mixX", mixXs
              elseif mixYs and #mixYs > 0 then
                sourceType, source = "mixY", mixYs
              end

              if source then
                local frameCount = #source
                local timeline = animationModule.PathConstraintTimeline.new(frameCount)
                timeline.pathConstraintIndex = constraintIndex
                for i, frame in ipairs(source) do
                  local time = frame.time or 0
                  local position = (sourceType == "position") and (frame.value or frame.position or 0) or (defaultData.position or 0)
                  local spacing = (sourceType == "spacing") and (frame.value or frame.spacing or 0) or (defaultData.spacing or 0)
                  local rotateMix = (sourceType == "rotateMix") and (frame.mixRotate or frame.rotateMix or frame.value or 1) or (defaultData.mixRotate or 1)
                  local translateMix
                  if sourceType == "translateMix" then
                    translateMix = frame.translateMix or frame.value or (defaultData.mixX or 1)
                  elseif sourceType == "mixX" then
                    translateMix = frame.mixX or frame.value or (defaultData.mixX or 1)
                  elseif sourceType == "mixY" then
                    translateMix = frame.mixY or frame.value or (defaultData.mixY or 1)
                  else
                    translateMix = defaultData.mixX or 1
                  end
                  timeline:setFrame(i - 1, time, position, spacing, rotateMix, translateMix)
                  if frame.curve then
                    if frame.curve == "stepped" then
                      timeline:setStepped(i - 1)
                    elseif type(frame.curve) == "table" then
                      local nextFrame = source[i+1]
                      if nextFrame then
                        local frameDuration = nextFrame.time - time
                        
                        -- Calculate value change for normalization
                        local currentVal = 0
                        local nextVal = 0
                        
                        if sourceType == "position" then
                            currentVal = position
                            nextVal = (nextFrame.value or nextFrame.position or 0)
                        elseif sourceType == "spacing" then
                            currentVal = spacing
                            nextVal = (nextFrame.value or nextFrame.spacing or 0)
                        elseif sourceType == "rotateMix" then
                            currentVal = rotateMix
                            nextVal = (nextFrame.mixRotate or nextFrame.rotateMix or nextFrame.value or 1)
                        elseif sourceType == "translateMix" then
                            currentVal = translateMix
                            nextVal = (nextFrame.translateMix or nextFrame.value or (defaultData.mixX or 1))
                        elseif sourceType == "mixX" then
                            currentVal = translateMix
                            nextVal = (nextFrame.mixX or nextFrame.value or (defaultData.mixX or 1))
                        elseif sourceType == "mixY" then
                            currentVal = translateMix
                            nextVal = (nextFrame.mixY or nextFrame.value or (defaultData.mixY or 1))
                        end
                        
                        local valChange = nextVal - currentVal
                        
                        local c = frame.curve
                        local cx1 = (c[1] - time) / frameDuration
                        local cy1 = (valChange == 0) and 0 or (c[2] - currentVal) / valChange
                        local cx2 = (c[3] - time) / frameDuration
                        local cy2 = (valChange == 0) and 0 or (c[4] - currentVal) / valChange
                        timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                      end
                    end
                  end
                  if time > duration then duration = time end
                end
                table.insert(timelines, timeline)
              end
            end
          end
        end
      end

      -- Parse Physics timelines
      if animJson.physics then
        for constraintName, timelineMap in pairs(animJson.physics) do
          local constraintIndex = -1
          for i, c in ipairs(self.physicsConstraints) do
            if c.name == constraintName then
              constraintIndex = i
              break
            end
          end

          if constraintIndex ~= -1 then
            for typeName, timelineData in pairs(timelineMap) do
                local timelineType = nil
                if typeName == "inertia" then timelineType = animationModule.PhysicsConstraintTimeline.INERTIA
                elseif typeName == "strength" then timelineType = animationModule.PhysicsConstraintTimeline.STRENGTH
                elseif typeName == "damping" then timelineType = animationModule.PhysicsConstraintTimeline.DAMPING
                elseif typeName == "massInverse" then timelineType = animationModule.PhysicsConstraintTimeline.MASS_INVERSE
                elseif typeName == "wind" then timelineType = animationModule.PhysicsConstraintTimeline.WIND
                elseif typeName == "gravity" then timelineType = animationModule.PhysicsConstraintTimeline.GRAVITY
                elseif typeName == "mix" then timelineType = animationModule.PhysicsConstraintTimeline.MIX
                end

                if timelineType then
                    local frameCount = #timelineData
                    local timeline = animationModule.PhysicsConstraintTimeline.new(frameCount, timelineType)
                    timeline.physicsConstraintIndex = constraintIndex
                    
                    for i, frame in ipairs(timelineData) do
                        local time = frame.time or 0
                        local value = frame.value or 0
                        timeline:setFrame(i - 1, time, value)
                        
                        if frame.curve then
                            if frame.curve == "stepped" then
                                timeline:setStepped(i - 1)
                            elseif type(frame.curve) == "table" then
                                local nextFrame = timelineData[i+1]
                                if nextFrame then
                                    local frameDuration = nextFrame.time - time
                                    local valChange = (nextFrame.value or 0) - value
                                    
                                    local c = frame.curve
                                    local cx1 = (c[1] - time) / frameDuration
                                    local cy1 = (valChange == 0) and 0 or (c[2] - value) / valChange
                                    local cx2 = (c[3] - time) / frameDuration
                                    local cy2 = (valChange == 0) and 0 or (c[4] - value) / valChange
                                    
                                    timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                                end
                            end
                        end
                        
                        if time > duration then duration = time end
                    end
                    table.insert(timelines, timeline)
                elseif typeName == "reset" then
                     local frameCount = #timelineData
                     local timeline = animationModule.PhysicsConstraintResetTimeline.new(frameCount)
                     timeline.physicsConstraintIndex = constraintIndex
                     
                     for i, frame in ipairs(timelineData) do
                         local time = frame.time or 0
                         timeline:setFrame(i - 1, time)
                         if time > duration then duration = time end
                     end
                     table.insert(timelines, timeline)
                end
            end
          end
        end
      end

      -- Parse slot timelines (attachment switching, color, etc.)
      if animJson.slots then
        for slotName, slotTimelines in pairs(animJson.slots) do
          local slotIndex = self:findSlotIndex(slotName)

          if slotIndex ~= -1 then
            -- Parse color timeline (rgba)
            if slotTimelines.rgba or slotTimelines.color then
              local timelineData = slotTimelines.rgba or slotTimelines.color
              local frameCount = #timelineData
              local timeline = animationModule.ColorTimeline.new(frameCount)
              timeline.slotIndex = slotIndex

              for i, frame in ipairs(timelineData) do
                local time = frame.time or 0
                local color = frame.color or "ffffffff"
                local r, g, b, a = utils.hexToColor(color)
                timeline:setFrame(i - 1, time, r, g, b, a)

                if frame.curve then
                  if frame.curve == "stepped" then
                    timeline:setStepped(i - 1)
                  elseif type(frame.curve) == "table" then
                    local nextFrame = timelineData[i+1]
                    if nextFrame then
                        local frameDuration = nextFrame.time - time
                        local c = frame.curve
                        local cx1 = (c[1] - time) / frameDuration
                        local cy1 = c[2]
                        local cx2 = (c[3] - time) / frameDuration
                        local cy2 = c[4]
                        timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                    end
                  end
                end

                if time > duration then duration = time end
              end

              table.insert(timelines, timeline)
            end

            -- Parse two color timeline (rgba2)
            if slotTimelines.rgba2 then
              local timelineData = slotTimelines.rgba2
              local frameCount = #timelineData
              local timeline = animationModule.TwoColorTimeline.new(frameCount)
              timeline.slotIndex = slotIndex

              for i, frame in ipairs(timelineData) do
                local time = frame.time or 0
                local light = frame.light or "ffffffff"
                local dark = frame.dark or "000000"
                local r, g, b, a = utils.hexToColor(light)
                local r2, g2, b2 = utils.hexToColor(dark)
                timeline:setFrame(i - 1, time, r, g, b, a, r2, g2, b2)

                if frame.curve then
                  if frame.curve == "stepped" then
                    timeline:setStepped(i - 1)
                  elseif type(frame.curve) == "table" then
                    local nextFrame = timelineData[i+1]
                    if nextFrame then
                        local frameDuration = nextFrame.time - time
                        local c = frame.curve
                        local cx1 = (c[1] - time) / frameDuration
                        local cy1 = c[2]
                        local cx2 = (c[3] - time) / frameDuration
                        local cy2 = c[4]
                        timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                    end
                  end
                end

                if time > duration then duration = time end
              end

              table.insert(timelines, timeline)
            end

            -- Parse attachment timeline
            if slotTimelines.attachment then
              local frameCount = #slotTimelines.attachment
              local timeline = animationModule.AttachmentTimeline.new(frameCount)
              timeline.slotIndex = slotIndex

              for i, frame in ipairs(slotTimelines.attachment) do
                local time = frame.time or 0
                local attachmentName = frame.name
                timeline:setFrame(i - 1, time, attachmentName)

                if time > duration then duration = time end
              end

              table.insert(timelines, timeline)
            end
          end
        end
      end

      -- Parse deform timelines under attachments
      if animJson.attachments then
        for skinName, skinMap in pairs(animJson.attachments) do
          for slotName, slotMap in pairs(skinMap) do
            local slotIndex = self:findSlotIndex(slotName)
            if slotIndex ~= -1 then
              for attachmentName, attachmentTimelines in pairs(slotMap) do
                if attachmentTimelines.deform then
                  local framesData = attachmentTimelines.deform
                  local frameCount = #framesData
                  if frameCount > 0 then
                    local timeline = animationModule.DeformTimeline.new(frameCount)
                    timeline.slotIndex = slotIndex
                    timeline.attachmentName = attachmentName

                    for i, frame in ipairs(framesData) do
                      local time = frame.time or 0
                      local offset = frame.offset or 0
                      local vertices = frame.vertices or {}
                      timeline:setFrame(i - 1, time, vertices, offset)

                      if frame.curve then
                        if frame.curve == "stepped" then
                          timeline:setStepped(i - 1)
                        elseif type(frame.curve) == "table" then
                          local nextFrame = framesData[i+1]
                          if nextFrame then
                            local frameDuration = nextFrame.time - time
                            local c = frame.curve
                            local cx1 = (c[1] - time) / frameDuration
                            local cy1 = c[2]
                            local cx2 = (c[3] - time) / frameDuration
                            local cy2 = c[4]
                            timeline:setCurve(i - 1, cx1, cy1, cx2, cy2)
                          end
                        end
                      end

                      if time > duration then duration = time end
                    end

                    table.insert(timelines, timeline)
                  end
                end
              end
            end
          end
        end
      end

      -- Create animation
      local animation = animationModule.Animation.new(animName, timelines, duration)
      self.animations[animName] = animation
    end
  end

  self:linkMeshes()
end

function SkeletonData:linkMeshes()
  for _, linkedMesh in ipairs(self.linkedMeshes) do
    local skin = linkedMesh.skinName and self.skins[linkedMesh.skinName] or self.defaultSkin
    if not skin then
       skin = self:findSkin(linkedMesh.skinName)
    end
    if not skin then 
        print("LinkedMesh error: Skin not found: " .. tostring(linkedMesh.skinName))
        goto continue 
    end
    
    local parent = skin:getAttachment(self:findSlotIndex(linkedMesh.slotName), linkedMesh.parentName)
    if not parent then
        print("LinkedMesh error: Parent mesh not found: " .. tostring(linkedMesh.parentName))
        goto continue 
    end
    
    linkedMesh.mesh.parentMesh = parent
    linkedMesh.mesh.inheritDeform = linkedMesh.inheritTimeline -- Set inheritDeform property
    linkedMesh.mesh:updateRegion()
    
    -- Copy properties from parent
    linkedMesh.mesh.bones = parent.bones
    linkedMesh.mesh.weights = parent.weights
    linkedMesh.mesh.vertices = parent.vertices
    linkedMesh.mesh.worldVerticesLength = parent.worldVerticesLength
    linkedMesh.mesh.regionUVs = parent.regionUVs
    linkedMesh.mesh.triangles = parent.triangles
    linkedMesh.mesh.hullLength = parent.hullLength
    linkedMesh.mesh.edges = parent.edges
    linkedMesh.mesh.width = parent.width
    linkedMesh.mesh.height = parent.height

    if not linkedMesh.mesh.region then
          -- Try to use the saved loader to find the region
          if linkedMesh.loader and linkedMesh.loader.findRegion then
              local region = linkedMesh.loader:findRegion(linkedMesh.mesh.path)
              if region then
                  linkedMesh.mesh.region = region
              end
          end
          
          -- Fallback to parent region if still nil
          if not linkedMesh.mesh.region and parent.region then
               linkedMesh.mesh.region = parent.region
          end

          -- If still nil, try to find region using attachment name (not path)
          if not linkedMesh.mesh.region then
               print("Error: LinkedMesh has no region and could not resolve it: " .. (linkedMesh.mesh.name or "unnamed") .. " (path: " .. tostring(linkedMesh.mesh.path) .. ")")
          end
     end
    
    if linkedMesh.mesh.updateRegion then
        linkedMesh.mesh:updateRegion()
    else
        print("Warning: Linked mesh missing updateRegion method: " .. (linkedMesh.mesh.name or "unnamed"))
    end

    ::continue::
  end
  self.linkedMeshes = {}
end

function SkeletonData:createAttachment(attachmentMap, attachmentName, attachmentLoader, slotName)
  local attachmentType = attachmentMap.type or "region"

  if attachmentType == "region" then
    local path = attachmentMap.path or attachmentMap.name or attachmentName
    local attachment
    if attachmentLoader and attachmentLoader.newRegionAttachment then
        attachment = attachmentLoader:newRegionAttachment(nil, attachmentName, path)
    end

    if not attachment then
        attachment = RegionAttachment.new(attachmentName)
    end

    attachment.path = path
    attachment.x = (attachmentMap.x or 0) * self.scale
    attachment.y = (attachmentMap.y or 0) * self.scale
    attachment.rotation = attachmentMap.rotation or 0
    attachment.scaleX = attachmentMap.scaleX or 1
    attachment.scaleY = attachmentMap.scaleY or 1
    attachment.width = (attachmentMap.width or 0) * self.scale
    attachment.height = (attachmentMap.height or 0) * self.scale

    if attachmentMap.color then
      attachment.color:fromHex(attachmentMap.color)
    end

    if attachment.updateRegion then
        attachment:updateRegion()
    end

    return attachment
  elseif attachmentType == "mesh" then
    local path = attachmentMap.path or attachmentMap.name or attachmentName
    local attachment
    if attachmentLoader and attachmentLoader.newMeshAttachment then
        attachment = attachmentLoader:newMeshAttachment(nil, attachmentName, path)
    end

    if not attachment then
        attachment = MeshAttachment.new(attachmentName)
    end

    attachment.path = path
    attachment.width = (attachmentMap.width or 0) * self.scale
    attachment.height = (attachmentMap.height or 0) * self.scale

    if attachmentMap.color then
      attachment.color:fromHex(attachmentMap.color)
    end

    -- Parse mesh data
    -- Calculate normalized UVs (0-1) relative to the region
    attachment.regionUVs = {}
    -- JSON UVs are normalized (0-1) and relative to the image (unrotated)
    if attachmentMap.uvs then
        for i, v in ipairs(attachmentMap.uvs) do
            attachment.regionUVs[i] = v
        end
    end
    
    attachment.uvs = {}
    -- Initialize uvs with 0 (will be updated by updateRegion)
    for i = 1, #attachmentMap.uvs do
        attachment.uvs[i] = 0
    end
    
    attachment.worldVerticesLength = #attachment.uvs

    -- Convert triangles to 1-based indices for Lua/Love2D
    if attachmentMap.triangles then
        attachment.triangles = {}
        for i, index in ipairs(attachmentMap.triangles) do
            attachment.triangles[i] = index + 1
            if attachment.triangles[i] == 0 then
                print("ERROR: Triangle index is 0 at " .. i .. ". Original: " .. index)
            end
        end
        -- print("DEBUG: Parsed " .. #attachment.triangles .. " triangles for " .. attachmentName)
    else
        attachment.triangles = {}
    end

    attachment.hullLength = (attachmentMap.hull or 0) * 2
    attachment.edges = attachmentMap.edges

    if attachmentMap.vertices then
        local jsonVertices = attachmentMap.vertices
        local uvs = attachmentMap.uvs

        if #jsonVertices == #uvs then
            -- Non-weighted mesh
            attachment.vertices = {}
            for i, v in ipairs(jsonVertices) do
                attachment.vertices[i] = v * self.scale
            end
        else
            -- Weighted mesh
            attachment.vertices = {}
            attachment.bones = {}
            attachment.weights = {}

            local v = 1
            local b = 1
            local w = 1
            local i = 1

            while i <= #jsonVertices do
                local boneCount = jsonVertices[i]
                attachment.bones[b] = boneCount
                b = b + 1
                i = i + 1

                for _ = 1, boneCount do
                    -- Bone index (JSON is 0-based, Lua is 1-based)
                    attachment.bones[b] = jsonVertices[i] + 1
                    b = b + 1
                    i = i + 1

                    -- Vertex x, y
                    attachment.vertices[v] = jsonVertices[i] * self.scale
                    attachment.vertices[v+1] = jsonVertices[i+1] * self.scale
                    v = v + 2
                    i = i + 2

                    -- Weigh
                    attachment.weights[w] = jsonVertices[i]
                    w = w + 1
                    i = i + 1
                end
            end
        end
    end

    if attachment.updateRegion then
        attachment:updateRegion()
    end

    return attachment
  elseif attachmentType == "path" then
    local attachment = PathAttachment.new(attachmentName)
    attachment.closed = attachmentMap.closed or false
    if attachmentMap.constantSpeed ~= nil then
        attachment.constantSpeed = attachmentMap.constantSpeed
    else
        attachment.constantSpeed = true
    end
    attachment.lengths = attachmentMap.lengths or {}
    if #attachment.lengths > 0 then
        attachment.length = attachment.lengths[#attachment.lengths]
    else
        attachment.length = 0
    end
    
    if attachmentMap.color then
      attachment.color:fromHex(attachmentMap.color)
    end

    if attachmentMap.vertices then
        local jsonVertices = attachmentMap.vertices
        local vertexCount = attachmentMap.vertexCount or 0
        attachment.worldVerticesLength = vertexCount * 2
        
        -- Logic to detect weighted vs non-weighted
        local isWeighted = #jsonVertices > vertexCount * 2
        
        if not isWeighted then
            -- Non-weighted
            attachment.vertices = {}
            for i, v in ipairs(jsonVertices) do
                attachment.vertices[i] = v * self.scale
            end
        else
            -- Weighted
            attachment.vertices = {}
            attachment.bones = {}
            attachment.weights = {}

            local v = 1
            local b = 1
            local w = 1
            local i = 1

            while i <= #jsonVertices do
                local boneCount = jsonVertices[i]
                attachment.bones[b] = boneCount
                b = b + 1
                i = i + 1

                for _ = 1, boneCount do
                    -- Bone index (JSON is 0-based, Lua is 1-based)
                    attachment.bones[b] = jsonVertices[i] + 1
                    b = b + 1
                    i = i + 1

                    -- Vertex x, y
                    attachment.vertices[v] = jsonVertices[i] * self.scale
                    attachment.vertices[v+1] = jsonVertices[i+1] * self.scale
                    v = v + 2
                    i = i + 2

                    -- Weight
                    attachment.weights[w] = jsonVertices[i]
                    w = w + 1
                    i = i + 1
                end
            end
        end
    end
    
    return attachment
  elseif attachmentType == "boundingbox" then
    local attachment = BoundingBoxAttachment.new(attachmentName)

    if attachmentMap.color then
      attachment.color:fromHex(attachmentMap.color)
    end

    -- 这里应该解析顶点数据
    return attachment
  elseif attachmentType == "linkedmesh" then
    local path = attachmentMap.path or attachmentMap.name or attachmentName
    local attachment
    if attachmentLoader and attachmentLoader.newMeshAttachment then
        attachment = attachmentLoader:newMeshAttachment(nil, attachmentName, path)
    end
    
    if not attachment then
        attachment = MeshAttachment.new(attachmentName)
    end

    attachment.path = path
    if attachmentMap.color then
      attachment.color:fromHex(attachmentMap.color)
    end
    
    local inheritDeform = attachmentMap.deform
    
    table.insert(self.linkedMeshes, {
        mesh = attachment,
        skinName = attachmentMap.skin,
        slotName = slotName,
        parentName = attachmentMap.parent,
        inheritTimeline = inheritDeform,
        loader = attachmentLoader -- Save loader for later resolution
    })
    
    return attachment
  elseif attachmentType == "clipping" then
    local attachment
    if attachmentLoader and attachmentLoader.newClippingAttachment then
        attachment = attachmentLoader:newClippingAttachment(nil, attachmentName)
    end

    if not attachment then
        attachment = ClippingAttachment.new(attachmentName)
    end

    -- 'end' is a Lua keyword, so we need to use bracket notation
    attachment.endSlot = attachmentMap["end"]

    -- Parse vertices
    if attachmentMap.vertices then
        local jsonVertices = attachmentMap.vertices
        local vertexCount = attachmentMap.vertexCount or 0
        attachment.worldVerticesLength = vertexCount * 2
        attachment.vertexCount = vertexCount
        
        -- Logic to detect weighted vs non-weighted
        local isWeighted = #jsonVertices > vertexCount * 2
        
        if not isWeighted then
            -- Non-weighted
            attachment.vertices = {}
            for i, v in ipairs(jsonVertices) do
                attachment.vertices[i] = v * self.scale
            end
        else
            -- Weighted
            attachment.vertices = {}
            attachment.bones = {}
            attachment.weights = {}
            
            local v = 1
            local b = 1
            local w = 1
            local i = 1
            
            while i <= #jsonVertices do
                local boneCount = jsonVertices[i]
                attachment.bones[b] = boneCount
                b = b + 1
                i = i + 1
                
                for _ = 1, boneCount do
                    -- Bone index (JSON is 0-based, Lua is 1-based)
                    attachment.bones[b] = jsonVertices[i] + 1
                    b = b + 1
                    i = i + 1
                    
                    -- Vertex x, y
                    attachment.vertices[v] = jsonVertices[i] * self.scale
                    attachment.vertices[v+1] = jsonVertices[i+1] * self.scale
                    v = v + 2
                    i = i + 2
                    
                    -- Weight
                    attachment.weights[w] = jsonVertices[i]
                    w = w + 1
                    i = i + 1
                end
            end
        end
    end

    return attachment
  else
    print("Unknown attachment type: " .. attachmentType)
    return nil
  end
end

function SkeletonData:findBone(boneName)
  for _, bone in ipairs(self.bones) do
    if bone.name == boneName then
      return bone
    end
  end
  return nil
end

function SkeletonData:findBoneIndex(boneName)
  for i, bone in ipairs(self.bones) do
    if bone.name == boneName then
      return i
    end
  end
  return -1
end

function SkeletonData:findSlot(slotName)
  for _, slot in ipairs(self.slots) do
    if slot.name == slotName then
      return slot
    end
  end
  return nil
end

function SkeletonData:findSlotIndex(slotName)
  for i, slot in ipairs(self.slots) do
    if slot.name == slotName then
      return i
    end
  end
  return -1
end

function SkeletonData:findSkin(skinName)
  return self.skins[skinName]
end

function SkeletonData:findEvent(eventName)
  return self.events[eventName]
end

function SkeletonData:findAnimation(animationName)
  return self.animations[animationName]
end

-- AnimationStateData for managing animation mixing
local AnimationStateData = setmetatable({}, {__index = BaseData})
AnimationStateData.__index = AnimationStateData

function AnimationStateData.new(skeletonData)
  local self = setmetatable(BaseData.new(), AnimationStateData)
  self.skeletonData = skeletonData
  self.animationToMixTime = {} -- Mix times between animations
  self.defaultMix = 0.25 -- Default mix time in seconds
  return self
end

function AnimationStateData:setMix(fromAnimation, toAnimation, duration)
  if not self.animationToMixTime[fromAnimation] then
    self.animationToMixTime[fromAnimation] = {}
  end
  self.animationToMixTime[fromAnimation][toAnimation] = duration
end

function AnimationStateData:getMix(fromAnimation, toAnimation)
  local fromTable = self.animationToMixTime[fromAnimation]
  if fromTable then
    local mixTime = fromTable[toAnimation]
    if mixTime then
      return mixTime
    end
  end
  return self.defaultMix
end

function AnimationStateData:setDefaultMix(duration)
  self.defaultMix = duration or self.defaultMix
end

-- 导出数据模块
data.BaseData = BaseData
data.BoneData = BoneData
data.SlotData = SlotData
data.Attachment = Attachment
data.RegionAttachment = RegionAttachment
data.MeshAttachment = MeshAttachment
data.PathAttachment = PathAttachment
data.BoundingBoxAttachment = BoundingBoxAttachment
data.ClippingAttachment = ClippingAttachment
data.Skin = Skin
data.EventData = EventData
data.SkeletonData = SkeletonData
data.AnimationStateData = AnimationStateData
data.IkConstraintData = IkConstraintData
data.TransformConstraintData = TransformConstraintData
data.PathConstraintData = PathConstraintData
data.PhysicsConstraintData = PhysicsConstraintData

return data
