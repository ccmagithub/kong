local singletons = require "kong.singletons"

local function check_unique(group, acl)
  -- If dao required to make this work in integration tests when adding fixtures
  if singletons.dao and acl.key_id and group then
    local res, err = singletons.dao.acls:find_all {key_id = acl.key_id, group = group}
    if not err and #res > 0 then
      return false, "ACL group already exist for this key"
    elseif not err then
      return true
    end
  end
end

local SCHEMA = {
  primary_key = {"id"},
  table = "acls",
  cache_key = { "key_id" },
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    key_id = { type = "id", required = true, foreign = "api_key:id" },
    group = { type = "string", required = true, func = check_unique }
  },
}

return {acls = SCHEMA}
