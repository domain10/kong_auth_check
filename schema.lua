local typedefs = require "kong.db.schema.typedefs"

return {
  name = "my-auth-check",
  fields = {
    { consumer=typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { ucenter_url = typedefs.url({ required = false }) },
          -- { ignore_addr = { type = "string",required = false, }, },
    }, }, },
  },
}
