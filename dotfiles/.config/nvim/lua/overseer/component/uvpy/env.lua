return {
  desc = "Set helpful Python env vars",
  params = {
    unbuffered = { type = "boolean", default = true, desc = "Set PYTHONUNBUFFERED=1" },
    vars = { type = "list", subtype = { type = "string" }, default = {}, desc = "Extra env as KEY=VALUE" },
  },
  constructor = function(params)
    return {
      on_init = function(self, task)
        task.env = task.env or {}
        if params.unbuffered then
          task.env.PYTHONUNBUFFERED = "1"
        end
        for _, kv in ipairs(params.vars or {}) do
          local eq = string.find(kv, "=")
          if eq then
            local k = string.sub(kv, 1, eq - 1)
            local v = string.sub(kv, eq + 1)
            if #k > 0 then task.env[k] = v end
          elseif #kv > 0 then
            task.env[kv] = "1"
          end
        end
      end,
    }
  end,
}
