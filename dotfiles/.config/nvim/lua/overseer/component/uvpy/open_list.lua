return {
  desc = "Open Overseer task list when task starts",
  params = {
    enter = { type = "boolean", default = false, desc = "Focus the task list when opening" },
  },
  constructor = function(params)
    return {
      on_start = function()
        -- Defer to ensure UI is ready
        vim.defer_fn(function()
          local ok, overseer = pcall(require, "overseer")
          if ok then overseer.open({ enter = params.enter }) end
        end, 10)
      end,
    }
  end,
}

