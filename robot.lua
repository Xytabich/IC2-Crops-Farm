local cp, cl = component.proxy, component.list
local rb, nav, md, tb, inv = cp(cl("robot")()), cp(cl("navigation")()), cp(cl("tunnel")()), cp(cl("tractor_beam")()), cp(cl("inventory_controller")())

local stacks = 2
local path, -- путь движения робота, формат [action1, repeatCount1, ... actionN, repeatCountN]
  points, -- двумерный массив с точками сбора, points[x][z] = true
  pos,
  stepOffset,
  index, round,
  scan, wait, tool, stackSize = {}, {}, {0, 0}, {1, 0}, 0, 0, false, false, true, 0

local function rforw(side, offset)
  table.insert(path, side and 3 or 2) table.insert(path, 1)
  table.insert(path, 1) table.insert(path, offset)
end

local function buildPath(radius, pointName) -- строит полный путь прохода поля
  local points = nav.findWaypoints(radius*8)
  local point = nil
  for i=1,#points do
    if points[i].label == pointName then
      point = points[i]
      break
    end
  end
  if not point then error("Point not found") end
  local px, pz = point.position[1], point.position[3]
  pos[1] = px
  pos[2] = pz

  local targetFacing, offset1, offset2, side
  if px < -radius or px > radius then
    targetFacing = (px > radius) and 5 or 4
  else
    targetFacing = (pz > radius) and 3 or 2
  end
  while nav.getFacing() ~= targetFacing do rb.turn(true) end
  
  if px < -radius or px > radius then
    offset1 = math.abs(px < 0 and (px + radius) or (px - radius))
    side = px < 0
    offset2 = math.abs(pz < 0 and (pz + radius) or (pz - radius))
  else
    offset1 = math.abs(pz < 0 and (pz + radius) or (pz - radius))
    side = pz < 0
    offset2 = math.abs(px < 0 and (px + radius) or (px - radius))
  end
  table.insert(path, 1) table.insert(path, offset1)
  rforw(side, offset2)
  side = not side
  table.insert(path, side and 3 or 2) table.insert(path, 1)
  side = not side
  
  for i=-radius,radius do
    if i > -radius then
      rforw(side, 1)
      table.insert(path, side and 3 or 2) table.insert(path, 1)
    end
    if i == 0 then
      table.insert(path, 1) table.insert(path, radius-1)
      rforw(side, 1)
      side = not side
      rforw(side, 2)
      rforw(side, 1)
      side = not side
      rforw(side, radius-1)
      side = not side
    else
      table.insert(path, 1) table.insert(path, radius + radius)
      side = not side
    end
  end
  side = not side
  rforw(side, radius + radius)
  rforw(side, radius + radius)
  rforw(side, offset2)
  side = not side
  rforw(side, offset1)
  table.insert(path, 3) table.insert(path, 2)
end

local function facing() -- смещение при шаге вперед
  local f = nav.getFacing()
  stepOffset[1] = (f == 3) and 1 or ((f == 2) and -1 or 0)
  stepOffset[2] = (f == 5) and 1 or ((f == 4) and -1 or 0)
end

local function selectPoles()
  if not tool then
    if stackSize > 2 then
      return
    end
    while not inv.equip() do end
  end
  
  for i=2, stacks do
    item = inv.getStackInInternalSlot(i)
    if item and item.name == "IC2:blockCrop" then
      rb.select(i)
      if not rb.transferTo(1) then break end
    end
  end
  
  rb.select(1)
  stackSize = rb.count()
  
  tool = false
  while not inv.equip() do end
end

local function selectTool()
  if tool then return end
  
  tool = true
  rb.select(1)
  while not inv.equip() do end
end

local function placePole()
  selectPoles()
  local a, b
  repeat
    a, b = rb.use(0)
    if a then stackSize = stackSize-1 end
  until (not a) or b == "block_activated"
end

local function pick(x, z) -- сбор и притягивание предмета
  if points[x] and points[x][z] then
    selectTool()
    if rb.swing(0) then
      tb.suck()
      placePole()
    end
    points[x][z] = nil
    if next(points[x]) == nil then points[x] = nil end
    md.send("rb-pick", x, z)
  end
end

local function place(x, z)
  local a, b = rb.detect(0)
  if a then return end
  placePole()
  
  wait = true
  md.send("rb-scan", x, z)
end

local function action(n)
  if n == 1 then -- движение вперед и проверка точки
    pos[1] = pos[1] + stepOffset[1]
    pos[2] = pos[2] + stepOffset[2]
    while not rb.move(3) do end
    if scan then place(pos[1], pos[2])
    else pick(pos[1], pos[2]) end
  elseif n == 2 or n == 3 then -- поворот влево/вправо
    while not rb.turn(n == 3) do end
    facing()
  end
end

local function dropItems()
  for i=1,rb.inventorySize() do
    if rb.count(i) > 0 then
      rb.select(i)
      while not rb.drop(0) do end -- куда кидает результаты сбора
    end
  end
end

local function prepare()
  for i=1, stacks do
    rb.select(i)
    while rb.space() > 0 do
      inv.suckFromSlot(1, 1, rb.space())
    end
  end
  if rb.durability() < 0.5 then
    rb.select(1)
    while not rb.turn(true) do end
    while not rb.turn(true) do end
    
    while not inv.equip() do end
    if inv.dropIntoSlot(3, 1) then
      local item
      repeat
        item = inv.getStackInSlot(3, 1)
      until (not item) or item.charge >= item.maxCharge*0.95
      while not inv.suckFromSlot(3, 1) do end
    end
    while not inv.equip() do end
    
    while not rb.turn(true) do end
    while not rb.turn(true) do end
  end
end

md.send("rb-info")
facing()
while true do
  local name, _, _, _, _, msgType, arg1, arg2
  repeat
    name, _, _, _, _, msgType, arg1, arg2 = computer.pullSignal(0.01)
    if name and name == "modem_message" then
      if msgType == "info" then -- информация о области работы, во время прохода изменять нельзя
        buildPath(arg1, arg2)
      elseif msgType == "point" then -- добавляет точку сбора
        if not points[arg1] then points[arg1] = {} end
        points[arg1][arg2] = true
        
        if index < 1 and #path > 0 then
          prepare()
          index = 1
          round = 1
          scan = false
        end
      elseif msgType == "scan" then
        if index < 1 and #path > 0 then
          prepare()
          index = 1
          round = 1
          scan = true
        end
      elseif msgType == "next" then
        wait = false
      end
    end
  until not name
  
  if index == 1 then
    wait = computer.energy()/computer.maxEnergy() < 0.95
  end
  
  if index >= 1 and (not wait) then
    local a, c = path[index], path[index+1]
    if round <= c then
      action(a)
      round = round+1
    else
      index = index+2
      round = 1
      if index >= #path then
        index = 0
        if scan then
          selectTool()
          md.send("rb-scan-end")
        else
          selectTool()
          dropItems()
        end
      end
    end
  end
end