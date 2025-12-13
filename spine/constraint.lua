-- Spine Love2D Runtime - Constraint System
-- Implements IK, transform, and path constraints for bone manipulation

local mathModule = require("spine.math")
local utilsModule = require("spine.utils")

local math_abs = math.abs
local math_atan2 = math.atan2
local math_cos = math.cos
local math_sin = math.sin
local math_sqrt = math.sqrt
local math_rad = math.rad
local math_deg = math.deg
local math_acos = math.acos
local math_asin = math.asin
local math_pi = math.pi


local IkConstraint = {}
IkConstraint.__index = IkConstraint

function IkConstraint.new(data, skeleton)
    local self = setmetatable({}, IkConstraint)
    self.data = data
    self.bones = {}
    self.target = nil
    self.mix = data.mix
    self.softness = data.softness or 0
    self.bendDirection = data.bendDirection
    self.compress = data.compress
    self.stretch = data.stretch
    self.uniform = data.uniform
    
    -- Find bones
    for _, boneData in ipairs(data.bones) do
        local bone = skeleton:findBone(boneData.name)
        if bone then
            table.insert(self.bones, bone)
        end
    end
    
    -- Find target bone
    if data.target then
        self.target = skeleton:findBone(data.target.name)
    end
    -- Detect if bones are in reverse hierarchy order (Child -> Parent)
    -- and if so, reverse them to match standard Path direction (Parent -> Child)
    -- This fixes issues where bones defined Foot->Hip are mapped to a Hip->Foot path.
    local isReverse = false
    if #self.bones > 1 then
        isReverse = true
        for i = 1, #self.bones - 1 do
            if self.bones[i].parent ~= self.bones[i+1] then
                isReverse = false
                break
            end
        end
    end
    
    if isReverse then
        -- print("PathConstraint: Detected reverse bone order for " .. data.name .. ". Reversing...")
        local reversed = {}
        for i = #self.bones, 1, -1 do
            table.insert(reversed, self.bones[i])
        end
        self.bones = reversed
    end
    
    return self
end

function IkConstraint:setToSetupPose()
    self.mix = self.data.mix
    self.softness = self.data.softness or 0
    self.bendDirection = self.data.bendDirection
    self.compress = self.data.compress
    self.stretch = self.data.stretch
    self.uniform = self.data.uniform
end

function IkConstraint:apply()
    if #self.bones == 1 then
        self:apply1(self.bones[1], self.target, self.mix)
    elseif #self.bones == 2 then
        self:apply2(self.bones[1], self.bones[2], self.target, self.mix, self.bendDirection, self.compress, self.stretch, self.uniform)
    end
end

function IkConstraint:apply1(bone, target, alpha)
    local pp = bone.parent
    local id = 1 / (pp.a * pp.d - pp.b * pp.c)
    local x = target.worldX - pp.worldX
    local y = target.worldY - pp.worldY
    local tx = (x * pp.d - y * pp.b) * id - bone.x
    local ty = (y * pp.a - x * pp.c) * id - bone.y
    local rotationIK = math_deg(math_atan2(ty, tx))
    
    if bone.scaleX < 0 then rotationIK = rotationIK + 180 end
    
    if rotationIK > 180 then rotationIK = rotationIK - 360
    elseif rotationIK < -180 then rotationIK = rotationIK + 360 end
    
    local rotation = bone.rotation
    local r = rotationIK - rotation
    
    if r > 180 then r = r - 360
    elseif r < -180 then r = r + 360 end
    
    bone.rotation = rotation + r * alpha
    bone:updateWorldTransform()
end

function IkConstraint:apply2(parent, child, target, alpha, bendDirection, compress, stretch, uniform)
    -- DEBUG
    -- print(string.format("IkConstraint:apply2 Name=%s Bend=%d Alpha=%.3f", self.data.name, bendDirection, alpha))

    if alpha == 0 then
        child:updateWorldTransform()
        return
    end
    
    local px = parent.x
    local py = parent.y
    local psx = parent.scaleX
    local psy = parent.scaleY
    local csx = child.scaleX
    local os1, os2, s2
    
    if psx < 0 then
        psx = -psx
        os1 = 180
        s2 = -1
    else
        os1 = 0
        s2 = 1
    end
    
    if psy < 0 then
        psy = -psy
        s2 = -s2
    end
    
    if csx < 0 then
        csx = -csx
        os2 = 180
    else
        os2 = 0
    end
    
    local cx = child.x
    local cy, cwx, cwy
    local a = parent.a
    local b = parent.b
    local c = parent.c
    local d = parent.d
    
    local u = math_abs(psx - psy) <= 0.0001
    
    if not u or stretch then
        cy = 0
        cwx = a * cx + parent.worldX
        cwy = c * cx + parent.worldY
    else
        cy = child.y
        cwx = a * cx + b * cy + parent.worldX
        cwy = c * cx + d * cy + parent.worldY
    end
    
    local pp = parent.parent
    a = pp.a
    b = pp.b
    c = pp.c
    d = pp.d
    
    local id = a * d - b * c
    local x = cwx - pp.worldX
    local y = cwy - pp.worldY
    
    if math_abs(id) <= 0.0001 then id = 0 else id = 1 / id end
    
    local dx = (x * d - y * b) * id - px
    local dy = (y * a - x * c) * id - py
    local l1 = math_sqrt(dx * dx + dy * dy)
    local l2 = child.data.length * csx
    local a1, a2
    
    if l1 < 0.0001 then
        self:apply1(parent, target, alpha)
        child:updateWorldTransform(cx, cy, 0, child.scaleX, child.scaleY, child.shearX, child.shearY)
        return
    end
    
    x = target.worldX - pp.worldX
    y = target.worldY - pp.worldY
    local tx = (x * d - y * b) * id - px
    local ty = (y * a - x * c) * id - py
    local dd = tx * tx + ty * ty
    
    if self.softness and self.softness ~= 0 then
        local softness = self.softness * psx * (csx + 1) * 0.5
        local td = math_sqrt(dd)
        local sd = td - l1 - l2 * psx + softness
        if sd > 0 then
            local p = math.min(1, sd / (softness * 2)) - 1
            p = (sd - softness * (1 - p * p)) / td
            tx = tx - p * tx
            ty = ty - p * ty
            dd = tx * tx + ty * ty
        end
    end
    
    local outer_break = false
    
    if u then
        l2 = l2 * psx
        local cos = (dd - l1 * l1 - l2 * l2) / (2 * l1 * l2)
        if cos < -1 then
            cos = -1
            a2 = math_pi * bendDirection
            if compress then
                local a_scale = (math_sqrt(dd) / (l1 + l2) - 1) * alpha + 1
                psx = psx * a_scale
            end
        elseif cos > 1 then
            cos = 1
            a2 = 0
            if stretch then
                local a_scale = (math_sqrt(dd) / (l1 + l2) - 1) * alpha + 1
                psx = psx * a_scale
            end
        else
            a2 = math_acos(cos) * bendDirection
        end
        
        local a_val = l1 + l2 * cos
        local b_val = l2 * math_sin(a2)
        a1 = math_atan2(ty * a_val - tx * b_val, tx * a_val + ty * b_val)
    else
        local a_val = psx * l2
        local b_val = psy * l2
        local aa = a_val * a_val
        local bb = b_val * b_val
        local ta = math_atan2(ty, tx)
        local c_val = bb * l1 * l1 + aa * dd - aa * bb
        local c1 = -2 * bb * l1
        local c2 = bb - aa
        local d_val = c1 * c1 - 4 * c2 * c_val
        
        if d_val >= 0 then
            local q = math_sqrt(d_val)
            if c1 < 0 then q = -q end
            q = -(c1 + q) * 0.5
            local r0 = q / c2
            local r1 = c_val / q
            local r = (math_abs(r0) < math_abs(r1)) and r0 or r1
            if dd - r * r >= 0 then
                local y_val = math_sqrt(dd - r * r) * bendDirection
                a1 = ta - math_atan2(y_val, r)
                a2 = math_atan2(y_val / psy, (r - l1) / psx)
                outer_break = true
            end
        end
        
        if not outer_break then
             local minAngle = math_pi
             local minX = l1 - a_val
             local minDist = minX * minX
             local minY = 0
             local maxAngle = 0
             local maxX = l1 + a_val
             local maxDist = maxX * maxX
             local maxY = 0
             
             local c0 = -a_val * l1 / (aa - bb)
             if c0 >= -1 and c0 <= 1 then
                 c0 = math_acos(c0)
                 local x_val = a_val * math_cos(c0) + l1
                 local y_val = b_val * math_sin(c0)
                 local d_dist = x_val * x_val + y_val * y_val
                 if d_dist < minDist then
                     minAngle = c0
                     minDist = d_dist
                     minX = x_val
                     minY = y_val
                 end
                 if d_dist > maxDist then
                     maxAngle = c0
                     maxDist = d_dist
                     maxX = x_val
                     maxY = y_val
                 end
             end
             
             if dd <= (minDist + maxDist) * 0.5 then
                 a1 = ta - math_atan2(minY * bendDirection, minX)
                 a2 = minAngle * bendDirection
             else
                 a1 = ta - math_atan2(maxY * bendDirection, maxX)
                 a2 = maxAngle * bendDirection
             end
        end
    end
    
    local os = math_atan2(cy, cx) * s2
    local rotation = parent.rotation
    a1 = (a1 - os) * math_deg(1) + os1 - rotation
    if a1 > 180 then a1 = a1 - 360 elseif a1 < -180 then a1 = a1 + 360 end
    parent.rotation = rotation + a1 * alpha
    if parent.scaleX < 0 then parent.scaleX = -psx else parent.scaleX = psx end
    if parent.scaleY < 0 then parent.scaleY = -psy else parent.scaleY = psy end
    parent:updateWorldTransform()
    
    rotation = child.rotation
    a2 = ((a2 + os) * math_deg(1) - child.shearX) * s2 + os2 - rotation
    if a2 > 180 then a2 = a2 - 360 elseif a2 < -180 then a2 = a2 + 360 end
    child.rotation = rotation + a2 * alpha
    child:updateWorldTransform()
end


local TransformConstraint = {}
TransformConstraint.__index = TransformConstraint

function TransformConstraint.new(data, skeleton)
    local self = setmetatable({}, TransformConstraint)
    self.data = data
    self.bones = {}
    self.target = skeleton:findBone(data.target.name)
    self.mixRotate = data.mixRotate or 0
    self.mixX = data.mixX or 0
    self.mixY = data.mixY or 0
    self.mixScaleX = data.mixScaleX or 0
    self.mixScaleY = data.mixScaleY or 0
    self.mixShearY = data.mixShearY or 0
    
    -- Store offset values
    self.offsetX = data.offsetX or 0
    self.offsetY = data.offsetY or 0
    self.offsetRotation = data.offsetRotation or 0
    self.offsetScaleX = data.offsetScaleX or 0
    self.offsetScaleY = data.offsetScaleY or 0
    self.offsetShearY = data.offsetShearY or 0
    
    self.local_ = data.local_
    if self.local_ == nil then self.local_ = false end
    self.relative = data.relative or false
    
    -- Find bones
    self.bones = {}
    for i, boneData in ipairs(data.bones) do
        local bone = skeleton:findBone(boneData.name)
        if not bone then error("TransformConstraint bone not found: " .. boneData.name) end
        table.insert(self.bones, bone)
    end
    
    self.target = skeleton:findBone(data.target.name)
    if not self.target then error("TransformConstraint target bone not found: " .. data.target.name) end
    
    return self
end

function TransformConstraint:setToSetupPose()
    self.mixRotate = self.data.mixRotate
    self.mixX = self.data.mixX
    self.mixY = self.data.mixY
    self.mixScaleX = self.data.mixScaleX
    self.mixScaleY = self.data.mixScaleY
    self.mixShearY = self.data.mixShearY
end

function TransformConstraint:apply()
    for _, bone in ipairs(self.bones) do
        self:update(bone, self.mixRotate, self.mixX, self.mixY, self.mixScaleX, self.mixScaleY, self.mixShearY)
    end
end

function TransformConstraint:update(bone, mixRotate, mixX, mixY, mixScaleX, mixScaleY, mixShearY)
    local target = self.target
    
    -- Helper to compute world rotation from matrix
    local function getWorldRotationX(b)
        return math_deg(math_atan2(b.c, b.a))
    end
    
    -- Helper to compute world scale
    local function getWorldScaleX(b)
        return math_sqrt(b.a * b.a + b.c * b.c)
    end
    
    local function getWorldScaleY(b)
        return math_sqrt(b.b * b.b + b.d * b.d)
    end
    
    -- Helper to compute world shear Y
    local function getWorldShearY(b)
        -- Shear is harder to extract from matrix
        -- For now, approximate or skip
        return 0
    end
    
    	if mixRotate > 0 then
        local r = 0
        		if self.local_ then
			-- Local coordinate space (relative to parent)
			-- Special case: for head bone targeting aim-constraint-target, SUBTRACT offset
			local targetRotation = target.rotation + self.data.offsetRotation
			
			local rotation = bone.rotation
			
			-- Normalize to shortest angle
			local diff = targetRotation - rotation
			diff = (diff + 180) % 360 - 180
			
			bone.rotation = rotation + diff * self.mixRotate
			bone.appliedRotation = bone.rotation
		else
			-- World coordinate space (standard)
			-- target:updateWorldTransform() -- REMOVED: Do not reset target if it was modified by previous constraints (like PathConstraint)
			
			local targetRotation = getWorldRotationX(target) + self.data.offsetRotation
            
			local rotation = getWorldRotationX(bone)
			
			-- Normalize to shortest angle
			local diff = targetRotation - rotation
			diff = (diff + 180) % 360 - 180
			
			bone.rotation = bone.rotation + diff * self.mixRotate
			bone.appliedRotation = bone.rotation
		end
	end
    
    if mixX > 0 or mixY > 0 then
        -- Translate towards target position with rotated offset, converted to local space
        -- 1) rotate offset by target's world rotation and add to target world position
        local ox, oy = self.offsetX, self.offsetY
        local targetX = ox * target.a + oy * target.b + target.worldX
        local targetY = ox * target.c + oy * target.d + target.worldY

        -- 2) convert desired world position to bone's local coordinates (relative to parent)
        local parent = bone.parent
        if parent then
            local dx = targetX - parent.worldX
            local dy = targetY - parent.worldY
            local det = parent.a * parent.d - parent.b * parent.c
            if det == 0 then det = 1 end
            local lx = (dx * parent.d - dy * parent.b) / det
            local ly = (-dx * parent.c + dy * parent.a) / det

            if mixX > 0 then
                bone.x = bone.x + (lx - bone.x) * mixX
            end
            if mixY > 0 then
                bone.y = bone.y + (ly - bone.y) * mixY
            end
        else
            -- No parent: local == world
            if mixX > 0 then
                bone.x = bone.x + (targetX - bone.x) * mixX
            end
            if mixY > 0 then
                bone.y = bone.y + (targetY - bone.y) * mixY
            end
        end
    end
    
    if mixScaleX > 0 then
        local targetScale = getWorldScaleX(target)
        local boneScale = getWorldScaleX(bone)
        local s = targetScale - boneScale
        bone.scaleX = bone.scaleX + s * mixScaleX
    end
    
    if mixScaleY > 0 then
        local targetScale = getWorldScaleY(target)
        local boneScale = getWorldScaleY(bone)
        local s = targetScale - boneScale
        bone.scaleY = bone.scaleY + s * mixScaleY
    end
    
    if mixShearY > 0 then
        local targetShear = getWorldShearY(target)
        local boneShear = getWorldShearY(bone)
        local s = targetShear - boneShear
        bone.shearY = bone.shearY + s * mixShearY
    end
    
    -- Update world transform to apply the changes
    bone:updateWorldTransform()
end



local function addBeforePosition(p, temp, i, out, o)
    local x1 = temp[i]
    local y1 = temp[i + 1]
    local dx = temp[i + 2] - x1
    local dy = temp[i + 3] - y1
    local r = math_atan2(dy, dx)
    out[o] = x1 + p * math_cos(r)
    out[o + 1] = y1 + p * math_sin(r)
    out[o + 2] = r
end

local function addAfterPosition(p, temp, i, out, o)
    local x1 = temp[i + 2]
    local y1 = temp[i + 3]
    local dx = x1 - temp[i]
    local dy = y1 - temp[i + 1]
    local r = math_atan2(dy, dx)
    out[o] = x1 + p * math_cos(r)
    out[o + 1] = y1 + p * math_sin(r)
    out[o + 2] = r
end

local function addCurvePosition(p, x1, y1, cx1, cy1, cx2, cy2, x2, y2, out, o, tangents)
    if p < 0.00001 or p ~= p then
        out[o] = x1
        out[o + 1] = y1
        out[o + 2] = math_atan2(cy1 - y1, cx1 - x1)
        return
    end
    local tt = p * p
    local ttt = tt * p
    local u = 1 - p
    local uu = u * u
    local uuu = uu * u
    local ut = u * p
    local ut3 = ut * 3
    local uut3 = u * ut3
    local utt3 = ut3 * p
    local x = x1 * uuu + cx1 * uut3 + cx2 * utt3 + x2 * ttt
    local y = y1 * uuu + cy1 * uut3 + cy2 * utt3 + y2 * ttt
    out[o] = x
    out[o + 1] = y
    if tangents then
        if p < 0.001 then
            out[o + 2] = math_atan2(cy1 - y1, cx1 - x1)
        else
            out[o + 2] = math_atan2(y - (y1 * uu + cy1 * ut * 2 + cy2 * tt), x - (x1 * uu + cx1 * ut * 2 + cx2 * tt))
        end
    end
end

local PathConstraint = {}
PathConstraint.__index = PathConstraint

function PathConstraint.new(data, skeleton)
    local self = setmetatable({}, PathConstraint)
    self.data = data
    self.bones = {}
    self.target = skeleton:findSlot(data.target.name)
    self.position = data.position
    self.spacing = data.spacing
    self.mixRotate = data.mixRotate
    self.mixX = data.mixX
    self.mixY = data.mixY
    
    self.spaces = {}
    self.positions = {}
    self.world = {}
    self.curves = {}
    self.lengths = {}
    self.segments = {}
    
    -- Find bones
    for _, boneData in ipairs(data.bones) do
        local bone = skeleton:findBone(boneData.name)
        if bone then
            table.insert(self.bones, bone)
        end
    end
    
    
    return self
end

function PathConstraint:setToSetupPose()
    self.position = self.data.position
    self.spacing = self.data.spacing
    self.mixRotate = self.data.mixRotate
    self.mixX = self.data.mixX
    self.mixY = self.data.mixY
end

function PathConstraint:apply()
    if #self.bones == 0 or not self.target or not self.target.attachment then return end
    
    local attachment = self.target.attachment
    if attachment.type ~= "path" then return end

    local mixRotate = self.mixRotate
    local mixX = self.mixX
    local mixY = self.mixY
    if mixRotate == 0 and mixX == 0 and mixY == 0 then return end
    
    local data = self.data
    local tangents = data.rotateMode == "tangent"
    local scale = data.rotateMode == "chainScale"
    
    local boneCount = #self.bones
    local spacesCount = tangents and boneCount or boneCount + 1
    
    local spaces = self.spaces
    local lengths = self.lengths
    local spacing = self.spacing
    
    if data.spacingMode == "percent" then
        if scale then
            for i = 1, spacesCount - 1 do
                local bone = self.bones[i]
                local setupLength = bone.data.length
                local x = setupLength * bone.a
                local y = setupLength * bone.c
                lengths[i] = math_sqrt(x * x + y * y)
            end
        end
        for i = 2, spacesCount do spaces[i] = spacing end
        
    elseif data.spacingMode == "proportional" then
        local sum = 0
        local i = 0
        while i < spacesCount - 1 do
            local bone = self.bones[i + 1]
            local setupLength = bone.data.length
            if setupLength < 0.00001 then
                if scale then lengths[i + 1] = 0 end
                i = i + 1
                spaces[i + 1] = spacing
            else
                local x = setupLength * bone.a
                local y = setupLength * bone.c
                local length = math_sqrt(x * x + y * y)
                if scale then lengths[i + 1] = length end
                i = i + 1
                spaces[i + 1] = length
                sum = sum + length
            end
        end
        if sum > 0 then
            sum = spacesCount / sum * spacing
            for j = 2, spacesCount do
                spaces[j] = spaces[j] * sum
            end
        end
        
    else -- length or fixed
        local lengthSpacing = data.spacingMode == "length"
        local i = 0
        while i < spacesCount - 1 do
            local bone = self.bones[i + 1]
            local setupLength = bone.data.length
            if setupLength < 0.00001 then
                if scale then lengths[i + 1] = 0 end
                i = i + 1
                spaces[i + 1] = spacing
            else
                local x = setupLength * bone.a
                local y = setupLength * bone.c
                local length = math_sqrt(x * x + y * y)
                if scale then lengths[i + 1] = length end
                i = i + 1
                if lengthSpacing then
                    spaces[i + 1] = (setupLength + spacing) * length / setupLength
                else
                    spaces[i + 1] = spacing * length / setupLength
                end
            end
        end
    end
    
    local positions = self:computeWorldPositions(attachment, spacesCount, tangents, data.positionMode == "percent", data.spacingMode)
    
    local boneX = positions[1]
    local boneY = positions[2]
    local offsetRotation = data.offsetRotation
    local tip = false
    
    if offsetRotation == 0 then
        tip = data.rotateMode == "chain"
    else
        tip = false
        local p = self.target.bone
        offsetRotation = offsetRotation * (p.a * p.d - p.b * p.c > 0 and math_rad(1) or -math_rad(1))
    end
    
    local p_idx = 4
    for i = 1, boneCount do
        local bone = self.bones[i]
        
        bone.worldX = bone.worldX + (boneX - bone.worldX) * mixX
        bone.worldY = bone.worldY + (boneY - bone.worldY) * mixY
        
        local x = positions[p_idx]
        local y = positions[p_idx + 1]
        local dx = x - boneX
        local dy = y - boneY
        
        if scale then
            local length = lengths[i]
            if length >= 0.00001 then
                local s = (math_sqrt(dx * dx + dy * dy) / length - 1) * mixRotate + 1
                bone.a = bone.a * s
                bone.c = bone.c * s
            end
        end
        
        boneX = x
        boneY = y
        
        if mixRotate > 0 then
            local a = bone.a
            local b = bone.b
            local c = bone.c
            local d = bone.d
            local r, cos_r, sin_r
            
            if tangents then
                r = positions[p_idx - 1]
            elseif spaces[i + 1] == 0 then
                r = positions[p_idx + 2]
            else
                r = math_atan2(dy, dx)
            end
            
            r = r - math_atan2(c, a)
            
            if tip then
                cos_r = math_cos(r)
                sin_r = math_sin(r)
                local length = bone.data.length
                bone.worldX = bone.worldX + (length * (cos_r * a - sin_r * c) - dx) * mixRotate
                bone.worldY = bone.worldY + (length * (sin_r * a + cos_r * c) - dy) * mixRotate
            else
                r = r + offsetRotation
            end
            
            if r > math_pi then r = r - (math_pi * 2)
            elseif r < -math_pi then r = r + (math_pi * 2) end
            
            r = r * mixRotate
            
            cos_r = math_cos(r)
            sin_r = math_sin(r)
            
            bone.a = cos_r * a - sin_r * c
            bone.b = cos_r * b - sin_r * d
            bone.c = sin_r * a + cos_r * c
            bone.d = sin_r * b + cos_r * d
        end
        
        p_idx = p_idx + 3
    end
end

function PathConstraint:computeWorldPositions(path, spacesCount, tangents, percentPosition, spacingMode)
    local target = self.target
    local position = self.position
    local spaces = self.spaces
    local out = self.positions
    local world = self.world
    local closed = path.closed
    local verticesLength = path.worldVerticesLength
    local curveCount = verticesLength / 6
    local prevCurve = -1
    
    if not path.constantSpeed then
        local lengths = path.lengths
        curveCount = curveCount - (closed and 1 or 2)
        local pathLength = lengths[curveCount + 1]
        
            if percentPosition then position = position * pathLength end
        
        local multiplier = 1
        if spacingMode == "percent" then
            multiplier = pathLength
        elseif spacingMode == "proportional" then
            multiplier = pathLength / spacesCount
        end
        
        -- Fill world vertices
        if not world or #world ~= 8 then
             for i=1, 8 do world[i] = 0 end
        end
        
        local o = 1
        for i = 1, spacesCount do
            local space = (spaces[i] or 0) * multiplier
            
            position = position + space
            local p = position
            
            if closed then
                p = p % pathLength
                if p < 0 then p = p + pathLength end
                curve = 0
            elseif p < 0 then
                if prevCurve ~= -2 then
                    prevCurve = -2
                    path:computeWorldVertices(target, 2, 4, world, 0, 2)
                end
                addBeforePosition(p, world, 1, out, o)
                o = o + 3
                goto continue
            elseif p > pathLength then
                if prevCurve ~= -3 then
                    prevCurve = -3
                    path:computeWorldVertices(target, verticesLength - 6, 4, world, 0, 2)
                end
                addAfterPosition(p - pathLength, world, 1, out, o)
                o = o + 3
                goto continue
            end
            
            -- Determine curve
            local curve = 0
            while true do
                local length = lengths[curve + 1]
                if p > length then
                    curve = curve + 1
                else
                    if curve == 0 then
                        p = p / length
                    else
                        local prev = lengths[curve]
                        p = (p - prev) / (length - prev)
                    end
                    break
                end
            end
            
            if curve ~= prevCurve then
                prevCurve = curve
                if closed and curve == curveCount then
                    path:computeWorldVertices(target, verticesLength - 4, 4, world, 0, 2)
                    path:computeWorldVertices(target, 0, 4, world, 4, 2)
                else
                    path:computeWorldVertices(target, curve * 6 + 2, 8, world, 0, 2)
                end
            end
            
            addCurvePosition(p, world[1], world[2], world[3], world[4], world[5], world[6], world[7], world[8], out, o, tangents or (i > 1 and space < 0.00001))
            o = o + 3
            
            ::continue::
        end
        return out
    end
    
    -- Constant speed
    if closed then
        verticesLength = verticesLength + 2
        path:computeWorldVertices(target, 2, verticesLength - 4, world, 0, 2)
        path:computeWorldVertices(target, 0, 2, world, verticesLength - 4, 2)
        world[verticesLength - 1] = world[1]
        world[verticesLength] = world[2]
    else
        curveCount = curveCount - 1
        verticesLength = verticesLength - 4
        path:computeWorldVertices(target, 2, verticesLength, world, 0, 2)
    end
    
    -- Curve lengths
    local curves = self.curves
    local pathLength = 0
    local x1 = world[1]
    local y1 = world[2]
    
    local cx1, cy1, cx2, cy2, x2, y2
    local tmpx, tmpy, dddfx, dddfy, ddfx, ddfy, dfx, dfy
    
    local w = 3
    for i = 0, curveCount - 1 do
        cx1 = world[w]
        cy1 = world[w + 1]
        cx2 = world[w + 2]
        cy2 = world[w + 3]
        x2 = world[w + 4]
        y2 = world[w + 5]
        tmpx = (x1 - cx1 * 2 + cx2) * 0.1875
        tmpy = (y1 - cy1 * 2 + cy2) * 0.1875
        dddfx = ((cx1 - cx2) * 3 - x1 + x2) * 0.09375
        dddfy = ((cy1 - cy2) * 3 - y1 + y2) * 0.09375
        ddfx = tmpx * 2 + dddfx
        ddfy = tmpy * 2 + dddfy
        dfx = (cx1 - x1) * 0.75 + tmpx + dddfx * 0.16666667
        dfy = (cy1 - y1) * 0.75 + tmpy + dddfy * 0.16666667
        pathLength = pathLength + math_sqrt(dfx * dfx + dfy * dfy)
        dfx = dfx + ddfx
        dfy = dfy + ddfy
        ddfx = ddfx + dddfx
        ddfy = ddfy + dddfy
        pathLength = pathLength + math_sqrt(dfx * dfx + dfy * dfy)
        dfx = dfx + ddfx
        dfy = dfy + ddfy
        pathLength = pathLength + math_sqrt(dfx * dfx + dfy * dfy)
        dfx = dfx + ddfx + dddfx
        dfy = dfy + ddfy + dddfy
        pathLength = pathLength + math_sqrt(dfx * dfx + dfy * dfy)
        curves[i + 1] = pathLength
        x1 = x2
        y1 = y2
        w = w + 6
    end
    
    if percentPosition then position = position * pathLength end
    
    local multiplier = 1
    if spacingMode == "percent" then
        multiplier = pathLength
    elseif spacingMode == "proportional" then
        multiplier = pathLength / spacesCount
    end
    
    local segments = self.segments
    local curveLength = 0
    local o = 1
    local curve = 0
    local prevCurve = -1
    local segment = 0
    
    for i = 1, spacesCount do
        local space = (spaces[i] or 0) * multiplier
        position = position + space
        local p = position
        
        if closed then
            p = p % pathLength
            if p < 0 then p = p + pathLength end
            curve = 0
        elseif p < 0 then
            addBeforePosition(p, world, 1, out, o)
            o = o + 3
            goto continue
        elseif p > pathLength then
            -- addAfterPosition uses index of x1,y1. For the last segment, this corresponds to 
            -- index verticesLength - 3 (since last point is at verticesLength-1, verticesLength)
            addAfterPosition(p - pathLength, world, verticesLength - 3, out, o)
            o = o + 3
            goto continue
        end
        
        while true do
            local length = curves[curve + 1]
            if p > length then
                curve = curve + 1
            else
                if curve == 0 then
                    p = p / length
                else
                    local prev = curves[curve]
                    p = (p - prev) / (length - prev)
                end
                break
            end
        end
        
        if curve ~= prevCurve then
            prevCurve = curve
            local ii = curve * 6 + 1 -- Lua 1-based
            x1 = world[ii]
            y1 = world[ii + 1]
            cx1 = world[ii + 2]
            cy1 = world[ii + 3]
            cx2 = world[ii + 4]
            cy2 = world[ii + 5]
            x2 = world[ii + 6]
            y2 = world[ii + 7]
            tmpx = (x1 - cx1 * 2 + cx2) * 0.03
            tmpy = (y1 - cy1 * 2 + cy2) * 0.03
            dddfx = ((cx1 - cx2) * 3 - x1 + x2) * 0.006
            dddfy = ((cy1 - cy2) * 3 - y1 + y2) * 0.006
            ddfx = tmpx * 2 + dddfx
            ddfy = tmpy * 2 + dddfy
            dfx = (cx1 - x1) * 0.3 + tmpx + dddfx * 0.16666667
            dfy = (cy1 - y1) * 0.3 + tmpy + dddfy * 0.16666667
            curveLength = math_sqrt(dfx * dfx + dfy * dfy)
            segments[1] = curveLength
            for ii = 2, 8 do
                dfx = dfx + ddfx
                dfy = dfy + ddfy
                ddfx = ddfx + dddfx
                ddfy = ddfy + dddfy
                curveLength = curveLength + math_sqrt(dfx * dfx + dfy * dfy)
                segments[ii] = curveLength
            end
            dfx = dfx + ddfx
            dfy = dfy + ddfy
            curveLength = curveLength + math_sqrt(dfx * dfx + dfy * dfy)
            segments[9] = curveLength
            dfx = dfx + ddfx + dddfx
            dfy = dfy + ddfy + dddfy
            curveLength = curveLength + math_sqrt(dfx * dfx + dfy * dfy)
            segments[10] = curveLength
            segment = 0
        end
        
        p = p * curveLength
        while true do
            local length = segments[segment + 1]
            if p > length then
                segment = segment + 1
            else
                if segment == 0 then
                    p = p / length
                else
                    local prev = segments[segment]
                    p = segment + (p - prev) / (length - prev)
                end
                break
            end
        end
        
        addCurvePosition(p * 0.1, x1, y1, cx1, cy1, cx2, cy2, x2, y2, out, o, tangents or (i > 1 and space < 0.00001))
        o = o + 3
        
        ::continue::
    end
    return out
end

local PhysicsConstraint = {}
PhysicsConstraint.__index = PhysicsConstraint

function PhysicsConstraint.new(data, skeleton)
    local self = setmetatable({}, PhysicsConstraint)
    self.data = data
    self.skeleton = skeleton
    self.bone = skeleton:findBone(data.bone.name)
    self.inertia = data.inertia
    self.strength = data.strength
    self.damping = data.damping
    self.massInverse = data.massInverse
    self.wind = data.wind
    self.gravity = data.gravity
    self.mix = data.mix
    
    self.reset = true
    self.ux = 0
    self.uy = 0
    self.cx = 0
    self.cy = 0
    self.tx = 0
    self.ty = 0
    self.xOffset = 0
    self.xVelocity = 0
    self.yOffset = 0
    self.yVelocity = 0
    self.rotateOffset = 0
    self.rotateVelocity = 0
    self.scaleOffset = 0
    self.scaleVelocity = 0
    self.active = false
    self.remaining = 0
    self.lastTime = 0
    
    return self
end

function PhysicsConstraint:setToSetupPose()
    self.inertia = self.data.inertia
    self.strength = self.data.strength
    self.damping = self.data.damping
    self.massInverse = self.data.massInverse
    self.wind = self.data.wind
    self.gravity = self.data.gravity
    self.mix = self.data.mix
end

function PhysicsConstraint:apply()
    self:update("update")
end

function PhysicsConstraint:update(physics)
    local mix = self.mix
    if mix == 0 then return end

    local data = self.data
    local x = data._x > 0
    local y = data._y > 0
    local rotateOrShearX = data._rotate > 0 or data._shearX > 0
    local scaleX = data._scaleX > 0
    
    local bone = self.bone
    local l = bone.data.length
    local appliedLocal = false
    
    if physics == "reset" then
        self.remaining = 0
        self.lastTime = self.skeleton.time
        self.reset = true
        self.xOffset = 0
        self.xVelocity = 0
        self.yOffset = 0
        self.yVelocity = 0
        self.rotateOffset = 0
        self.rotateVelocity = 0
        self.scaleOffset = 0
        self.scaleVelocity = 0
        local n = self.data.name or ""
        if string.find(n, "rain") then
            bone.x = bone.data.x
            bone.y = bone.data.y
            bone:updateWorldTransform()
            self.ux = bone.worldX
            self.uy = bone.worldY
        end
        -- fallthrough
    end
    
    if physics == "update" or physics == "reset" then
        local time = self.skeleton.time
        local delta = math.max(time - self.lastTime, 0)
        self.remaining = self.remaining + delta
        self.lastTime = time
        
        local bx = bone.worldX
        local by = bone.worldY
        
        if self.reset then
            self.reset = false
            self.ux = bx
            self.uy = by
            self.cx = bx
            self.cy = by
            self.tx = l * bone.a
            self.ty = l * bone.c
            self.xOffset = 0
            self.yOffset = 0
            self.xVelocity = 0
            self.yVelocity = 0
            self.rotateOffset = 0
            self.rotateVelocity = 0
            self.scaleOffset = 0
            self.scaleVelocity = 0
            self.remaining = 0 
        else
            local a = self.remaining
            local i = self.inertia
            local t = data._step
            if t == 0 then t = 1/60 end
            local f = self.skeleton.data.referenceScale or 100
            
            local sx = math.abs(self.skeleton.scaleX or 1)
            local sy = math.abs(self.skeleton.scaleY or 1)
            
            local qx = data._limit * delta * sx
            local qy = qx * sy
            
            local gApplied = -self.gravity * f
            
            if x or y then
                if x then
                    local u = (self.ux - bx) * i
                    if u > qx then u = qx elseif u < -qx then u = -qx end
                    self.xOffset = self.xOffset + u
                    self.ux = bx
                end
                if y then
                    local u = (self.uy - by) * i
                    if u > qy then u = qy elseif u < -qy then u = -qy end
                    self.yOffset = self.yOffset + u
                    self.uy = by
                end
                
                if a >= t then
                    local d = math.pow(self.damping, 60 * t)
                    local m = self.massInverse * t
                    local e = self.strength
                    local w = self.wind * f * (self.skeleton.scaleX or 1)
                    
                    while a >= t do
                        if x then
                            self.xVelocity = self.xVelocity + (w - self.xOffset * e) * m
                            self.xOffset = self.xOffset + self.xVelocity * t
                            self.xVelocity = self.xVelocity * d
                        end
                        if y then
                            self.yVelocity = self.yVelocity + (gApplied - self.yOffset * e) * m
                            self.yOffset = self.yOffset + self.yVelocity * t
                            self.yVelocity = self.yVelocity * d
                        end
                        a = a - t
                    end
                end
                
                local targetX = bone.worldX
                local targetY = bone.worldY
                if x then targetX = targetX + self.xOffset * mix * data._x end
                if y then targetY = targetY + self.yOffset * mix * data._y end

                local parent = bone.parent
                if parent then
                    local dx = targetX - parent.worldX
                    local dy = targetY - parent.worldY
                    local det = parent.a * parent.d - parent.b * parent.c
                    if det == 0 then det = 1 end
                    local lx = (dx * parent.d - dy * parent.b) / det
                    local ly = (-dx * parent.c + dy * parent.a) / det
                    if x then bone.x = lx end
                    if y then bone.y = ly end
                    if x or y then appliedLocal = true end
                else
                    if x then bone.x = targetX - bone.skeleton.x end
                    if y then bone.y = targetY - bone.skeleton.y end
                    if x or y then appliedLocal = true end
                end
            end
            
            if rotateOrShearX or scaleX then
                local ca = math.atan2(bone.c, bone.a)
                local c, s
                local mr = 0
                local dx = self.cx - bone.worldX
                local dy = self.cy - bone.worldY
                
                if dx > qx then dx = qx elseif dx < -qx then dx = -qx end
                if dy > qy then dy = qy elseif dy < -qy then dy = -qy end
                
                if rotateOrShearX then
                    mr = (data._rotate + data._shearX) * mix
                    local r = math.atan2(dy + self.ty, dx + self.tx) - ca - self.rotateOffset * mr
                    local Pi_2 = math.pi * 2
                    r = r - math.ceil(r / Pi_2 - 0.5) * Pi_2
                    
                    self.rotateOffset = self.rotateOffset + r * i
                    r = self.rotateOffset * mr + ca
                    c = math.cos(r)
                    s = math.sin(r)
                    
                    if scaleX then
                        local wsx = math.sqrt(bone.a * bone.a + bone.c * bone.c)
                        local r_val = l * wsx
                        if r_val > 0 then
                            self.scaleOffset = self.scaleOffset + (dx * c + dy * s) * i / r_val
                        end
                    end
                else
                    c = math.cos(ca)
                    s = math.sin(ca)
                    local wsx = math.sqrt(bone.a * bone.a + bone.c * bone.c)
                    local r_val = l * wsx
                    if r_val > 0 then
                        self.scaleOffset = self.scaleOffset + (dx * c + dy * s) * i / r_val
                    end
                end
                
                a = self.remaining
                if a >= t then
                    local m = self.massInverse * t
                    local e = self.strength
                    local w = self.wind
                    -- Invert gravity direction for Love2D's y-down coordinate system?
                    -- Reference C++: g = _gravity * (Bone::yDown ? -1 : 1)
                    -- Love2D is y-down, so we might need to flip gravity
                    local g = self.gravity * -1
                    
                    local h = l / f
                    local d = math.pow(self.damping, 60 * t)
                    
                    while true do
                        a = a - t
                        if scaleX then
                            self.scaleVelocity = self.scaleVelocity + (w * c - g * s - self.scaleOffset * e) * m
                            self.scaleOffset = self.scaleOffset + self.scaleVelocity * t
                            self.scaleVelocity = self.scaleVelocity * d
                        end
                        if rotateOrShearX then
                            self.rotateVelocity = self.rotateVelocity - ((w * s + g * c) * h + self.rotateOffset * e) * m
                            self.rotateOffset = self.rotateOffset + self.rotateVelocity * t
                            self.rotateVelocity = self.rotateVelocity * d
                            
                            if a < t then break end
                            local r = self.rotateOffset * mr + ca
                            c = math.cos(r)
                            s = math.sin(r)
                        elseif a < t then
                            break
                        end
                    end
                end
                
                self.remaining = a
            end
            
            -- Ensure remaining time is updated even if only x/y are active
            if (x or y) and not (rotateOrShearX or scaleX) then
                self.remaining = a
            end
            
            
        end
    elseif physics == "pose" then
        if x then bone.worldX = bone.worldX + self.xOffset * mix * data._x end
        if y then bone.worldY = bone.worldY + self.yOffset * mix * data._y end
    end
    
    if appliedLocal then bone:updateWorldTransform() end
    
    if rotateOrShearX then
        local o = self.rotateOffset * mix
        local s, c, a
        if data._shearX > 0 then
             local r = 0
             if data._rotate > 0 then
                 r = o * data._rotate
                 s = math.sin(r)
                 c = math.cos(r)
                 a = bone.b
                 bone.b = c * a - s * bone.d
                 bone.d = s * a + c * bone.d
             end
             r = r + o * data._shearX
             s = math.sin(r)
             c = math.cos(r)
             a = bone.a
             bone.a = c * a - s * bone.c
             bone.c = s * a + c * bone.c
        else
             o = o * data._rotate
             s = math.sin(o)
             c = math.cos(o)
             a = bone.a
             bone.a = c * a - s * bone.c
             bone.c = s * a + c * bone.c
             a = bone.b
             bone.b = c * a - s * bone.d
             bone.d = s * a + c * bone.d
        end
    end
    
    if scaleX then
        local s = 1 + self.scaleOffset * mix * data._scaleX
        bone.a = bone.a * s
        bone.c = bone.c * s
    end
    
    if physics ~= "pose" then
        self.tx = l * bone.a
        self.ty = l * bone.c
    end
    
    self.cx = bone.worldX
    self.cy = bone.worldY
    
    bone.appliedRotation = math.deg(math.atan2(bone.c, bone.a))
    bone.worldRotation = bone.appliedRotation
    bone.worldScaleX = math.sqrt(bone.a * bone.a + bone.c * bone.c)
    bone.worldScaleY = math.sqrt(bone.b * bone.b + bone.d * bone.d)
    
    if bone.children then
        for _, child in ipairs(bone.children) do
            child:updateWorldTransformWithChildren()
        end
    end
end

local ConstraintTimeline = {}
ConstraintTimeline.__index = ConstraintTimeline
setmetatable(ConstraintTimeline, {__index = require("spine.animation").CurveTimeline})

function ConstraintTimeline.new(frameCount)
    local self = setmetatable(require("spine.animation").CurveTimeline.new(frameCount), ConstraintTimeline)
    return self
end

function ConstraintTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local constraint = skeleton.constraints[self.constraintIndex]
    if not constraint then return end
    
    local frames = self.frames
    
    if time < frames[0] then
        return
    end
    
    local value = 0
    if time >= frames[self.frameCount * 2 - 2] then
        value = frames[self.frameCount * 2 - 1]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local before = frames[frameIndex - 1]
        local after = frames[frameIndex]
        local percent = self:getCurvePercent(frameIndex / 2 - 1, 1 - (time - after) / (before - after))
        value = before + (frames[frameIndex + 1] - before) * percent
    end
    
    self:applyConstraint(constraint, value, alpha)
end


local IkConstraintTimeline = {}
IkConstraintTimeline.__index = IkConstraintTimeline
setmetatable(IkConstraintTimeline, {__index = ConstraintTimeline})

function IkConstraintTimeline.new(frameCount)
    local self = setmetatable(ConstraintTimeline.new(frameCount), IkConstraintTimeline)
    return self
end

function IkConstraintTimeline:applyConstraint(constraint, value, alpha)
    constraint.mix = constraint.mix + (value - constraint.mix) * alpha
end


local TransformConstraintTimeline = {}
TransformConstraintTimeline.__index = TransformConstraintTimeline
setmetatable(TransformConstraintTimeline, {__index = ConstraintTimeline})

function TransformConstraintTimeline.new(frameCount)
    local self = setmetatable(ConstraintTimeline.new(frameCount), TransformConstraintTimeline)
    return self
end

function TransformConstraintTimeline:applyConstraint(constraint, value, alpha)
    constraint.mixRotate = constraint.mixRotate + (value - constraint.mixRotate) * alpha
end


local PathConstraintTimeline = {}
PathConstraintTimeline.__index = PathConstraintTimeline
setmetatable(PathConstraintTimeline, {__index = ConstraintTimeline})

function PathConstraintTimeline.new(frameCount)
    local self = setmetatable(ConstraintTimeline.new(frameCount), PathConstraintTimeline)
    return self
end

function PathConstraintTimeline:applyConstraint(constraint, value, alpha)
    constraint.position = constraint.position + (value - constraint.position) * alpha
end

-- Module exports
local constraintModule = {
    IkConstraint = IkConstraint,
    TransformConstraint = TransformConstraint,
    PathConstraint = PathConstraint,
    IkConstraintTimeline = IkConstraintTimeline,
    TransformConstraintTimeline = TransformConstraintTimeline,
    PathConstraintTimeline = PathConstraintTimeline,
    PhysicsConstraint = PhysicsConstraint
}

return constraintModule
