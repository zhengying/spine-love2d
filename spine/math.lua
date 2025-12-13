-- Spine Love2D Runtime - 数学库模块
-- 提供向量、矩阵、变换等数学计算功能

local math_module = {}

-- 向量2D
local Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x, y)
  return setmetatable({x = x or 0, y = y or 0}, Vector2)
end

function Vector2:length()
  return math.sqrt(self.x * self.x + self.y * self.y)
end

function Vector2:lengthSquared()
  return self.x * self.x + self.y * self.y
end

function Vector2:normalize()
  local len = self:length()
  if len > 0 then
    self.x = self.x / len
    self.y = self.y / len
  end
  return self
end

function Vector2:normalized()
  local len = self:length()
  if len > 0 then
    return Vector2.new(self.x / len, self.y / len)
  end
  return Vector2.new(0, 0)
end

function Vector2:dot(other)
  return self.x * other.x + self.y * other.y
end

function Vector2:cross(other)
  return self.x * other.y - self.y * other.x
end

function Vector2:add(other)
  self.x = self.x + other.x
  self.y = self.y + other.y
  return self
end

function Vector2:sub(other)
  self.x = self.x - other.x
  self.y = self.y - other.y
  return self
end

function Vector2:mul(scalar)
  self.x = self.x * scalar
  self.y = self.y * scalar
  return self
end

function Vector2:div(scalar)
  self.x = self.x / scalar
  self.y = self.y / scalar
  return self
end

function Vector2:lerp(other, t)
  return Vector2.new(
    self.x + (other.x - self.x) * t,
    self.y + (other.y - self.y) * t
  )
end

function Vector2:distance(other)
  local dx = self.x - other.x
  local dy = self.y - other.y
  return math.sqrt(dx * dx + dy * dy)
end

function Vector2:distanceSquared(other)
  local dx = self.x - other.x
  local dy = self.y - other.y
  return dx * dx + dy * dy
end

function Vector2:rotate(angle)
  local cos = math.cos(angle)
  local sin = math.sin(angle)
  local newX = self.x * cos - self.y * sin
  local newY = self.x * sin + self.y * cos
  self.x, self.y = newX, newY
  return self
end

function Vector2:clone()
  return Vector2.new(self.x, self.y)
end

function Vector2:__tostring()
  return string.format("Vector2(%.3f, %.3f)", self.x, self.y)
end

math_module.Vector2 = Vector2

-- 变换矩阵
local Transform = {}
Transform.__index = Transform

function Transform.new()
  return setmetatable({
    x = 0, y = 0,
    rotation = 0,
    scaleX = 1, scaleY = 1,
    shearX = 0, shearY = 0,
    a = 1, b = 0, c = 0, d = 1,
    worldX = 0, worldY = 0,
    worldRotation = 0,
    worldScaleX = 1, worldScaleY = 1,
    worldShearX = 0, worldShearY = 0
  }, Transform)
end

function Transform:setPosition(x, y)
  self.x, self.y = x, y
  return self
end

function Transform:setRotation(rotation)
  self.rotation = rotation
  return self
end

function Transform:setScale(scaleX, scaleY)
  self.scaleX, self.scaleY = scaleX, scaleY or scaleX
  return self
end

function Transform:setShear(shearX, shearY)
  self.shearX, self.shearY = shearX, shearY or 0
  return self
end

function Transform:update()
  local cos = math.cos(self.rotation)
  local sin = math.sin(self.rotation)
  self.a = cos * self.scaleX
  self.b = sin * self.scaleX
  self.c = -sin * self.scaleY
  self.d = cos * self.scaleY
end

function Transform:apply(point)
  self:update()
  local x = point.x
  local y = point.y
  return Vector2.new(
    x * self.a + y * self.b + self.x,
    x * self.c + y * self.d + self.y
  )
end

function Transform:applyToVector(x, y)
  self:update()
  return 
    x * self.a + y * self.b + self.x,
    x * self.c + y * self.d + self.y
end

function Transform:worldToLocal(worldPoint)
  local dx = worldPoint.x - self.worldX
  local dy = worldPoint.y - self.worldY
  local cos = math.cos(-self.worldRotation)
  local sin = math.sin(-self.worldRotation)
  local x = dx * cos - dy * sin
  local y = dx * sin + dy * cos
  return Vector2.new(x / self.worldScaleX, y / self.worldScaleY)
end

function Transform:localToWorld(localPoint)
  local x = localPoint.x * self.worldScaleX
  local y = localPoint.y * self.worldScaleY
  local cos = math.cos(self.worldRotation)
  local sin = math.sin(self.worldRotation)
  return Vector2.new(
    x * cos - y * sin + self.worldX,
    x * sin + y * cos + self.worldY
  )
end

function Transform:copyFrom(other)
  self.x, self.y = other.x, other.y
  self.rotation = other.rotation
  self.scaleX, self.scaleY = other.scaleX, other.scaleY
  self.shearX, self.shearY = other.shearX, other.shearY
  self:update()
  return self
end

function Transform:copyFromWorld(other)
  self.worldX, self.worldY = other.worldX, other.worldY
  self.worldRotation = other.worldRotation
  self.worldScaleX, self.worldScaleY = other.worldScaleX, other.worldScaleY
  self.worldShearX, self.worldShearY = other.worldShearX, other.worldShearY
  return self
end

function Transform:clone()
  local t = Transform.new()
  t:copyFrom(self)
  return t
end

math_module.Transform = Transform

-- 颜色工具
local Color = {}
Color.__index = Color

function Color.new(r, g, b, a)
  return setmetatable({
    r = r or 1, g = g or 1, b = b or 1, a = a or 1
  }, Color)
end

function Color:fromHex(hex)
  hex = hex:gsub("#", "")
  if #hex == 6 then
    self.r = tonumber(hex:sub(1, 2), 16) / 255
    self.g = tonumber(hex:sub(3, 4), 16) / 255
    self.b = tonumber(hex:sub(5, 6), 16) / 255
    self.a = 1
  elseif #hex == 8 then
    self.r = tonumber(hex:sub(1, 2), 16) / 255
    self.g = tonumber(hex:sub(3, 4), 16) / 255
    self.b = tonumber(hex:sub(5, 6), 16) / 255
    self.a = tonumber(hex:sub(7, 8), 16) / 255
  end
  return self
end

function Color:toHex()
  local r = math.floor(self.r * 255)
  local g = math.floor(self.g * 255)
  local b = math.floor(self.b * 255)
  local a = math.floor(self.a * 255)
  return string.format("%02X%02X%02X%02X", r, g, b, a)
end

function Color:lerp(other, t)
  return Color.new(
    self.r + (other.r - self.r) * t,
    self.g + (other.g - self.g) * t,
    self.b + (other.b - self.b) * t,
    self.a + (other.a - self.a) * t
  )
end

function Color:multiply(other)
  self.r = self.r * other.r
  self.g = self.g * other.g
  self.b = self.b * other.b
  self.a = self.a * other.a
  return self
end

function Color:add(other)
  self.r = math.min(1, self.r + other.r)
  self.g = math.min(1, self.g + other.g)
  self.b = math.min(1, self.b + other.b)
  self.a = math.min(1, self.a + other.a)
  return self
end

function Color:clone()
  return Color.new(self.r, self.g, self.b, self.a)
end

math_module.Color = Color

-- 插值函数
function math_module.lerp(a, b, t)
  return a + (b - a) * t
end


-- Binary search for timeline frames
-- frames: array of frame data (0-indexed)
-- value: time value to search for
-- step: number of values per frame
-- Returns the index of the frame just before or at the given time
function math_module.binarySearch(frames, value, step)
    local low = 1
    local high = #frames - step + 1 -- Start of last frame
    
    while low <= high do
        local mid = math.floor((low + high) / 2)
        -- Align to step
        mid = math.floor((mid - 1) / step) * step + 1
        
        if frames[mid] <= value then
            low = mid + step
        else
            high = mid - step
        end
    end
    
    return high
end

function math_module.clamp(value, min, max)
  return math.max(min, math.min(max, value))

end

function math_module.wrap(value, min, max)
  local range = max - min
  return min + ((value - min) % range + range) % range
end

function math_module.angleDifference(a1, a2)
  local diff = a2 - a1
  if diff > math.pi then
    diff = diff - 2 * math.pi
  elseif diff < -math.pi then
    diff = diff + 2 * math.pi
  end
  return diff
end

function math_module.angleLerp(a1, a2, t)
  local diff = math_module.angleDifference(a1, a2)
  return a1 + diff * t
end

function math_module.bezier(t, p0, p1, p2, p3)
  local u = 1 - t
  local tt = t * t
  local uu = u * u
  local uuu = uu * u
  local ttt = tt * t
  
  if p3 then
    -- 三次贝塞尔
    return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3
  elseif p2 then
    -- 二次贝塞尔
    return uu * p0 + 2 * u * t * p1 + tt * p2
  else
    -- 线性
    return u * p0 + t * p1
  end
end

-- 曲线计算
function math_module.curve(t, cx1, cy1, cx2, cy2)
  local u = 1 - t
  local tt = t * t
  local uu = u * u
  local uuu = uu * u
  local ttt = tt * t
  
  -- 三次贝塞尔曲线
  local x = uuu * 0 + 3 * uu * t * cx1 + 3 * u * tt * cx2 + ttt * 1
  local y = uuu * 0 + 3 * uu * t * cy1 + 3 * u * tt * cy2 + ttt * 1
  
  return x, y
end

-- 初始化数学库
function math_module.init()
  -- 设置随机数种子
  math.randomseed(os.time())
  
  -- 扩展数学函数
  local originalMath = math
  
  -- 度转弧度
  if not originalMath.rad then
    originalMath.rad = function(deg)
      return deg * math.pi / 180
    end
  end
  
  -- 弧度转度
  if not originalMath.deg then
    originalMath.deg = function(rad)
      return rad * 180 / math.pi
    end
  end
  
  print("Spine Math module initialized")
end

-- 工具函数
function math_module.isPowerOfTwo(n)
  return n > 0 and bit.band(n, n - 1) == 0
end

function math_module.nextPowerOfTwo(n)
  if n <= 1 then return 1 end
  return 2 ^ math.ceil(math.log(n) / math.log(2))
end

function math_module.sign(n)
  return n > 0 and 1 or (n < 0 and -1 or 0)
end

-- 矩阵运算 (简化版，主要用于2D变换)
local Matrix = {}
Matrix.__index = Matrix

function Matrix.new()
  return setmetatable({
    m = {
      {1, 0, 0},
      {0, 1, 0},
      {0, 0, 1}
    }
  }, Matrix)
end

function Matrix:identity()
  self.m = {
    {1, 0, 0},
    {0, 1, 0},
    {0, 0, 1}
  }
  return self
end

function Matrix:translate(x, y)
  self.m[3][1] = self.m[3][1] + x
  self.m[3][2] = self.m[3][2] + y
  return self
end

function Matrix:rotate(angle)
  local cos = math.cos(angle)
  local sin = math.sin(angle)
  local m = self.m
  
  local a = m[1][1]
  local b = m[1][2]
  local c = m[2][1]
  local d = m[2][2]
  
  m[1][1] = a * cos + b * sin
  m[1][2] = b * cos - a * sin
  m[2][1] = c * cos + d * sin
  m[2][2] = d * cos - c * sin
  
  return self
end

function Matrix:scale(x, y)
  y = y or x
  self.m[1][1] = self.m[1][1] * x
  self.m[1][2] = self.m[1][2] * x
  self.m[2][1] = self.m[2][1] * y
  self.m[2][2] = self.m[2][2] * y
  return self
end

function Matrix:multiply(other)
  local result = Matrix.new()
  local a, b, c = self.m, other.m, result.m
  
  for i = 1, 3 do
    for j = 1, 3 do
      c[i][j] = 0
      for k = 1, 3 do
        c[i][j] = c[i][j] + a[i][k] * b[k][j]
      end
    end
  end
  
  self.m = c
  return self
end

function Matrix:apply(x, y)
  local m = self.m
  return 
    x * m[1][1] + y * m[1][2] + m[3][1],
    x * m[2][1] + y * m[2][2] + m[3][2]
end

math_module.Matrix = Matrix

return math_module