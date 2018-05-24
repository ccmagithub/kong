local utils = require "kong.tools.utils"

local function check_consumer_id(value, key_t)
  local consumer_id = type(key_t.consumer_id) == "string" and utils.strip(key_t.consumer_id) or ""

  if consumer_id == "" then
    return false, "At least a 'consumer_id' must be specified"
  end

  return true
end

return {
  table = "api_key",
  primary_key = {"id"},
  cache_key = { "id", "key", "consumer_id" },
  fields = {
    id = {type = "id", dao_insert_value = true, required = true},
    key = {type = "id", unique = true, dao_insert_value = true},
    consumer_id = {type = "id", immutable = true, required = true, func = check_consumer_id},
    created_at = {type = "timestamp", immutable = true, dao_insert_value = true},
    expired_time = {type = "timestamp", dao_insert_value = true},
  },
}