local cp, cl, ci = component.proxy, component.list, component.invoke
local md, red, wp = cp(cl("tunnel")()), cp(cl("redstone")()), cp(cl("waypoint")())
--local dmd = cp(cl("modem")()) --модем для статистики

-- радиус поля, не считая центр (например, у поля 11х11 радиус 5)
local radius = 5

local crops = {}
local points = {}
local scan, check = false, false
local hasCrops = false
local side = false
local comps, cind = nil, 1
red.setOutput(1, side and 15 or 0)

local function rotateSides()
  side = not side
  red.setOutput(1, side and 15 or 0)
end

local function findNewCrop()
  for addr in cl("tecrop") do
    if not crops[addr] then
      return addr
    end
  end
  return false
end

local function addNewCrop(x, z)
  local addr = nil
  for i=1,2 do
    addr = findNewCrop()
    if addr then break end
    rotateSides()
  end
  if addr then crops[addr] = {x, z} end
  md.send("next")
end

local function checkCrops()
  if (not comps) or cind > #comps then
    rotateSides()
    comps = {}
    for a,t in cl("tecrop") do table.insert(comps, a) end
    cind = 1
  end
  local addr = comps[cind]
  cind = cind+1
  
  local crop = crops[addr]
  if crop then
    local x, z = crop[1], crop[2]
    if points[x] and points[x][z] ~= nil then return end
    
    local t, tr = pcall(ci, addr, "getID")
    local c, cr = pcall(ci, addr, "getSize")
    if (not t) or (not c) then return end
    
    if cr > 1 or tr == "weed" then
      if not points[x] then points[x] = {} end
      points[x][z] = tr
      
      md.send("point", x, z)
      --dmd.broadcast(128, "point", x, z, tr)
      return
    end
  end
end

function pointPick(x, z)
  --dmd.broadcast(128, "pick", x, z)
  if points[x] and points[x][z] then
    points[x][z] = nil
    if next(points[x]) == nil then points[x] = nil end
  end
end

while true do
  local name, _, _, _, _, msgType, arg1, arg2
  repeat
    name, _, _, _, _, msgType, arg1, arg2 = computer.pullSignal(0.01)
    if name and name == "modem_message" then
      if msgType == "rb-info" then
        md.send("info", radius, wp.getLabel())
        if not hasCrops then
          scan = true
          md.send("scan")
        else
          check = true
          for x,v in pairs(points) do
            for z,n in pairs(v) do
              md.send("point", x, z)
            end
          end
        end
      elseif msgType == "rb-scan" then
        if scan then addNewCrop(arg1, arg2) end
      elseif msgType == "rb-scan-end" then
        scan = false
        check = true
        hasCrops = true
      elseif msgType == "rb-pick" then
        pointPick(arg1, arg2)
      end
    end
  until not name
  if (not scan) and check then
    checkCrops()
  end
end