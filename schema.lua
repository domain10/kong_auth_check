local typedefs = require "kong.db.schema.typedefs"

local string_record = {
  type = "record",
  fields = {
    { ucenter = {type = "string"} },
  },
}


return {
  name = "my-auth-check",
  fields = {
    { consumer=typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
            { host = typedefs.host({ required = false }), },
            { port = typedefs.port({ required = false }), },
            { jump_upstream = string_record },
            { del_cache = { type = "boolean", default = false }, },
-- { ucenter_url = typedefs.url({ required = false }) },
-- { frontend_dir = {type = "string"} },
        }, 
	},},
  }
}
