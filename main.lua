return function(mod)
  return assert(loadstring(assert(mod:read('companion.lua'))))()(mod)
end
