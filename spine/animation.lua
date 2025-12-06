-- Spine Love2D Runtime - Animation System
-- Handles animation playback, mixing, and timeline application

local mathModule = require("spine.math")

local Animation = {}
Animation.__index = Animation

function Animation.new(name, timelines, duration)
    local self = {
        name = name,
        timelines = timelines,
        duration = duration
    }
    setmetatable(self, Animation)
    return self
end

function Animation:apply(skeleton, lastTime, time, loop, events, alpha, blend, direction)
    if not self.timelines then return end

    if loop and self.duration > 0 then
        time = time % self.duration
        lastTime = lastTime % self.duration
    end

    for _, timeline in ipairs(self.timelines) do
        timeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    end
end


local Timeline = {}
Timeline.__index = Timeline

function Timeline.new(frameCount)
    local self = setmetatable({}, Timeline)
    self.frames = {}
    self.frameCount = frameCount
    return self
end

function Timeline:getFrameCount()
    return self.frameCount
end

function Timeline:getDuration()
    return self.frames[self.frameCount * self:getFrameEntries()]
end

function Timeline:getFrameEntries()
    return 1
end


local CurveTimeline = {}
CurveTimeline.__index = CurveTimeline
setmetatable(CurveTimeline, {__index = Timeline})

function CurveTimeline.new(frameCount)
    local self = setmetatable(Timeline.new(frameCount), CurveTimeline)
    self.curves = {}
    return self
end

function CurveTimeline:setLinear(frameIndex)
    if not self.curves then
        self.curves = {}
    end
    self.curves[frameIndex] = nil -- nil means linear
end

function CurveTimeline:setStepped(frameIndex)
    if not self.curves then
        self.curves = {}
    end
    self.curves[frameIndex] = "stepped"
end

function CurveTimeline:setCurve(frameIndex, cx1, cy1, cx2, cy2, cx3, cy3, cx4, cy4)
    if not self.curves then
        self.curves = {}
    end

    -- If 8 arguments are provided, it's a 2D curve (separate X and Y)
    if cx3 then
        self.curves[frameIndex] = {
            x = {cx1, cy1, cx2, cy2},
            y = {cx3, cy3, cx4, cy4}
        }
    else
        self.curves[frameIndex] = {cx1, cy1, cx2, cy2}
    end
end

function CurveTimeline:getCurvePercent(frameIndex, percent, dimension)
    -- dimension: 0 for X/default, 1 for Y
    local curve = self.curves and self.curves[frameIndex]

    if not curve then
        return percent -- linear
    end

    if curve == "stepped" then
        return 0
    end

    local c = curve
    if type(curve.x) == "table" then
        if dimension == 1 then -- Y dimension
            c = curve.y
        else -- X dimension
            c = curve.x
        end
    end

    local cx1, cy1, cx2, cy2 = c[1], c[2], c[3], c[4]

    -- Solve for t given x (percent)
    -- Bezier curve for X axis: 0, cx1, cx2, 1
    -- We want to find t such that Bx(t) = percent

    local t = percent
    -- Iterate to find t
    for _ = 1, 5 do
        local u = 1 - t
        local tt = t * t
        local uu = u * u
        local ttt = tt * t

        -- x(t) = 3*(1-t)^2*t*cx1 + 3*(1-t)*t^2*cx2 + t^3
        local x = 3 * uu * t * cx1 + 3 * u * tt * cx2 + ttt
        
        local d = x - percent
        if math.abs(d) < 0.0001 then break end

        -- Derivative
        -- B'(t) = 3(1-t)^2(P1-P0) + 6(1-t)t(P2-P1) + 3t^2(P3-P2)
        -- P0=0, P1=cx1, P2=cx2, P3=1
        local dx = 3 * uu * cx1 + 6 * u * t * (cx2 - cx1) + 3 * tt * (1 - cx2)

        if dx == 0 then break end
        t = t - d / dx
    end

    t = math.max(0, math.min(1, t))

    -- Calculate y using t
    -- By(t) = 3(1-t)^2*t*cy1 + 3(1-t)t^2*cy2 + t^3
    local u = 1 - t
    local tt = t * t
    local uu = u * u
    local ttt = tt * t

    return 3 * uu * t * cy1 + 3 * u * tt * cy2 + ttt
end


local RotateTimeline = {}
RotateTimeline.__index = RotateTimeline
setmetatable(RotateTimeline, {__index = CurveTimeline})

function RotateTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), RotateTimeline)
    return self
end

function RotateTimeline:getFrameEntries()
    return 2
end

function RotateTimeline:setFrame(frameIndex, time, degrees)
    local i = frameIndex * 2 + 1
    self.frames[i] = time
    self.frames[i + 1] = degrees
end

function RotateTimeline:apply(skeleton, _lastTime, time, _events, alpha, blend, _direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]

    if time < frames[1] then
        if blend == "setup" then
            bone.rotation = bone.data.rotation
        end
        return
    end

    local r = 0
    if time >= frames[#frames - 1] then
        r = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local before = frames[frameIndex] -- time at frameIndex
        local r1 = frames[frameIndex + 1]
        local after = frames[frameIndex + 2] -- time at next frame
        local r2 = frames[frameIndex + 3]

        local curveIndex = (frameIndex - 1) / 2
        local rawPercent = 1 - (time - after) / (before - after)
        local percent = self:getCurvePercent(curveIndex, rawPercent)

        local diff = r2 - r1
        while diff > 180 do diff = diff - 360 end
        while diff < -180 do diff = diff + 360 end

        r = r1 + diff * percent
    end

    if blend == "setup" then
        bone.rotation = bone.data.rotation + r * alpha
    else
        -- r is relative to setup pose, so we must add bone.data.rotation
        local target = bone.data.rotation + r

        -- Handle rotation wrapping (shortest path)
        local diff = target - bone.rotation
        while diff > 180 do diff = diff - 360 end
        while diff < -180 do diff = diff + 360 end

        bone.rotation = bone.rotation + diff * alpha
    end
end


local TranslateTimeline = {}
TranslateTimeline.__index = TranslateTimeline
setmetatable(TranslateTimeline, {__index = CurveTimeline})

function TranslateTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TranslateTimeline)
    return self
end

function TranslateTimeline:getFrameEntries()
    return 3
end

function TranslateTimeline:setFrame(frameIndex, time, x, y)
    local i = frameIndex * 3 + 1
    self.frames[i] = time
    self.frames[i + 1] = x
    self.frames[i + 2] = y
end

function TranslateTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]

    if time < frames[1] then
        if blend == "setup" then
            bone.x = bone.data.x
            bone.y = bone.data.y
        end
        return
    end

    local x = 0
    local y = 0

    if time >= frames[#frames - 2] then
        x = frames[#frames - 1]
        y = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 3)
        local before = frames[frameIndex]
        local x1 = frames[frameIndex + 1]
        local y1 = frames[frameIndex + 2]
        local after = frames[frameIndex + 3]
        local x2 = frames[frameIndex + 4]
        local y2 = frames[frameIndex + 5]
        local timePercent = 1 - (time - after) / (before - after)

        local percentX = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 0)
        local percentY = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 1)

        x = x1 + (x2 - x1) * percentX
        y = y1 + (y2 - y1) * percentY
    end

    if blend == "setup" then
        bone.x = bone.data.x + x * alpha
        bone.y = bone.data.y + y * alpha
    else
        bone.x = bone.x + (bone.data.x + x - bone.x) * alpha
        bone.y = bone.y + (bone.data.y + y - bone.y) * alpha
    end
end


local ScaleTimeline = {}
ScaleTimeline.__index = ScaleTimeline
setmetatable(ScaleTimeline, {__index = TranslateTimeline})

function ScaleTimeline.new(frameCount)
    local self = setmetatable(TranslateTimeline.new(frameCount), ScaleTimeline)
    return self
end

function ScaleTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]

    if time < frames[1] then
        if blend == "setup" then
            bone.scaleX = bone.data.scaleX
            bone.scaleY = bone.data.scaleY
        end
        return
    end

    local x = 0
    local y = 0

    if time >= frames[#frames - 2] then
        x = frames[#frames - 1] * bone.data.scaleX
        y = frames[#frames] * bone.data.scaleY
    else
        local frameIndex = mathModule.binarySearch(frames, time, 3)
        local before = frames[frameIndex]
        local x1 = frames[frameIndex + 1]
        local y1 = frames[frameIndex + 2]
        local after = frames[frameIndex + 3]
        local x2 = frames[frameIndex + 4]
        local y2 = frames[frameIndex + 5]
        local timePercent = 1 - (time - after) / (before - after)

        local percentX = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 0)
        local percentY = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 1)

        x = (x1 + (x2 - x1) * percentX) * bone.data.scaleX
        y = (y1 + (y2 - y1) * percentY) * bone.data.scaleY
    end

    if alpha == 1 then
        if blend == "add" then
            bone.scaleX = bone.scaleX + x - bone.data.scaleX
            bone.scaleY = bone.scaleY + y - bone.data.scaleY
        else
            bone.scaleX = x
            bone.scaleY = y
        end
    else
        local bx = 0
        local by = 0
        if blend == "setup" then
            bx = bone.data.scaleX
            by = bone.data.scaleY
        else
            bx = bone.scaleX
            by = bone.scaleY
        end

        -- Mixing logic for scale is multiplicative in some runtimes, but additive in others.
        -- Spine 3.8+ usually uses additive mixing for scale if not "add" blend.
        -- Let's stick to simple linear mix for now.
        if blend == "setup" then
            bone.scaleX = bx + (x - bx) * alpha
            bone.scaleY = by + (y - by) * alpha
        else
            bone.scaleX = bx + (x - bx) * alpha
            bone.scaleY = by + (y - by) * alpha
        end
    end
end

local ShearTimeline = {}
ShearTimeline.__index = ShearTimeline
setmetatable(ShearTimeline, {__index = TranslateTimeline})

function ShearTimeline.new(frameCount)
    local self = setmetatable(TranslateTimeline.new(frameCount), ShearTimeline)
    return self
end

function ShearTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]

    if time < frames[1] then
        if blend == "setup" then
            bone.shearX = bone.data.shearX
            bone.shearY = bone.data.shearY
        end
        return
    end

    local x = 0
    local y = 0

    if time >= frames[#frames - 2] then
        x = frames[#frames - 1]
        y = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 3)
        local before = frames[frameIndex]
        local x1 = frames[frameIndex + 1]
        local y1 = frames[frameIndex + 2]
        local after = frames[frameIndex + 3]
        local x2 = frames[frameIndex + 4]
        local y2 = frames[frameIndex + 5]
        local timePercent = 1 - (time - after) / (before - after)

        local percentX = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 0)
        local percentY = self:getCurvePercent((frameIndex - 1) / 3, timePercent, 1)

        x = x1 + (x2 - x1) * percentX
        y = y1 + (y2 - y1) * percentY
    end

    if blend == "setup" then
        bone.shearX = bone.data.shearX + x * alpha
        bone.shearY = bone.data.shearY + y * alpha
    else
        bone.shearX = bone.shearX + (bone.data.shearX + x - bone.shearX) * alpha
        bone.shearY = bone.shearY + (bone.data.shearY + y - bone.shearY) * alpha
    end
end


local ColorTimeline = {}
ColorTimeline.__index = ColorTimeline
setmetatable(ColorTimeline, {__index = CurveTimeline})

function ColorTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), ColorTimeline)
    return self
end

function ColorTimeline:getFrameEntries()
    return 5
end

function ColorTimeline:setFrame(frameIndex, time, r, g, b, a)
    local i = frameIndex * 5 + 1
    self.frames[i] = time
    self.frames[i + 1] = r
    self.frames[i + 2] = g
    self.frames[i + 3] = b
    self.frames[i + 4] = a
end

function ColorTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local slot = skeleton.slots[self.slotIndex]

    if time < frames[1] then
        if blend == "setup" then
            slot.color.r = slot.data.color.r
            slot.color.g = slot.data.color.g
            slot.color.b = slot.data.color.b
            slot.color.a = slot.data.color.a
        end
        return
    end

    local r = 0
    local g = 0
    local b = 0
    local a = 0

    if time >= frames[#frames - 4] then
        local i = #frames - 4
        r = frames[i]
        g = frames[i + 1]
        b = frames[i + 2]
        a = frames[i + 3]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 5)
        local before = frames[frameIndex]
        local r1 = frames[frameIndex + 1]
        local g1 = frames[frameIndex + 2]
        local b1 = frames[frameIndex + 3]
        local a1 = frames[frameIndex + 4]
        local after = frames[frameIndex + 5]
        local r2 = frames[frameIndex + 6]
        local g2 = frames[frameIndex + 7]
        local b2 = frames[frameIndex + 8]
        local a2 = frames[frameIndex + 9]
        local percent = self:getCurvePercent((frameIndex - 1) / 5, 1 - (time - after) / (before - after))

        r = r1 + (r2 - r1) * percent
        g = g1 + (g2 - g1) * percent
        b = b1 + (b2 - b1) * percent
        a = a1 + (a2 - a1) * percent
    end

    if alpha == 1 then
        slot.color.r = r
        slot.color.g = g
        slot.color.b = b
        slot.color.a = a
    else
        if blend == "setup" then
            slot.color.r = slot.data.color.r + (r - slot.data.color.r) * alpha
            slot.color.g = slot.data.color.g + (g - slot.data.color.g) * alpha
            slot.color.b = slot.data.color.b + (b - slot.data.color.b) * alpha
            slot.color.a = slot.data.color.a + (a - slot.data.color.a) * alpha
        else
            slot.color.r = slot.color.r + (r - slot.color.r) * alpha
            slot.color.g = slot.color.g + (g - slot.color.g) * alpha
            slot.color.b = slot.color.b + (b - slot.color.b) * alpha
            slot.color.a = slot.color.a + (a - slot.color.a) * alpha
        end
    end
end


local AttachmentTimeline = {}
AttachmentTimeline.__index = AttachmentTimeline
setmetatable(AttachmentTimeline, {__index = Timeline})

function AttachmentTimeline.new(frameCount)
    local self = setmetatable(Timeline.new(frameCount), AttachmentTimeline)
    self.attachmentNames = {}
    return self
end

function AttachmentTimeline:getFrameEntries()
    return 1
end

function AttachmentTimeline:setFrame(frameIndex, time, attachmentName)
    self.frames[frameIndex + 1] = time
    self.attachmentNames[frameIndex + 1] = attachmentName
end

function AttachmentTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local slot = skeleton.slots[self.slotIndex]
    if not slot then return end
    
    if #frames == 0 or not frames[1] then return end

    if time < frames[1] then
        if blend == "setup" then
            slot:setAttachment(slot.data.attachmentName and skeleton:getAttachment(slot.data.name, slot.data.attachmentName) or nil)
        end
        return
    end

    local lastTimeIndex = #frames

    local frameIndex = 0
    if time >= frames[lastTimeIndex] then
        frameIndex = lastTimeIndex
    else
        frameIndex = mathModule.binarySearch(frames, time, 1)
    end

    local attachmentName = self.attachmentNames[frameIndex]

    slot:setAttachment(attachmentName and skeleton:getAttachment(slot.data.name, attachmentName) or nil)
end


local DeformTimeline = {}
DeformTimeline.__index = DeformTimeline
setmetatable(DeformTimeline, {__index = CurveTimeline})

function DeformTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), DeformTimeline)
    self.vertices = {}
    self.offsets = {}
    return self
end

function DeformTimeline:getFrameEntries()
    return 1
end

function DeformTimeline:setFrame(frameIndex, time, vertices, offset)
    self.frames[frameIndex + 1] = time
    self.vertices[frameIndex + 1] = vertices or {}
    self.offsets[frameIndex + 1] = offset or 0
end

function DeformTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local slot = skeleton.slots[self.slotIndex]
    if not slot then return end

    local attachment = slot.attachment
    if not attachment then return end

    -- Check if attachment matches the timeline's attachment
    -- Logic: apply if (attachment == deformAttachment) || (inheritDeform && parentMesh == deformAttachment)
    -- Note: self.attachmentName is the name of the attachment this timeline targets (the "deformAttachment")
    -- But we only have the name here, not the object.
    -- However, attachment.name might not match if it's a linked mesh with a different name.
    -- So we need to check names?
    -- The timeline stores 'attachmentName'.
    -- If attachment.name == self.attachmentName -> Match.
    -- If attachment.parentMesh and attachment.inheritDeform -> Check parentMesh.name == self.attachmentName.
    
    local apply = false
    if attachment.name == self.attachmentName then
        apply = true
    elseif attachment.parentMesh and attachment.inheritDeform then
        if attachment.parentMesh.name == self.attachmentName then
            apply = true
        end
    end
    
    if not apply then return end

    local frames = self.frames
    if #frames == 0 or not frames[1] then return end

    if time < frames[1] then
        if blend == "setup" or direction == "out" then
            slot.attachmentVertices = nil
        end
        return
    end

    local deformCount = #attachment.vertices
    if deformCount == 0 then return end

    local out = {}
    for i = 1, deformCount do out[i] = 0 end

    local frameIndex
    if time >= frames[#frames] then
        frameIndex = #frames
        local verts = self.vertices[frameIndex] or {}
        local offset = self.offsets[frameIndex] or 0
        for i = 1, #verts do
            out[offset + i] = verts[i]
        end
    else
        frameIndex = mathModule.binarySearch(frames, time, 1)
        local prevIndex = frameIndex
        local nextIndex = frameIndex + 1
        local prevTime = frames[prevIndex]
        local nextTime = frames[nextIndex]
        local percent = (time - prevTime) / (nextTime - prevTime)
        percent = self:getCurvePercent(prevIndex, percent)

        local prevVerts = self.vertices[prevIndex] or {}
        local nextVerts = self.vertices[nextIndex] or {}
        local prevOffset = self.offsets[prevIndex] or 0
        local nextOffset = self.offsets[nextIndex] or 0

        local prevCount = #prevVerts
        local nextCount = #nextVerts
        
        -- Calculate range to iterate (union of both frames)
        -- We only need to update indices that are touched by either frame
        -- But 'out' is already zeroed, so we just need to write non-zero interpolated values?
        -- No, we need to write ALL values that deviate from 0.
        -- If prev has value and next is 0, we interpolate to 0.
        -- If both are 0, result is 0 (already set).
        
        -- Iterate from min start to max end
        local minStart = math.min(prevOffset, nextOffset) + 1
        local maxEnd = math.max(prevOffset + prevCount, nextOffset + nextCount)
        
        for i = minStart, maxEnd do
            local prevVal = 0
            local nextVal = 0
            
            -- Check if i is within prev frame range
            if i > prevOffset and i <= prevOffset + prevCount then
                prevVal = prevVerts[i - prevOffset]
            end
            
            -- Check if i is within next frame range
            if i > nextOffset and i <= nextOffset + nextCount then
                nextVal = nextVerts[i - nextOffset]
            end
            
            out[i] = prevVal + (nextVal - prevVal) * percent
        end
    end

    if alpha == 1 or not slot.attachmentVertices or #slot.attachmentVertices == 0 then
        slot.attachmentVertices = out
    else
        local existing = slot.attachmentVertices
        local res = {}
        local len = math.max(#existing, #out)
        for i = 1, len do
            local e = existing[i] or 0
            local v = out[i] or 0
            res[i] = e + (v - e) * alpha
        end
        slot.attachmentVertices = res
    end
end


local AnimationState = {}
AnimationState.__index = AnimationState

function AnimationState.new(animationStateData)
    local self = setmetatable({}, AnimationState)
    self.data = animationStateData
    self.tracks = {}
    self.events = {}
    self.listeners = {}
    self.queue = {}
    self.animations = {}
    return self
end

function AnimationState:addListener(listener)
    table.insert(self.listeners, listener)
end

function AnimationState:getCurrent(trackIndex)
    return self.tracks[trackIndex]
end

function AnimationState:fireEvent(eventType, ...)
    for _, listener in ipairs(self.listeners) do
        if listener[eventType] then
            listener[eventType](...)
        end
    end
end

function AnimationState:update(delta)
    for i, track in pairs(self.tracks) do
        if track then
            track:update(delta)

            if track.isComplete then
                -- Handle animation completion
                if track.listener then
                    track.listener:complete(i)
                end

                -- Clear completed track
                self.tracks[i] = nil
            end
        end
    end

    -- Process queued animations
    for _, entry in ipairs(self.queue) do
        self:setAnimation(entry.trackIndex, entry.animation, entry.loop)
    end
    self.queue = {}
end

function AnimationState:setAnimation(trackIndex, animationNameOrObject, loop)
    local track = self.tracks[trackIndex]

    -- Support both animation names (strings) and Animation objects
    local animation = animationNameOrObject
    if type(animationNameOrObject) == "string" then
        -- Look up animation by name from skeleton data
        if self.data and self.data.skeletonData and self.data.skeletonData.animations then
            animation = self.data.skeletonData.animations[animationNameOrObject]
            if not animation then
                print("Warning: Animation not found: " .. animationNameOrObject)
                return
            end
        else
            print("Warning: No skeleton data available to look up animation: " .. animationNameOrObject)
            return
        end
    end

    -- Calculate mix duration if we have animation state data and previous animation
    local mixDuration = 0
    if track and track.animation and self.data and animation then
        mixDuration = self.data:getMix(track.animation.name, animation.name)
    end

    -- Fire start event
    self:fireEvent("start", trackIndex)

    if not track then
        track = {
            animation = animation,
            loop = loop,
            time = 0,
            lastTime = 0,
            isComplete = false,
            mixDuration = mixDuration,
            mixTime = 0
        }
        self.tracks[trackIndex] = track
    else
        track.animation = animation
        track.loop = loop
        track.time = 0
        track.lastTime = 0
        track.isComplete = false
        track.mixDuration = mixDuration
        track.mixTime = 0
    end

    -- Update track function
    track.update = function(self, delta)
        self.time = self.time + delta
        -- print("Track time: " .. t.time)
        if not self.loop and self.time >= self.animation.duration then
            self.isComplete = true
            self.time = self.animation.duration
        end
    end
        track.setTrackTime = function(self, t)
        self.time = t or self.time
    end
    track.setTrackEnd = function(self, t)
        self.trackEnd = t
    end
    return track
end

function AnimationState:addAnimation(trackIndex, animation, loop, delay)
    local entry = {
        trackIndex = trackIndex,
        animation = animation,
        loop = loop,
        delay = delay or 0
    }
    table.insert(self.queue, entry)
end

function AnimationState:apply(skeleton)
    for _, track in pairs(self.tracks) do
        if track and track.animation then
            -- Use 'first' blend mode which will apply setup for constraints before animation data
            track.animation:apply(skeleton, track.lastTime, track.time, track.loop, self.events, 1, "first", 1)
            track.lastTime = track.time
        end
    end
end

local EventTimeline = {}
EventTimeline.__index = EventTimeline
setmetatable(EventTimeline, {__index = Timeline})

function EventTimeline.new(frameCount)
    local self = setmetatable(Timeline.new(frameCount), EventTimeline)
    self.events = {}
    return self
end

function EventTimeline:getFrameEntries()
    return 1
end

function EventTimeline:setFrame(frameIndex, time, event)
    self.frames[frameIndex + 1] = time
    self.events[frameIndex + 1] = event
end

function EventTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    if not events then return end

    local frames = self.frames
    local frameCount = #frames

    if lastTime > time then -- Fire events after jump
        self:apply(skeleton, lastTime, 999999, events, alpha, blend, direction)
        lastTime = -1
    elseif lastTime >= frames[frameCount] then -- Last time is after last frame
        return
    end

    if time < frames[1] then return end -- Time is before first frame

    local i = 0
    if lastTime < frames[1] then
        i = 1
    else
        i = mathModule.binarySearch(frames, lastTime, 1)
        local frame = frames[i]
        while i > 1 do -- Fire multiple events with the same time
            if frames[i - 1] ~= frame then break end
            i = i - 1
        end
    end

    while i <= frameCount and time >= frames[i] do
        table.insert(events, self.events[i])
        i = i + 1
    end
end


local DrawOrderTimeline = {}
DrawOrderTimeline.__index = DrawOrderTimeline
setmetatable(DrawOrderTimeline, {__index = Timeline})

function DrawOrderTimeline.new(frameCount)
    local self = setmetatable(Timeline.new(frameCount), DrawOrderTimeline)
    self.drawOrders = {}
    return self
end

function DrawOrderTimeline:getFrameEntries()
    return 1
end

function DrawOrderTimeline:setFrame(frameIndex, time, drawOrder)
    self.frames[frameIndex + 1] = time
    self.drawOrders[frameIndex + 1] = drawOrder
end

function DrawOrderTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames

    if #frames == 0 then return end

    if time < frames[1] then
        if blend == "setup" then
            -- Reset draw order
            for i, slot in ipairs(skeleton.slots) do
                skeleton.drawOrder[i] = slot
            end
        end
        return
    end

    local frameIndex = 0
    if time >= frames[#frames] then
        frameIndex = #frames
    else
        frameIndex = mathModule.binarySearch(frames, time, 1)
    end

    local drawOrderToSetupIndex = self.drawOrders[frameIndex]
    if not drawOrderToSetupIndex then return end

    local drawOrder = skeleton.drawOrder
    local slots = skeleton.slots

    -- Copy slots to drawOrder based on offsets
    -- This is complex. Spine runtime usually does:
    -- 1. Copy slots to drawOrder
    -- 2. Apply offsets

    -- But here we have pre-calculated drawOrder?
    -- No, setFrame receives `drawOrder` which is likely a list of offsets.

    -- Actually, let's look at how data.lua parses it.
    -- It passes `drawOrder` which is `animJson.drawOrder[i].offsets`.

    -- So `drawOrderToSetupIndex` is the offsets array.

    local offsets = drawOrderToSetupIndex

    -- Reset draw order first
    for i, slot in ipairs(slots) do
        drawOrder[i] = slot
    end

    -- Apply offsets
    for _, offset in ipairs(offsets) do
        local slotIndex = skeleton.data:findSlotIndex(offset.slot)
        local amount = offset.offset

        if slotIndex ~= -1 then
            local slot = slots[slotIndex + 1] -- 1-based
            -- Find slot in drawOrder
            local oldIndex = 0
            for i, s in ipairs(drawOrder) do
                if s == slot then
                    oldIndex = i
                    break
                end
            end

            if oldIndex > 0 then
                table.remove(drawOrder, oldIndex)
                table.insert(drawOrder, oldIndex + amount, slot)
            end
        end
    end
end
-- TwoColorTimeline
local TwoColorTimeline = {}
TwoColorTimeline.__index = TwoColorTimeline
setmetatable(TwoColorTimeline, {__index = CurveTimeline})

function TwoColorTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TwoColorTimeline)
    return self
end

function TwoColorTimeline:getFrameEntries()
    return 8 -- time, r, g, b, a, r2, g2, b2
end

function TwoColorTimeline:setFrame(frameIndex, time, r, g, b, a, r2, g2, b2)
    local i = frameIndex * 8 + 1
    self.frames[i] = time
    self.frames[i + 1] = r
    self.frames[i + 2] = g
    self.frames[i + 3] = b
    self.frames[i + 4] = a
    self.frames[i + 5] = r2
    self.frames[i + 6] = g2
    self.frames[i + 7] = b2
end

function TwoColorTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local slot = skeleton.slots[self.slotIndex]

    if time < frames[1] then
        if blend == "setup" then
            slot.color.r = slot.data.color.r
            slot.color.g = slot.data.color.g
            slot.color.b = slot.data.color.b
            slot.color.a = slot.data.color.a

            if slot.data.darkColor then
                slot.darkColor.r = slot.data.darkColor.r
                slot.darkColor.g = slot.data.darkColor.g
                slot.darkColor.b = slot.data.darkColor.b
            end
        end
        return
    end

    local r, g, b, a = 0, 0, 0, 0
    local r2, g2, b2 = 0, 0, 0

    if time >= frames[#frames - 7] then
        local i = #frames - 7
        r = frames[i + 1]  -- Skip time at frames[i]
        g = frames[i + 2]
        b = frames[i + 3]
        a = frames[i + 4]
        r2 = frames[i + 5]
        g2 = frames[i + 6]
        b2 = frames[i + 7]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 8)
        local before = frames[frameIndex]
        local r1 = frames[frameIndex + 1]
        local g1 = frames[frameIndex + 2]
        local b1 = frames[frameIndex + 3]
        local a1 = frames[frameIndex + 4]
        local r21 = frames[frameIndex + 5]
        local g21 = frames[frameIndex + 6]
        local b21 = frames[frameIndex + 7]

        local after = frames[frameIndex + 8]
        local r2_ = frames[frameIndex + 9]
        local g2_ = frames[frameIndex + 10]
        local b2_ = frames[frameIndex + 11]
        local a2 = frames[frameIndex + 12]
        local r22 = frames[frameIndex + 13]
        local g22 = frames[frameIndex + 14]
        local b22 = frames[frameIndex + 15]

        local percent = self:getCurvePercent(frameIndex / 8, 1 - (time - after) / (before - after))

        r = r1 + (r2_ - r1) * percent
        g = g1 + (g2_ - g1) * percent
        b = b1 + (b2_ - b1) * percent
        a = a1 + (a2 - a1) * percent
        r2 = r21 + (r22 - r21) * percent
        g2 = g21 + (g22 - g21) * percent
        b2 = b21 + (b22 - b21) * percent
    end

    if alpha == 1 then
        slot.color.r = r
        slot.color.g = g
        slot.color.b = b
        slot.color.a = a

        if slot.darkColor then
            slot.darkColor.r = r2
            slot.darkColor.g = g2
            slot.darkColor.b = b2
        end
    else
        if blend == "setup" then
            slot.color.r = slot.data.color.r + (r - slot.data.color.r) * alpha
            slot.color.g = slot.data.color.g + (g - slot.data.color.g) * alpha
            slot.color.b = slot.data.color.b + (b - slot.data.color.b) * alpha
            slot.color.a = slot.data.color.a + (a - slot.data.color.a) * alpha

            if slot.darkColor then
                slot.darkColor.r = slot.data.darkColor.r + (r2 - slot.data.darkColor.r) * alpha
                slot.darkColor.g = slot.data.darkColor.g + (g2 - slot.data.darkColor.g) * alpha
                slot.darkColor.b = slot.data.darkColor.b + (b2 - slot.data.darkColor.b) * alpha
            end
        else
            slot.color.r = slot.color.r + (r - slot.color.r) * alpha
            slot.color.g = slot.color.g + (g - slot.color.g) * alpha
            slot.color.b = slot.color.b + (b - slot.color.b) * alpha
            slot.color.a = slot.color.a + (a - slot.color.a) * alpha

            if slot.darkColor then
                slot.darkColor.r = slot.darkColor.r + (r2 - slot.darkColor.r) * alpha
                slot.darkColor.g = slot.darkColor.g + (g2 - slot.darkColor.g) * alpha
                slot.darkColor.b = slot.darkColor.b + (b2 - slot.darkColor.b) * alpha
            end
        end
    end
end

-- IkConstraintTimeline
local IkConstraintTimeline = {}
IkConstraintTimeline.__index = IkConstraintTimeline
setmetatable(IkConstraintTimeline, {__index = CurveTimeline})

function IkConstraintTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), IkConstraintTimeline)
    return self
end

function IkConstraintTimeline:getFrameEntries()
    return 5 -- time, mix, bendDirection, compress, stretch
end

function IkConstraintTimeline:setFrame(frameIndex, time, mix, bendDirection, compress, stretch)
    local i = frameIndex * 5 + 1
    self.frames[i] = time
    self.frames[i + 1] = mix
    self.frames[i + 2] = bendDirection
    self.frames[i + 3] = compress and 1 or 0
    self.frames[i + 4] = stretch and 1 or 0
end

function IkConstraintTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local constraint = skeleton.ikConstraints[self.ikConstraintIndex]
    if not constraint then return end

    if time < frames[1] then
        if blend == "setup" then
            constraint.mix = constraint.data.mix
            constraint.bendDirection = constraint.data.bendDirection
            constraint.compress = constraint.data.compress
            constraint.stretch = constraint.data.stretch
        end
        return
    end

    if time >= frames[#frames - 4] then
        local i = #frames - 4
        constraint.mix = constraint.mix + (frames[i + 1] - constraint.mix) * alpha
        if direction == "out" then
            constraint.bendDirection = constraint.data.bendDirection
            constraint.compress = constraint.data.compress
            constraint.stretch = constraint.data.stretch
        else
            constraint.bendDirection = frames[i + 2]
            constraint.compress = frames[i + 3] > 0
            constraint.stretch = frames[i + 4] > 0
        end
        return
    end

    local frameIndex = mathModule.binarySearch(frames, time, 5)
    local before = frames[frameIndex]
    local mix1 = frames[frameIndex + 1]
    local after = frames[frameIndex + 5]
    local mix2 = frames[frameIndex + 6]
    local percent = self:getCurvePercent((frameIndex - 1) / 5, 1 - (time - after) / (before - after))

    if blend == "setup" then
        constraint.mix = constraint.data.mix + (mix1 + (mix2 - mix1) * percent - constraint.data.mix) * alpha
    else
        constraint.mix = constraint.mix + (mix1 + (mix2 - mix1) * percent - constraint.mix) * alpha
    end

    if direction == "out" then
        constraint.bendDirection = constraint.data.bendDirection
        constraint.compress = constraint.data.compress
        constraint.stretch = constraint.data.stretch
    else
        constraint.bendDirection = frames[frameIndex + 2]
        constraint.compress = frames[frameIndex + 3] > 0
        constraint.stretch = frames[frameIndex + 4] > 0
    end
end

-- TransformConstraintTimeline
local TransformConstraintTimeline = {}
TransformConstraintTimeline.__index = TransformConstraintTimeline
setmetatable(TransformConstraintTimeline, {__index = CurveTimeline})

function TransformConstraintTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TransformConstraintTimeline)
    return self
end

function TransformConstraintTimeline:getFrameEntries()
    return 5 -- time, rotateMix, translateMix, scaleMix, shearMix
end

function TransformConstraintTimeline:setFrame(frameIndex, time, rotateMix, translateMix, scaleMix, shearMix)
    local i = frameIndex * 5 + 1
    self.frames[i] = time
    self.frames[i + 1] = rotateMix
    self.frames[i + 2] = translateMix
    self.frames[i + 3] = scaleMix
    self.frames[i + 4] = shearMix
end

function TransformConstraintTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local constraint = skeleton.transformConstraints[self.transformConstraintIndex]
    if not constraint then return end

    if time < frames[1] then
        if blend == "setup" then
            constraint.mixRotate = constraint.data.mixRotate
            constraint.mixX = constraint.data.mixX
            constraint.mixY = constraint.data.mixY -- Assuming mixX/mixY are same for translateMix?
            -- Wait, data has translateMix, but runtime uses mixX/mixY?
            -- Let's assume translateMix applies to both mixX and mixY
            constraint.mixScaleX = constraint.data.mixScaleX
            constraint.mixScaleY = constraint.data.mixScaleY
            constraint.mixShearY = constraint.data.mixShearY
        end
        return
    end

    local rotate, translate, scale, shear = 0, 0, 0, 0

    if time >= frames[#frames - 4] then
        local i = #frames - 4
        rotate = frames[i + 1]
        translate = frames[i + 2]
        scale = frames[i + 3]
        shear = frames[i + 4]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 5)
        local before = frames[frameIndex]
        local rotate1 = frames[frameIndex + 1]
        local translate1 = frames[frameIndex + 2]
        local scale1 = frames[frameIndex + 3]
        local shear1 = frames[frameIndex + 4]

        local after = frames[frameIndex + 5]
        local rotate2 = frames[frameIndex + 6]
        local translate2 = frames[frameIndex + 7]
        local scale2 = frames[frameIndex + 8]
        local shear2 = frames[frameIndex + 9]

        local percent = self:getCurvePercent((frameIndex - 1) / 5, 1 - (time - after) / (before - after))

        rotate = rotate1 + (rotate2 - rotate1) * percent
        translate = translate1 + (translate2 - translate1) * percent
        scale = scale1 + (scale2 - scale1) * percent
        shear = shear1 + (shear2 - shear1) * percent
    end

    if blend == "setup" then
        constraint.mixRotate = constraint.data.mixRotate + (rotate - constraint.data.mixRotate) * alpha
        constraint.mixX = constraint.data.mixX + (translate - constraint.data.mixX) * alpha
        constraint.mixY = constraint.data.mixY + (translate - constraint.data.mixY) * alpha
        constraint.mixScaleX = constraint.data.mixScaleX + (scale - constraint.data.mixScaleX) * alpha
        constraint.mixScaleY = constraint.data.mixScaleY + (scale - constraint.data.mixScaleY) * alpha
        constraint.mixShearY = constraint.data.mixShearY + (shear - constraint.data.mixShearY) * alpha
    else
        constraint.mixRotate = constraint.mixRotate + (rotate - constraint.mixRotate) * alpha
        constraint.mixX = constraint.mixX + (translate - constraint.mixX) * alpha
        constraint.mixY = constraint.mixY + (translate - constraint.mixY) * alpha
        constraint.mixScaleX = constraint.mixScaleX + (scale - constraint.mixScaleX) * alpha
        constraint.mixScaleY = constraint.mixScaleY + (scale - constraint.mixScaleY) * alpha
        constraint.mixShearY = constraint.mixShearY + (shear - constraint.mixShearY) * alpha
    end
end

-- PathConstraintTimeline
local PathConstraintTimeline = {}
PathConstraintTimeline.__index = PathConstraintTimeline
setmetatable(PathConstraintTimeline, {__index = CurveTimeline})

function PathConstraintTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), PathConstraintTimeline)
    return self
end

function PathConstraintTimeline:getFrameEntries()
    return 5 -- time, position, spacing, rotateMix, translateMix
end

function PathConstraintTimeline:setFrame(frameIndex, time, position, spacing, rotateMix, translateMix)
    local i = frameIndex * 5 + 1
    self.frames[i] = time
    self.frames[i + 1] = position
    self.frames[i + 2] = spacing
    self.frames[i + 3] = rotateMix
    self.frames[i + 4] = translateMix
end

function PathConstraintTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    if not frames or not frames[1] then
        local constraint = skeleton.pathConstraints[self.pathConstraintIndex]
        if not constraint then return end
        if blend == "setup" then
            constraint.position = constraint.data.position
            constraint.spacing = constraint.data.spacing
            constraint.mixRotate = constraint.data.rotateMix
            constraint.mixX = constraint.data.translateMix
            constraint.mixY = constraint.data.translateMix
        end
        return
    end
    local constraint = skeleton.pathConstraints[self.pathConstraintIndex]
    if not constraint then return end

    if time < frames[1] then
        if blend == "setup" then
            constraint.position = constraint.data.position
            constraint.spacing = constraint.data.spacing
            constraint.mixRotate = constraint.data.rotateMix
            constraint.mixX = constraint.data.translateMix
            constraint.mixY = constraint.data.translateMix
        end
        return
    end

    local position, spacing, rotateMix, translateMix = 0, 0, 0, 0

    if time >= frames[#frames - 4] then
        local i = #frames - 4
        position = frames[i + 1]
        spacing = frames[i + 2]
        rotateMix = frames[i + 3]
        translateMix = frames[i + 4]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 5)
        local before = frames[frameIndex]
        local position1 = frames[frameIndex + 1]
        local spacing1 = frames[frameIndex + 2]
        local rotateMix1 = frames[frameIndex + 3]
        local translateMix1 = frames[frameIndex + 4]

        local after = frames[frameIndex + 5]
        local position2 = frames[frameIndex + 6]
        local spacing2 = frames[frameIndex + 7]
        local rotateMix2 = frames[frameIndex + 8]
        local translateMix2 = frames[frameIndex + 9]

        local percent = self:getCurvePercent((frameIndex - 1) / 5, 1 - (time - after) / (before - after))

        position = position1 + (position2 - position1) * percent
        spacing = spacing1 + (spacing2 - spacing1) * percent
        rotateMix = rotateMix1 + (rotateMix2 - rotateMix1) * percent
        translateMix = translateMix1 + (translateMix2 - translateMix1) * percent
    end

    if blend == "setup" then
        constraint.position = constraint.data.position + (position - constraint.data.position) * alpha
        constraint.spacing = constraint.data.spacing + (spacing - constraint.data.spacing) * alpha
        constraint.mixRotate = constraint.data.rotateMix + (rotateMix - constraint.data.rotateMix) * alpha
        constraint.mixX = constraint.data.translateMix + (translateMix - constraint.data.translateMix) * alpha
        constraint.mixY = constraint.data.translateMix + (translateMix - constraint.data.translateMix) * alpha
    else
        constraint.position = constraint.position + (position - constraint.position) * alpha
        constraint.spacing = constraint.spacing + (spacing - constraint.spacing) * alpha
        constraint.mixRotate = constraint.mixRotate + (rotateMix - constraint.mixRotate) * alpha
        constraint.mixX = constraint.mixX + (translateMix - constraint.mixX) * alpha
        constraint.mixY = constraint.mixY + (translateMix - constraint.mixY) * alpha
    end
end

-- Timeline for X-only translation (TranslateXTimeline)
local TranslateXTimeline = {}
TranslateXTimeline.__index = TranslateXTimeline
setmetatable(TranslateXTimeline, {__index = CurveTimeline})

function TranslateXTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TranslateXTimeline)
    return self
end

function TranslateXTimeline:getFrameEntries()
    return 2
end

function TranslateXTimeline:setFrame(frameIndex, time, value)
    frameIndex = frameIndex * 2
    self.frames[frameIndex + 1] = time
    self.frames[frameIndex + 2] = value
end

function TranslateXTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]
    if not bone then 
        return 
    end

    if time < frames[1] then
        if blend == "setup" then
            bone.x = bone.data.x
        end
        return
    end

    local x = 0
    if time >= frames[#frames - 1] then
        x = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local time1 = frames[frameIndex]
        local value1 = frames[frameIndex + 1]
        local time2 = frames[frameIndex + 2]
        local value2 = frames[frameIndex + 3]
        local percent = self:getCurvePercent((frameIndex - 1) / 2, 1 - (time - time2) / (time1 - time2))
        
        x = value1 + (value2 - value1) * percent
    end

    -- print("DEBUG: TranslateXTimeline apply bone " .. bone.data.name .. " x=" .. x .. " alpha=" .. alpha)
    if bone.data.name == "pot-control" then
         print("DEBUG: TranslateXTimeline apply pot-control x=" .. x .. " time=" .. time)
    end

    if blend == "setup" then
        bone.x = bone.data.x + x * alpha
    else
        bone.x = bone.x + (bone.data.x + x - bone.x) * alpha
    end
end

-- Timeline for Y-only translation (TranslateYTimeline)
local TranslateYTimeline = {}
TranslateYTimeline.__index = TranslateYTimeline
setmetatable(TranslateYTimeline, {__index = CurveTimeline})

function TranslateYTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TranslateYTimeline)
    return self
end

function TranslateYTimeline:getFrameEntries()
    return 2
end

function TranslateYTimeline:setFrame(frameIndex, time, value)
    frameIndex = frameIndex * 2
    self.frames[frameIndex + 1] = time
    self.frames[frameIndex + 2] = value
end

function TranslateYTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]
    if not bone then return end

    if time < frames[1] then
        if blend == "setup" then
            bone.y = bone.data.y
        end
        return
    end

    local y = 0
    if time >= frames[#frames - 1] then
        y = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local time1 = frames[frameIndex]
        local value1 = frames[frameIndex + 1]
        local time2 = frames[frameIndex + 2]
        local value2 = frames[frameIndex + 3]
        local percent = self:getCurvePercent((frameIndex - 1) / 2, 1 - (time - time2) / (time1 - time2))
        
        y = value1 + (value2 - value1) * percent
    end

    if blend == "setup" then
        bone.y = bone.data.y + y * alpha
    else
        bone.y = bone.y + (bone.data.y + y - bone.y) * alpha
    end
end

-- PhysicsConstraintTimeline
local PhysicsConstraintTimeline = {}
PhysicsConstraintTimeline.__index = PhysicsConstraintTimeline
setmetatable(PhysicsConstraintTimeline, {__index = CurveTimeline})

PhysicsConstraintTimeline.INERTIA = 0
PhysicsConstraintTimeline.STRENGTH = 1
PhysicsConstraintTimeline.DAMPING = 2
PhysicsConstraintTimeline.MASS_INVERSE = 3
PhysicsConstraintTimeline.WIND = 4
PhysicsConstraintTimeline.GRAVITY = 5
PhysicsConstraintTimeline.MIX = 6

function PhysicsConstraintTimeline.new(frameCount, type)
    local self = setmetatable(CurveTimeline.new(frameCount), PhysicsConstraintTimeline)
    self.type = type
    return self
end

function PhysicsConstraintTimeline:getFrameEntries()
    return 2
end

function PhysicsConstraintTimeline:setFrame(frameIndex, time, value)
    frameIndex = frameIndex * 2
    self.frames[frameIndex + 1] = time
    self.frames[frameIndex + 2] = value
end

function PhysicsConstraintTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local constraint = skeleton.physicsConstraints[self.physicsConstraintIndex]
    if not constraint then return end

    if time < frames[1] then
        if blend == "setup" then
             local t = self.type
             if t == PhysicsConstraintTimeline.INERTIA then constraint.inertia = constraint.data.inertia
             elseif t == PhysicsConstraintTimeline.STRENGTH then constraint.strength = constraint.data.strength
             elseif t == PhysicsConstraintTimeline.DAMPING then constraint.damping = constraint.data.damping
             elseif t == PhysicsConstraintTimeline.MASS_INVERSE then constraint.massInverse = constraint.data.massInverse
             elseif t == PhysicsConstraintTimeline.WIND then constraint.wind = constraint.data.wind
             elseif t == PhysicsConstraintTimeline.GRAVITY then constraint.gravity = constraint.data.gravity
             elseif t == PhysicsConstraintTimeline.MIX then constraint.mix = constraint.data.mix
             end
        end
        return
    end

    local val = 0
    if time >= frames[#frames - 1] then
        val = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local time1 = frames[frameIndex]
        local value1 = frames[frameIndex + 1]
        local time2 = frames[frameIndex + 2]
        local value2 = frames[frameIndex + 3]
        local percent = self:getCurvePercent((frameIndex - 1) / 2, 1 - (time - time2) / (time1 - time2))
        
        val = value1 + (value2 - value1) * percent
    end

    local t = self.type
    if blend == "setup" then
        if t == PhysicsConstraintTimeline.INERTIA then constraint.inertia = constraint.data.inertia + (val - constraint.data.inertia) * alpha
        elseif t == PhysicsConstraintTimeline.STRENGTH then constraint.strength = constraint.data.strength + (val - constraint.data.strength) * alpha
        elseif t == PhysicsConstraintTimeline.DAMPING then constraint.damping = constraint.data.damping + (val - constraint.data.damping) * alpha
        elseif t == PhysicsConstraintTimeline.MASS_INVERSE then constraint.massInverse = constraint.data.massInverse + (val - constraint.data.massInverse) * alpha
        elseif t == PhysicsConstraintTimeline.WIND then constraint.wind = constraint.data.wind + (val - constraint.data.wind) * alpha
        elseif t == PhysicsConstraintTimeline.GRAVITY then constraint.gravity = constraint.data.gravity + (val - constraint.data.gravity) * alpha
        elseif t == PhysicsConstraintTimeline.MIX then constraint.mix = constraint.data.mix + (val - constraint.data.mix) * alpha
        end
    else
        if t == PhysicsConstraintTimeline.INERTIA then constraint.inertia = constraint.inertia + (val - constraint.inertia) * alpha
        elseif t == PhysicsConstraintTimeline.STRENGTH then constraint.strength = constraint.strength + (val - constraint.strength) * alpha
        elseif t == PhysicsConstraintTimeline.DAMPING then constraint.damping = constraint.damping + (val - constraint.damping) * alpha
        elseif t == PhysicsConstraintTimeline.MASS_INVERSE then constraint.massInverse = constraint.massInverse + (val - constraint.massInverse) * alpha
        elseif t == PhysicsConstraintTimeline.WIND then constraint.wind = constraint.wind + (val - constraint.wind) * alpha
        elseif t == PhysicsConstraintTimeline.GRAVITY then constraint.gravity = constraint.gravity + (val - constraint.gravity) * alpha
        elseif t == PhysicsConstraintTimeline.MIX then constraint.mix = constraint.mix + (val - constraint.mix) * alpha
        end
    end
end

-- PhysicsConstraintResetTimeline
local PhysicsConstraintResetTimeline = {}
PhysicsConstraintResetTimeline.__index = PhysicsConstraintResetTimeline
setmetatable(PhysicsConstraintResetTimeline, {__index = Timeline})

function PhysicsConstraintResetTimeline.new(frameCount)
    local self = setmetatable(Timeline.new(frameCount), PhysicsConstraintResetTimeline)
    return self
end

function PhysicsConstraintResetTimeline:getFrameEntries()
    return 1
end

function PhysicsConstraintResetTimeline:setFrame(frameIndex, time)
    self.frames[frameIndex + 1] = time
end

function PhysicsConstraintResetTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local constraint = skeleton.physicsConstraints[self.physicsConstraintIndex]
    if not constraint then return end

    if lastTime > time then -- Fire events after jump
        -- When looping, we wrap around.
        -- We must fire any resets that are AFTER lastTime (up to end of duration)
        -- AND any resets that are BEFORE time (from 0).
        
        -- DISABLE FLUSH for Physics: Resetting physics at loop boundary kills momentum.
        -- Only reset if explicitly keyed at the start of the new loop.
        lastTime = -1
    elseif lastTime >= frames[#frames] then -- Last time is after last frame
        return
    end

    if time < frames[1] then return end -- Time is before first frame

    local i = 0
    if lastTime < frames[1] then
        i = 1
    else
        i = mathModule.binarySearch(frames, lastTime, 1) + 1
    end

    while i <= #frames and time >= frames[i] do
        if lastTime < frames[i] then
            constraint:update("reset")
        end
        i = i + 1
    end
end

-- Timeline for Y-only translation (TranslateYTimeline)
local TranslateYTimeline = {}
TranslateYTimeline.__index = TranslateYTimeline
setmetatable(TranslateYTimeline, {__index = CurveTimeline})

function TranslateYTimeline.new(frameCount)
    local self = setmetatable(CurveTimeline.new(frameCount), TranslateYTimeline)
    return self
end

function TranslateYTimeline:getFrameEntries()
    return 2
end

function TranslateYTimeline:setFrame(frameIndex, time, value)
    frameIndex = frameIndex * 2
    self.frames[frameIndex + 1] = time
    self.frames[frameIndex + 2] = value
end

function TranslateYTimeline:apply(skeleton, lastTime, time, events, alpha, blend, direction)
    local frames = self.frames
    local bone = skeleton.bones[self.boneIndex]
    if not bone then return end

    if time < frames[1] then
        if blend == "setup" then
            bone.y = bone.data.y
        end
        return
    end

    local y = 0
    if time >= frames[#frames - 1] then
        y = frames[#frames]
    else
        local frameIndex = mathModule.binarySearch(frames, time, 2)
        local time1 = frames[frameIndex]
        local value1 = frames[frameIndex + 1]
        local time2 = frames[frameIndex + 2]
        local value2 = frames[frameIndex + 3]
        local percent = self:getCurvePercent((frameIndex - 1) / 2, 1 - (time - time2) / (time1 - time2))
        
        y = value1 + (value2 - value1) * percent
    end

    if blend == "setup" then
        bone.y = bone.data.y + y * alpha
    else
        bone.y = bone.y + (bone.data.y + y - bone.y) * alpha
    end
end

-- Module exports
local animationModule = {
    Animation = Animation,
    Timeline = Timeline,
    CurveTimeline = CurveTimeline,
    RotateTimeline = RotateTimeline,
    TranslateTimeline = TranslateTimeline,
    TranslateXTimeline = TranslateXTimeline,
    TranslateYTimeline = TranslateYTimeline,
    ScaleTimeline = ScaleTimeline,
    ShearTimeline = ShearTimeline,
    ColorTimeline = ColorTimeline,
    TwoColorTimeline = TwoColorTimeline,
    AttachmentTimeline = AttachmentTimeline,
    EventTimeline = EventTimeline,
    DrawOrderTimeline = DrawOrderTimeline,
    IkConstraintTimeline = IkConstraintTimeline,
    TransformConstraintTimeline = TransformConstraintTimeline,
    PathConstraintTimeline = PathConstraintTimeline,
    PhysicsConstraintTimeline = PhysicsConstraintTimeline,
    PhysicsConstraintResetTimeline = PhysicsConstraintResetTimeline,
    DeformTimeline = DeformTimeline,
    AnimationState = AnimationState
}

return animationModule
