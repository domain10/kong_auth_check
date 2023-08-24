local typedefs = require "kong.db.schema.typedefs"

local string_record = {
  type = "record",
  fields = {
    { ucenter = {type = "string"} },
    { publish = {type = "string"} },
    { order = {type = "string"} },
    { remote = {type = "string"} },
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
            { not_check = { type = "boolean", default = false }, },
            { del_cache = { type = "boolean", default = false }, },
            { strip_path = { type = "string" }, },
-- { ucenter_url = typedefs.url({ required = false }) },
-- { frontend_dir = {type = "string"} },
        }, 
	},},
  }
}
