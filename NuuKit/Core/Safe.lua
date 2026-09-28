local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- Values the client hides from addons (the "secret values" of 12.0). They
-- carry the right type, but comparing, concatenating, or printing one raises
-- "attempt to compare a secret value", and pcall around the call that
-- produced it does not help: the error comes later, where it is used. So a
-- value read out of the client is checked here before anything touches it.
function Kit.IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, hidden = pcall(issecretvalue, value)
    return ok and hidden == true
end

-- Calls a client function and hands back its first value, or nil when the
-- function is missing, the call fails, or the value is secret, so callers
-- can compare what they get.
function Kit.Read(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok or Kit.IsSecret(value) then return nil end
    return value
end
