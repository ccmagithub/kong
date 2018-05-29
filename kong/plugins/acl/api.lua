local crud = require "kong.api.crud_helpers"

return {
  ["/api_key/:key_id/acls/"] = {
    -- get total group counts & data belongs to this key_id
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.acls)
    end,
    
    -- assign groupname into acls with key_id (add row data to acls)
    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.acls)
    end
  },

  ["/api_key/:key_id/acls/:group"] = {
    -- convert params and get data in acls table
    before = function(self, dao_factory, helpers)
      self.params.key_id = ngx.unescape_uri(self.params.key_id)
      self.params.group = ngx.unescape_uri(self.params.group)
      local row, err = crud.find_by_id_or_field(dao_factory.acls, 
            { key_id = self.params.key_id , group = self.params.group },
            self.params.key_id , "key_id")

      if err then
        return helpers.yield_error(err)
      elseif #row == 0 then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.acl = row[1]
    end,

    -- get acls data by params:key_id & params:group
    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.acl)
    end,

    -- delete acls data by params:key_id & params:group
    DELETE = function(self, dao_factory)
        crud.delete(self.acl, dao_factory.acls)
    end
  },

  ["/acls"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.acls)
    end
  }
}
