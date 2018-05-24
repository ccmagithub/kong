local crud = require "kong.api.crud_helpers"

return {
  ["/api_key/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.api_key)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.api_key)
    end
  },

  ["/api_key/:id"] = {
    before = function(self, dao_factory, helpers)
      self.params.id = ngx.unescape_uri(self.params.id)
      crud.find_api_key_by_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.api_key)
    end,

    PATCH = function(self, dao_factory)
      -- prevent update consumer_id
      self.params.consumer_id = nil
      require 'pl.pretty'.dump(self.params)
      crud.patch(self.params, dao_factory.api_key, self.api_key)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.api_key, dao_factory.api_key)
    end
  },

}
