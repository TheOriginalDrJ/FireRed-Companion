return function(mod)
  local F = require('src.world.game3.Follower')
  if F._pokemonCompanion then return F._pokemonCompanion end
  local P = require('src.core.game3.player')
  local Field = require('src.core.game3.field')
  local Runtime = require('src.core.game3.runtime')
  local Options = require('src.core.game3.options')
  local Pokemon = require('src.core.game3.pokemon')
  local Rows = require('src.ui.game3.option_rows')
  local Message = require('src.ui.game3.message')
  local Bag = require('src.core.game3.bag')
  local Items = require('src.core.game3.items_data')
  local Sprite = require('src.import.pmd.Sprite')
  local function readLua(path) return assert(loadstring(assert(mod:read(path))))() end
  local catalog = readLua('assets/catalog.lua')
  local api = {ready=true, catalog=catalog, problems={}, random=math.random}
  local npc, last, owner, currentSession, renderer, renderId
  local trail = {}
  local delta = {up={0,-1}, down={0,1}, left={-1,0}, right={1,0}}
  local gifts = {13, 14, 4, 18} -- Native FireRed: Potion, Antidote, Poke Ball, Paralyze Heal.

  local function enabled(options)
    local v = options and options.modOptions and options.modOptions.pokemon_companion
    return not (v and v.enabled == false)
  end
  local function lead(s)
    local mon = s and s.party and s.party[1]
    if not mon or Pokemon.isEgg(mon) then return nil end
    return mon
  end
  local function spriteId(mon)
    if not mon then return nil end
    local nat = Pokemon.national(Pokemon.speciesOf(mon))
    if nat == 201 then
      local letter = Pokemon.unownLetter(mon.personality)
      return letter == 26 and 'unown_emark' or letter == 27 and 'unown_qmark'
        or 'unown_'..string.char(97+letter)
    end
    if nat == 386 then return 'deoxys_attack' end -- FireRed form
    return catalog.byDex[nat]
  end
  local function state(s, mon)
    s.modData = s.modData or {}
    local data = s.modData.pokemon_companion
    if type(data) ~= 'table' then data={version=1, mons={}}; s.modData.pokemon_companion=data end
    data.mons = data.mons or {}
    local key = tostring(mon.otId or mon.trainerId or 0)..':'..tostring(mon.otSecretId or 0)..':'
      ..tostring(mon.personality or ('species-'..tostring(mon.species)))
    if not data.mons[key] then data.mons[key]={steps=0, talks=0, gifts=0} end
    return data.mons[key]
  end
  local function busy()
    local Space = package.loaded['src.core.game3.scripting.space']
    return Field.locked or (Runtime.uiBusy and Runtime.uiBusy()) or Message.open
      or (Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning())
  end
  local function makeRenderer(id)
    local meta = readLua('assets/'..id..'.lua')
    local tops = readLua('assets/'..id..'.bounds.lua')
    local image = mod.assets:image('assets/'..id..'.png')
    image:setFilter('nearest','nearest')
    local w,h = image:getDimensions()
    local entry = assert(catalog.entries[id])
    assert(w == meta.frameColumns*meta.frameWidth and h == math.ceil(entry.frames/meta.frameColumns)*meta.frameHeight, 'Invalid companion atlas')
    local r = {image=image, ticks=0, meta=meta, frames={}}
    for i=0,entry.frames-1 do
      r.frames[i]=love.graphics.newQuad(i%meta.frameColumns*meta.frameWidth,
        math.floor(i/meta.frameColumns)*meta.frameHeight,meta.frameWidth,meta.frameHeight,w,h)
    end
    function r:getPoseGeometry(facing)
      local f=Sprite.frame(meta,0,facing,self.ticks)
      return {quad=self.frames[f[1]-1],width=meta.frameWidth,height=meta.frameHeight,
        anchorX=meta.anchorX-f[3],anchorY=meta.anchorY-f[4],
        x=(f[1]-1)%meta.frameColumns*meta.frameWidth,
        y=math.floor((f[1]-1)/meta.frameColumns)*meta.frameHeight,top=tops[f[1]] or 0},false
    end
    function r:getDrawImage() return self.image end
    function r:draw(px,py,cx,cy,facing)
      local g=self:getPoseGeometry(facing)
      local x,y=math.floor(px-cx+8-g.anchorX),math.floor(py-cy+12-g.anchorY)
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(self.image,g.quad,x,y)
      if self.attention then
        -- Pixel bubble remains readable with any font or resolution setting.
        local bx,by=math.floor(px-cx+4),y+g.top-14
        love.graphics.setColor(0.12,0.16,0.22,1); love.graphics.rectangle('fill',bx-1,by-1,10,12)
        love.graphics.setColor(1,1,0.9,1); love.graphics.rectangle('fill',bx,by,8,10)
        love.graphics.rectangle('fill',bx+3,by+10,2,2)
        love.graphics.setColor(0.85,0.12,0.08,1); love.graphics.rectangle('fill',bx+3,by+1,2,5)
        love.graphics.rectangle('fill',bx+3,by+7,2,2); love.graphics.setColor(1,1,1,1)
      end
    end
    return r
  end
  local nativeReset = F.reset
  function F.reset()
    nativeReset(); npc,last,owner,currentSession=nil,nil,nil,nil; trail={}
  end
  function F.current() return npc end
  function F.at(_,x,y) if npc and not npc.hidden and not npc.moving and npc.cellX==x and npc.cellY==y then return npc end end
  function F.setVisible(_,value) if npc then npc.hidden=not value end end
  function F.onMapEntered() F.reset() end
  -- Rebase the entire trail only after an accepted connected-map crossing.
  -- The engine parks the player before the landing tile in the new map's
  -- coordinates; the same translation preserves our in-flight step exactly.
  local Collision = require('src.core.game3.collision')
  local nativeConnection = Collision.tryConnection
  Collision.tryConnection = function(game, fromX, fromY, dir, ...)
    local s = Field.getSession()
    local previous, map = npc, s and s.map
    local x, y = P.cellX, P.cellY
    local result = nativeConnection(game, fromX, fromY, dir, ...)
    if result and npc and npc == previous and s == currentSession
      and s == Field.getSession() and owner == lead(s) and last and last.map == map then
      local dx, dy = P.cellX - x, P.cellY - y
      npc.cellX, npc.cellY = npc.cellX + dx, npc.cellY + dy
      npc.px, npc.py = npc.px + dx * 16, npc.py + dy * 16
      if npc.fromX then npc.fromX = npc.fromX + dx * 16 end
      if npc.fromY then npc.fromY = npc.fromY + dy * 16 end
      local function shift(point)
        point.x, point.y = point.x + dx, point.y + dy
      end
      if npc.goal then shift(npc.goal) end
      for _, point in ipairs(trail) do shift(point) end
      shift(last); last.map = s.map
    end
    return result
  end
  function F.starterInParty() return lead(Field.getSession()) end
  function F.actor()
    if not npc or npc.hidden or not renderer or not P.isVisible() then return nil end
    -- Wait until the player has stepped away after a map change.
    if npc.px==P.px and npc.py==P.py then return nil end
    return {kind='follower',i=-1,x=npc.px,y=npc.py,sortY=npc.py,elevation=npc.elevation,
      facing=npc.facing,walkPhase=npc.moving and 1 or 0,renderer=renderer}
  end
  function F.update(game)
    local s=Field.getSession()
    local mon=lead(s)
    local options=Options.engine(s) or (game and game.options)
    local id=spriteId(mon)
    if not Field.running or not enabled(options) or not id or P.surfing or P.flyRide or P.biking
      or not P.isVisible() then F.reset(); return end
    if id~=renderId then
      local ok,value=pcall(makeRenderer,id)
      if not ok then api.problems[id]=tostring(value); F.reset(); return end
      renderer,renderId=value,id
    end
    if currentSession~=s or owner~=mon or not last or last.map~=s.map
      or math.abs(P.cellX-last.x)+math.abs(P.cellY-last.y)>2 then
      F.reset(); currentSession,owner=s,mon
      npc={cellX=P.cellX,cellY=P.cellY,px=P.px,py=P.py,facing=P.facing,passable=true,moving=false,elevation=P.elevation}
      last={map=s.map,x=P.cellX,y=P.cellY,elevation=P.elevation}
    end
    local data=state(s,mon)
    if last.x~=P.cellX or last.y~=P.cellY then
      trail[#trail+1]={x=last.x,y=last.y,elevation=last.elevation}
      local distance=math.abs(P.cellX-last.x)+math.abs(P.cellY-last.y)
      last={map=s.map,x=P.cellX,y=P.cellY,elevation=P.elevation}
      if distance==1 and not busy() then
        data.steps=(tonumber(data.steps) or 0)+1
        if not data.pending and data.steps>=256 then
          data.steps=0
          if api.random(1,4)==1 then
            data.pending=gifts[api.random(1,#gifts)]
          end
        end
      end
    end
    renderer.attention=data.pending~=nil
    if busy() then return end
    if not npc.moving and #trail>0 then
      local goal=table.remove(trail,1)
      local dx,dy=goal.x-npc.cellX,goal.y-npc.cellY
      if math.abs(dx)+math.abs(dy)>1 then
        -- Ledges/forced jumps: regroup on a visited landing, never cross a wall diagonally.
        npc.cellX,npc.cellY,npc.px,npc.py=goal.x,goal.y,goal.x*16,goal.y*16
        npc.elevation=goal.elevation
      elseif dx~=0 or dy~=0 then
        npc.facing=dx>0 and 'right' or dx<0 and 'left' or dy>0 and 'down' or 'up'
        npc.goal,npc.fromX,npc.fromY,npc.progress=goal,npc.px,npc.py,0
        npc.frames=math.max(4, math.floor((P.stepFrames or 16)/(#trail>1 and 2 or 1)))
        npc.moving=true
      end
    end
    if npc.moving then
      npc.progress=npc.progress+1
      local t=math.min(1,npc.progress/npc.frames)
      npc.px=npc.fromX+(npc.goal.x*16-npc.fromX)*t
      npc.py=npc.fromY+(npc.goal.y*16-npc.fromY)*t
      renderer.ticks=renderer.ticks+1
      if t==1 then npc.cellX,npc.cellY,npc.elevation,npc.moving=npc.goal.x,npc.goal.y,npc.goal.elevation,false end
    else renderer.ticks=0 end
  end
  function F.talk(game)
    local s=Field.getSession(); local mon=lead(s)
    if not npc or npc.hidden or npc.moving or P.moving or busy() or mon~=owner then return false end
    local d=delta[P.facing] or delta.down
    if npc.cellX~=P.cellX+d[1] or npc.cellY~=P.cellY+d[2] then return false end
    local data=state(s,mon)
    local name=Pokemon.displayName(mon)
    local text
    if data.pending then
      local item=data.pending
      if s.bag and Bag.add(s.bag,item,1) then
        data.pending=nil; data.gifts=(data.gifts or 0)+1; renderer.attention=false
        text=name..' found something!\fReceived '..Items.displayName(item)..'!'
      else text=name..' has a gift for you!\nYour Bag is full. Make some room.' end
    else
      data.talks=(data.talks or 0)+1
      local lines={' is happy to walk with you!',' is looking around curiously.',' stays close by your side.',' is ready for more exploring!'}
      if (tonumber(mon.hp) or 1)<=(tonumber(mon.maxHP or mon.maxHp) or 0)/4 then
        text=name..' looks tired. A rest would help.'
      else text=name..lines[(data.talks-1)%#lines+1] end
    end
    npc.facing=({up='down',down='up',left='right',right='left'})[P.facing]
    Message.show(text,{session=s,done=function() Message.close() end})
    return true
  end
  local nativeInteract=Field.interact
  Field.interact=function(game) if F.talk(game) then return true end; return nativeInteract(game) end
  local build=Rows.build
  Rows.build=function(ctx)
    local rows=build(ctx)
    rows[#rows+1]={id='pokemonCompanion.follow',label='POKEMON FOLLOW',
      value=function(c) return enabled(c.options) and 'ENABLE' or 'DISABLE' end,
      step=function(c)
        local value=not enabled(c.options)
        c.options.modOptions=c.options.modOptions or {}
        c.options.modOptions.pokemon_companion={enabled=value}
        if not value then F.reset() end
        return true
      end}
    return rows
  end
  table.insert(Rows.ORDER,'pokemonCompanion.follow')
  api.state,api.spriteId,api.enabled=state,spriteId,enabled
  F._pokemonCompanion=api
  return api
end
