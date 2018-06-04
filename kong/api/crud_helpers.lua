local cjson         = require "cjson"
local utils         = require "kong.tools.utils"
local responses     = require "kong.tools.responses"
local app_helpers   = require "lapis.application"


local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64
local encode_args   = ngx.encode_args
local tonumber      = tonumber
local ipairs        = ipairs
local next          = next
local type          = type


local function post_process_row(row, post_process)
  return type(post_process) == "function" and post_process(row) or row
end


local _M = {}

--- Will look up a value in the dao.
-- Either by `id` field or by the field named by 'alternate_field'. If the value
-- is NOT a uuid, then by the 'alternate_field'. If it is a uuid then it will
-- first try the `id` field, if that doesn't yield anything it will try again
-- with the 'alternate_field'.
-- @param dao the specific dao to search
-- @param filter filter table to use, tries will add to this table
-- @param value the value to look up
-- @param alternate_field the field to use if it is not a uuid, or not found in `id`
function _M.find_by_id_or_field(dao, filter, value, alternate_field)
  filter = filter or {}
  local is_uuid = utils.is_valid_uuid(value)
  filter[is_uuid and "id" or alternate_field] = value

  local rows, err = dao:find_all(filter)
  if err then
    return nil, err
  end

  if is_uuid and not next(rows) and alternate_field then
    -- it's a uuid, but yielded no results, so retry with the alternate field
    filter.id = nil
    filter[alternate_field] = value
    rows, err = dao:find_all(filter)
    if err then
      return nil, err
    end
  end
  return rows
end

function _M.find_api_by_name_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.apis, {},
                                           self.params.api_name_or_id, "name")

  if err then
    return helpers.yield_error(err)
  end
  self.params.api_name_or_id = nil

  -- We know name and id are unique for APIs, hence if we have a row, it must be the only one
  self.api = rows[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_plugin_by_filter(self, dao_factory, filter, helpers)
  local rows, err = dao_factory.plugins:find_all(filter)
  if err then
    return helpers.yield_error(err)
  end

  -- We know the id is unique, so if we have a row, it must be the only one
  self.plugin = rows[1]
  if not self.plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_consumer_by_username_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.consumers, {},
                                           self.params.username_or_id, "username")

  if err then
    return helpers.yield_error(err)
  end
  self.params.username_or_id = nil

  -- We know username and id are unique, so if we have a row, it must be the only one
  self.consumer = rows[1]
  if not self.consumer then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_upstream_by_name_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.upstreams, {},
                                           self.params.upstream_name_or_id, "name")

  if err then
    return helpers.yield_error(err)
  end
  self.params.upstream_name_or_id = nil

  -- We know name and id are unique, so if we have a row, it must be the only one
  self.upstream = rows[1]
  if not self.upstream then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

-- this function will return the exact target if specified by `id`, or just
-- 'any target entry' if specified by target (= 'hostname:port')
function _M.find_target_by_target_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.targets, {},
                                           self.params.target_or_id, "target")

  if err then
    return helpers.yield_error(err)
  end
  self.params.target_or_id = nil

  -- if looked up by `target` property we can have multiple targets here, but
  -- anyone will do as they all have the same 'target' field, so just pick
  -- the first
  self.target = rows[1]
  if not self.target then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.paginated_set(self, dao_collection, post_process)
  local size   = self.params.size   and tonumber(self.params.size) or 100
  local offset = self.params.offset and decode_base64(self.params.offset)

  self.params.size   = nil
  self.params.offset = nil

  local filter_keys = next(self.params) and self.params

  local rows, err, offset = dao_collection:find_page(filter_keys, offset, size)
  if err then
    return app_helpers.yield_error(err)
  end

  local total_count, err = dao_collection:count(filter_keys)
  if err then
    return app_helpers.yield_error(err)
  end

  local next_url
  if offset then
    offset = encode_base64(offset)
    next_url = self:build_url(self.req.parsed_url.path, {
      port     = self.req.parsed_url.port,
      query    = encode_args {
        offset = offset,
        size   = size
      }
    })
  end

  local data = setmetatable(rows, cjson.empty_array_mt)

  if type(post_process) == "function" then
    for i, row in ipairs(rows) do
      data[i] = post_process(row)
    end
  end

  return responses.send_HTTP_OK {
    data     = data,
    total    = total_count,
    offset   = offset,
    ["next"] = next_url
  }
end

-- Retrieval of an entity.
-- The DAO requires to be given a table containing the full primary key of the entity
function _M.get(primary_keys, dao_collection, post_process)
  local row, err = dao_collection:find(primary_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif row == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(post_process_row(row, post_process))
  end
end

--- Insertion of an entity.
function _M.post(params, dao_collection, post_process)
  local data, err = dao_collection:insert(params)
  if err then
    return app_helpers.yield_error(err)
  else
    return responses.send_HTTP_CREATED(post_process_row(data, post_process))
  end
end

-- specific for when adding consumer, auto add key & add admin group for this consumer 
function _M.post_consumer_enable_key(params, dao_factory, post_process)
  -- insert to consumers table
  local consumer_data, err = dao_factory.consumers:insert(params)
  if err then
    return app_helpers.yield_error(err) 
  end

  local apikeyparams = {
    consumer_id = consumer_data.id,
    -- only when adding consumer , main_key = true
    main_key = true
  }
  -- insert to api_key table
  local apikey_data, err = dao_factory.api_key:insert(apikeyparams)

  -- when insert api_key table fail, retry 3 times
  local retrytime = 0
  while err and retrytime < 3 do
    apikey_data, err = dao_factory.api_key:insert(apikeyparams)
    retrytime = retrytime + 1     
  end

  -- if it still error after retrying 3 times, delete this consumer sync
  if err then
    local ok, err_t = dao_factory.consumers:delete({ id = consumer_data.id })
    if err_t then
      return app_helpers.yield_error(err_t) 
    end

    return app_helpers.yield_error(err)
  end

  -- when adding consumer, not only enable api_key ,
  -- but also add this main key link to default admin service group (insert acls DB table)  
  local admin_acl_params = {
    group = "group_admin",
    key_id = apikey_data.id
  }
  local admin_acl_ok, err= dao_factory.acls:insert(admin_acl_params)

  retrytime = 0 -- set retrytime back to 0
  while err and retrytime < 3 do
    apikey_data, err = dao_factory.acls:insert(admin_acl_params)
    retrytime = retrytime + 1     
  end

  -- if it still error after retrying 3 times, delete this consumer & key sync
  if err then
    local ok, err_t = dao_factory.consumers:delete({ id = consumer_data.id })
    if err_t then
      return app_helpers.yield_error(err_t) 
    end

    ok, err_t = dao_factory.api_key:delete({ id = apikey_data.id })
    if err_t then
      return app_helpers.yield_error(err_t) 
    end

    return app_helpers.yield_error(err)
  end

  -- After adding these three table successfully , add key column into return data
  -- let consumer knows which key(mainkey) they can use
  local return_data = consumer_data
  return_data.key = apikey_data.key

  return responses.send_HTTP_CREATED(post_process_row(return_data, post_process))
end

--- Partial update of an entity.
-- Filter keys must be given to get the row to update.
function _M.patch(params, dao_collection, filter_keys, post_process)
  if not next(params) then
    return responses.send_HTTP_BAD_REQUEST("empty body")
  end
  local updated_entity, err = dao_collection:update(params, filter_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif updated_entity == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(post_process_row(updated_entity, post_process))
  end
end

-- Full update of an entity.
-- First, we check if the entity body has primary keys or not,
-- if it does, we are performing an update, if not, an insert.
function _M.put(params, dao_collection, post_process)
  local new_entity, err

  local model = dao_collection.model_mt(params)
  if not model:has_primary_keys() then
    -- If entity body has no primary key, deal with an insert
    new_entity, err = dao_collection:insert(params)
    if not err then
      return responses.send_HTTP_CREATED(post_process_row(new_entity, post_process))
    end
  else
    -- If entity body has primary key, deal with update
    new_entity, err = dao_collection:update(params, params, {full = true})
    if not err then
      if not new_entity then
        return responses.send_HTTP_NOT_FOUND()
      end

      return responses.send_HTTP_OK(post_process_row(new_entity, post_process))
    end
  end

  if err then
    return app_helpers.yield_error(err)
  end
end

--- Delete an entity.
-- The DAO requires to be given a table containing the full primary key of the entity
function _M.delete(primary_keys, dao_collection)
  local ok, err = dao_collection:delete(primary_keys)
  if not ok then
    if err then
      return app_helpers.yield_error(err)
    end

    return responses.send_HTTP_NOT_FOUND()
  end

  return responses.send_HTTP_NO_CONTENT()
end

-- delete consumer and also delete consumers key
function _M.delete_consumer_remove_key(primary_keys, dao_collection)
  local ok, err = dao_collection.consumers:delete(primary_keys)
  if not ok then
    if err then
      return app_helpers.yield_error(err)
    end

    return responses.send_HTTP_NOT_FOUND()
  end

  local apikey_data, err = _M.find_by_id_or_field(dao_collection.api_key, 
                                      { consumer_id = primary_keys.id }, primary_keys.id, "consumer_id")
  
  -- if this consumer has api_key , also delete consumer's key
  if next(apikey_data) ~= nil then
    for i = 1,#apikey_data do
      local apikey_del_ok, err = dao_collection.api_key:delete({id = apikey_data[i].id})
      local acls_data , err = _M.find_by_id_or_field(dao_collection.acls, 
                                      { key_id = apikey_data[i].id }, apikey_data[i].id, "key_id")

      -- if this api_key exist in acls , also delete related key_id
      if next(acls_data) ~= nil then
        for j = 1,#acls_data do
          local acls_ok,err = dao_collection.acls:delete({id = acls_data[j].id})            
        end       
      end
    end
  end

  return responses.send_HTTP_NO_CONTENT()
end

function _M.find_api_key_by_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.api_key, {},
                                           self.params.id)

  if err then
    return helpers.yield_error(err)
  end
  self.params.id = nil

  self.api_key = rows[1]
  if not self.api_key then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

return _M
