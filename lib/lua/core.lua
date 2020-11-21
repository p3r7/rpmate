--
-- CORE HELPERS
--


function unrequire(name)
  package.loaded[name] = nil
  _G[name] = nil
end

function len(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end
