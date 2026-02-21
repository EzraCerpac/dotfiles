return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}

      local function remove_windows_group(spec)
        if type(spec) ~= "table" then
          return
        end

        for i = #spec, 1, -1 do
          local entry = spec[i]
          if type(entry) == "table" then
            if entry[1] == "<leader>w" and entry.group == "windows" then
              table.remove(spec, i)
            else
              remove_windows_group(entry)
            end
          end
        end
      end

      remove_windows_group(opts.spec)
    end,
  },
}
