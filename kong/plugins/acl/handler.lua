local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local crud = require "kong.api.crud_helpers"
local pl_tablex = require "pl.tablex"

local table_concat = table.concat
local set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local ngx_error = ngx.ERR
local ngx_log = ngx.log
local EMPTY = pl_tablex.readonly {}
local BLACK = "BLACK"
local WHITE = "WHITE"


local reverse_cache = setmetatable({}, { __mode = "k" })

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


local ACLHandler = BasePlugin:extend()

ACLHandler.PRIORITY = 950
ACLHandler.VERSION = "0.1.0"

function ACLHandler:new()
  ACLHandler.super.new(self, "acl")
end

local function load_acls_into_memory(key_id)
  local results, err = singletons.dao.acls:find_all {key_id = key_id}
  if err then
    return nil, err
  end
  return results
end

-- check service acl authentication
function ACLHandler:access(conf)
  ACLHandler.super.access(self)
  local headers = ngx_get_headers()
  -- search in headers & querystring
  local apikey = headers["x-api-key"]

  if type(apikey) ~= "string" then
    ngx_log(ngx_error, "[acl plugin] need header [x-api-key] but not supply")
    return responses.send_HTTP_UNAUTHORIZED("Your request is unauthorized")
  end

  -- find primary key id at api_key table by posted apikey value 
  local apikeyrows, err = crud.find_by_id_or_field(singletons.dao.api_key, 
                                        { key = apikey }, apikey, "key")
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  -- not find any data at api_key table by filter this key=apikey
  -- return UNAUTHORIZED
  if next(apikeyrows) == nil then
    return responses.send_HTTP_UNAUTHORIZED("Your request is unauthorized")
  end

  -- Retrieve ACL
  -- use primary key id at api_key table to find this key_id data at acls table
  local cache_key = singletons.dao.acls:cache_key(apikeyrows[1].id)
  local acls, err = singletons.cache:get(cache_key, nil,
                                         load_acls_into_memory, apikeyrows[1].id)

  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if not acls then
    acls = EMPTY
  end
  
  -- check group
  -- build and cache a reverse-lookup table from our plugins 'conf' table
  local reverse = reverse_cache[conf]
  if not reverse then
    local groups = {}
    reverse = {
      groups = groups,
      type = (conf.blacklist or EMPTY)[1] and BLACK or WHITE,
    }

    -- cache by 'conf', the cache has weak keys, so invalidation of the
    -- plugin 'conf' will also remove it from our local cache here
    reverse_cache[conf] = reverse
    
    -- build reverse tables for quick lookup
    if reverse.type == BLACK then
      for i = 1, #(conf.blacklist or EMPTY) do
        local groupname = conf.blacklist[i]
        groups[groupname] = groupname
      end

    else
      for i = 1, #(conf.whitelist or EMPTY) do
        local groupname = conf.whitelist[i]
        groups[groupname] = groupname
      end
    end
    -- now create another cache inside this cache for the consumer acls so we
    -- only ever need to evaluate a white/blacklist once.
    -- The key for this cache will be 'acls' which will be invalidated upon
    -- changes. The weak key will make sure our local entry get's GC'ed.
    -- One exception: a blacklist scenario, and a consumer that does
    -- not have any groups. In that case 'acls == EMPTY' so all those users
    -- will be indexed by that table, which is ok, as their result is the
    -- same as well.
    
    reverse.consumer_access = setmetatable({}, { __mode = "k" })
  end

  -- 'cached_block' is either 'true' if it's to be blocked, or the header
  -- value if it is to be passed
  local cached_block = reverse.consumer_access[acls]
  if not cached_block then
    -- nothing cached, so check our lists and groups
    local block
    if reverse.type == BLACK then
      -- check blacklist
      block = false
      for i = 1, #acls do
        if reverse.groups[acls[i].group] then
          block = true
          break
        end
      end

    else
      -- check whitelist
      block = true
      for i = 1, #acls do
        if reverse.groups[acls[i].group] then
          block = false
          break
        end
      end
    end

    if block then
      cached_block = true

    else
      -- allowed, create the header
      local n = #acls
      local str_acls = new_tab(n, 0)
      for i = 1, n do
        str_acls[i] = acls[i].group
      end
      cached_block = table_concat(str_acls, ", ")
    end

    -- store the result in the cache
    reverse.consumer_access[acls] = cached_block
  end

  if cached_block == true then -- NOTE: we only catch the boolean here!

    return responses.send_HTTP_UNAUTHORIZED("Your request is unauthorized")
  end

  -- check key expired_time that from api_key table of posted key
  local expired_time = apikeyrows[1].expired_time or 0 
  -- os.time() will get milliseconds ,
  -- but our expired_time get seconds ,
  -- so os.time() there has to *1000 to compare with expired_time
  if expired_time < os.time()*1000 then
    return responses.send_HTTP_UNAUTHORIZED("Your request is unauthorized. Key is expired.")
  end

  set_header(constants.HEADERS.CONSUMER_GROUPS, cached_block)
end

return ACLHandler
