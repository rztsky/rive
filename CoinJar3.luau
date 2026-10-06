-- CoinJar v1.2 / Rive Node script
-- Screen: 440 x 956. Templates: coin1..coin5, 60 x 60.
-- Requires ViewModel1 with Boolean coinFlip1 on ALL five templates.
-- Each template's default state machine: idle -> start when true,
-- start -> idle when false. Disable Exit Time on both transitions.
-- Set the Node position to (0,0), scale 100%, rotation 0.
-- Assign five ARTBOARD inputs in the inspector, not placed scene copies.
-- Optional ScreenVM Number properties bound Source -> Target to matching
-- inputs: count=20, launchId=0, gravityX=0, gravityY=1, resetId=0.
-- Increment launchId to replace the scene with a new wave of count coins.
-- Increment resetId to clear. count is TOTAL, not per template (limit 80).
-- Set Screen clipping ON. Remove the five manually placed Screen copies.
-- Templates stay intact. Independently created VMs are owned by each coin.
-- Tilt inputs are normalized gravity in screen coordinates: +X right, +Y down.
-- Native iOS Core Motion forwarding is NOT included in this script.
-- After the last emission + tiltDelay seconds, smoothly enable tilt gravity.
-- Circular collision radius stays fixed even during the visual flip animation.
-- New waves intentionally replace old coins; changing count alone does not fire.

type Body = {
    art: Artboard<Data.ViewModel1>,
    vm: Data.ViewModel1,
    x: number, y: number, vx: number, vy: number,
    angle: number, omega: number, entered: boolean, rising: boolean,
}

type CoinJar = {
    coin1: Input<Artboard<Data.ViewModel1>>,
    coin2: Input<Artboard<Data.ViewModel1>>,
    coin3: Input<Artboard<Data.ViewModel1>>,
    coin4: Input<Artboard<Data.ViewModel1>>,
    coin5: Input<Artboard<Data.ViewModel1>>,
    count: Input<number>, launchId: Input<number>, resetId: Input<number>,
    gravityX: Input<number>, gravityY: Input<number>,
    boardWidth: Input<number>, boardHeight: Input<number>,
    radius: Input<number>, gravity: Input<number>,
    minLaunchSpeed: Input<number>, maxLaunchSpeed: Input<number>,
    sidewaysSpeed: Input<number>, spawnInterval: Input<number>,
    bounce: Input<number>, friction: Input<number>, tiltDelay: Input<number>,
    bodies: {Body}, pending: number, spawnClock: number,
    accumulator: number, lastLaunch: number, lastReset: number,
    sinceLastSpawn: number, gx: number, gy: number,
}

local STEP = 1 / 120
local LIMIT = 80

local function clamp(v: number, lo: number, hi: number): number
    return math.max(lo, math.min(hi, v))
end

local function radius(self: CoinJar): number
    return clamp(self.radius, 4, math.min(self.boardWidth, self.boardHeight) * 0.2)
end

local function clear(self: CoinJar)
    self.bodies = {}
    self.pending = 0
    self.spawnClock = 0
    self.accumulator = 0
    self.sinceLastSpawn = 0
    self.gx = 0
    self.gy = 1
end

local function spawn(self: CoinJar)
    local templates = {self.coin1, self.coin2, self.coin3, self.coin4, self.coin5}
    local template = templates[math.random(1, 5)]
    local vm = Data.ViewModel1.new()
    vm.coinFlip1.value = true
    local art = template:instance(vm)
    art.frameOrigin = true
    art:advance(0)
    local r = radius(self)
    local low = clamp(self.minLaunchSpeed, 300, 1800)
    local high = clamp(self.maxLaunchSpeed, low, 1800)
    local body: Body = {
        art = art, vm = vm,
        x = r + math.random() * math.max(0, self.boardWidth - 2 * r),
        y = self.boardHeight + r + 2,
        vx = (math.random() * 2 - 1) * clamp(self.sidewaysSpeed, 0, 600),
        vy = -(low + math.random() * (high - low)),
        angle = math.random() * math.pi * 2,
        omega = (math.random() * 2 - 1) * 4,
        entered = false, rising = true,
    }
    table.insert(self.bodies, body)
    self.sinceLastSpawn = 0
end

-- Wall normal points INTO the container. Equal-mass solid disks, I=mr^2/2.
local function wallImpulse(self: CoinJar, b: Body, nx: number, ny: number, r: number)
    local vn = b.vx * nx + b.vy * ny
    if vn >= 0 then return end
    local restitution = 0
    if vn < -70 then restitution = clamp(self.bounce, 0, 0.9) end
    local j = -(1 + restitution) * vn
    b.vx = b.vx + j * nx
    b.vy = b.vy + j * ny
    local tx, ty = -ny, nx
    local slip = b.vx * tx + b.vy * ty - b.omega * r
    local maxFriction = clamp(self.friction, 0, 1) * j
    local jt = clamp(-slip / 3, -maxFriction, maxFriction)
    b.vx = b.vx + jt * tx
    b.vy = b.vy + jt * ty
    b.omega = b.omega - 2 * jt / r
end

local function walls(self: CoinJar, b: Body, r: number)
    if b.x < r then
        b.x = r
        wallImpulse(self, b, 1, 0, r)
    elseif b.x > self.boardWidth - r then
        b.x = self.boardWidth - r
        wallImpulse(self, b, -1, 0, r)
    end
    if b.y < r then
        b.y = r
        wallImpulse(self, b, 0, 1, r)
    elseif b.entered and b.y > self.boardHeight - r then
        b.y = self.boardHeight - r
        wallImpulse(self, b, 0, -1, r)
    end
end

local function collide(self: CoinJar, a: Body, b: Body, r: number)
    if not a.entered or not b.entered then return end
    local dx, dy = b.x - a.x, b.y - a.y
    local d2 = dx * dx + dy * dy
    if d2 >= 4 * r * r then return end
    local distance = math.sqrt(d2)
    local nx, ny = 1, 0
    if distance > 0.0001 then nx, ny = dx / distance, dy / distance end
    local correction = math.max(0, 2 * r - distance - 0.01) * 0.48
    a.x, a.y = a.x - nx * correction, a.y - ny * correction
    b.x, b.y = b.x + nx * correction, b.y + ny * correction
    local vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
    if vn >= 0 then return end
    local restitution = 0
    if vn < -70 then restitution = clamp(self.bounce, 0, 0.9) end
    local j = -(1 + restitution) * vn / 2
    a.vx, a.vy = a.vx - j * nx, a.vy - j * ny
    b.vx, b.vy = b.vx + j * nx, b.vy + j * ny
    local tx, ty = -ny, nx
    local slip = (b.vx - a.vx) * tx + (b.vy - a.vy) * ty - r * (a.omega + b.omega)
    local maxFriction = clamp(self.friction, 0, 1) * j
    local jt = clamp(-slip / 6, -maxFriction, maxFriction)
    a.vx, a.vy = a.vx - jt * tx, a.vy - jt * ty
    b.vx, b.vy = b.vx + jt * tx, b.vy + jt * ty
    a.omega = a.omega - 2 * jt / r
    b.omega = b.omega - 2 * jt / r
end

local function fall(b: Body)
    if b.rising and b.vy >= 0 then
        b.rising = false
        b.vm.coinFlip1.value = false
    end
end

local function step(self: CoinJar)
    local r = radius(self)
    self.sinceLastSpawn = self.sinceLastSpawn + STEP
    if self.pending > 0 then
        self.spawnClock = self.spawnClock - STEP
        if self.spawnClock <= 0 then
            spawn(self)
            self.pending = self.pending - 1
            self.spawnClock = clamp(self.spawnInterval, 0.04, 2) * (0.65 + math.random() * 0.7)
        end
    end

    local tx: number = 0
    local ty: number = 1
    if self.pending == 0 and self.sinceLastSpawn >= math.max(0, self.tiltDelay) then
        tx = clamp(self.gravityX, -1, 1)
        ty = clamp(self.gravityY, -1, 1)
        local length: number = math.sqrt(tx * tx + ty * ty)
        if length > 1 then
            tx = tx / length
            ty = ty / length
        end
    end
    local blend = 1 - math.exp(-STEP * 8)
    self.gx = self.gx + (tx - self.gx) * blend
    self.gy = self.gy + (ty - self.gy) * blend
    local g = clamp(self.gravity, 100, 3000)
    local drag = math.exp(-0.08 * STEP)
    for _, b in ipairs(self.bodies) do
        b.vx = (b.vx + self.gx * g * STEP) * drag
        b.vy = (b.vy + self.gy * g * STEP) * drag
        b.x, b.y = b.x + b.vx * STEP, b.y + b.vy * STEP
        if not b.entered and b.y <= self.boardHeight - r then b.entered = true end
        fall(b) -- Latch at the apex, even if a collision immediately reverses vy.
        walls(self, b, r)
    end
    for _ = 1, 6 do
        for i = 1, #self.bodies - 1 do
            for j = i + 1, #self.bodies do
                collide(self, self.bodies[i], self.bodies[j], r)
            end
        end
        for _, b in ipairs(self.bodies) do walls(self, b, r) end
    end
    for _, b in ipairs(self.bodies) do
        fall(b) -- A ceiling/coin impact can begin descent before the free-flight apex.
        b.omega = clamp(b.omega * math.exp(-0.25 * STEP), -35, 35)
        b.angle = (b.angle + b.omega * STEP) % (2 * math.pi)
    end
end

local function init(self: CoinJar): boolean
    clear(self)
    self.lastLaunch = 0
    self.lastReset = self.resetId
    return true
end

local function advance(self: CoinJar, seconds: number): boolean
    if self.resetId ~= self.lastReset then
        clear(self)
        self.lastReset = self.resetId
        self.lastLaunch = self.launchId
    end
    if self.launchId ~= self.lastLaunch then
        clear(self)
        self.lastLaunch = self.launchId
        self.pending = math.floor(clamp(self.count, 0, LIMIT))
        print('CoinJar: launching ' .. tostring(self.pending) .. ' coins')
    end
    if self.boardWidth < 20 or self.boardHeight < 20 then return true end
    self.accumulator = math.min(self.accumulator + math.max(0, seconds), STEP * 12)
    local elapsed = 0
    while self.accumulator >= STEP do
        step(self)
        self.accumulator = self.accumulator - STEP
        elapsed = elapsed + STEP
    end
    for _, b in ipairs(self.bodies) do b.art:advance(elapsed) end
    return true
end

local function draw(self: CoinJar, renderer: Renderer)
    -- All five source artboards are 60 x 60.
    -- Explicit scalar entries avoid overloaded matrix multiplication and
    -- runtime-version-dependent type inference for artboard width/height.
    local scale: number = radius(self) / 30
    for _, b in ipairs(self.bodies) do
        local c: number = math.cos(b.angle) * scale
        local s: number = math.sin(b.angle) * scale
        local matrix = Mat2D.identity()
        matrix.xx = c
        matrix.xy = s
        matrix.yx = -s
        matrix.yy = c
        matrix.tx = b.x - 30 * c + 30 * s
        matrix.ty = b.y - 30 * s - 30 * c
        renderer:save()
        renderer:transform(matrix)
        b.art:draw(renderer)
        renderer:restore()
    end
end

return function(): Node<CoinJar>
    return {
        coin1 = late(), coin2 = late(), coin3 = late(), coin4 = late(), coin5 = late(),
        count = 20, launchId = 0, resetId = 0,
        gravityX = 0, gravityY = 1,
        boardWidth = 440, boardHeight = 956, radius = 30,
        gravity = 1400, minLaunchSpeed = 1100, maxLaunchSpeed = 1450,
        sidewaysSpeed = 180, spawnInterval = 0.12,
        bounce = 0.45, friction = 0.35, tiltDelay = 4,
        bodies = {}, pending = 0, spawnClock = 0, accumulator = 0,
        lastLaunch = 0, lastReset = 0, sinceLastSpawn = 0, gx = 0, gy = 1,
        init = init, advance = advance, draw = draw,
    }
end
