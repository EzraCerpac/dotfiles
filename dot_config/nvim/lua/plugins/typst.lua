local uv = vim.uv or vim.loop

local function ensure_pdf(source, pdf)
  if uv.fs_stat(pdf) then
    return true
  end

  local job, err = vim.system({ "typst", "compile", source, pdf }, { text = true })
  if not job then
    vim.notify("Typst compile failed: " .. (err or "command not found"), vim.log.levels.ERROR)
    return false
  end

  local result = job:wait()
  if result.code ~= 0 then
    local stderr = result.stderr or ""
    local stdout = result.stdout or ""
    local msg = stderr ~= "" and stderr or stdout
    vim.notify("Typst compile failed: " .. msg, vim.log.levels.ERROR)
    return false
  end

  return true
end

local function open_pdf(bufnr)
  local source = vim.api.nvim_buf_get_name(bufnr)
  if source == "" or not source:match("%.typ$") then
    vim.notify("No Typst buffer detected.", vim.log.levels.WARN)
    return
  end

  local pdf = source:gsub("%.typ$", ".pdf")
  if ensure_pdf(source, pdf) then
    vim.system({ "open", pdf }, { detach = true })
  end
end

return {
  {
    "chomosuke/typst-preview.nvim",
    ft = "typst",
    version = "1.*",
    opts = {},
    config = function(_, opts)
      require("typst-preview").setup(opts)

      vim.api.nvim_create_user_command("TypstOpenPdf", function()
        open_pdf(vim.api.nvim_get_current_buf())
      end, { desc = "Compile and open the Typst PDF for the current buffer" })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "typst",
        callback = function(event)
          vim.keymap.set("n", "<localleader>to", function()
            open_pdf(event.buf)
          end, { buffer = event.buf, desc = "[T]ypst [O]pen PDF" })
        end,
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts = opts or {}
      opts.servers = opts.servers or {}

      local tinymist_opts = opts.servers.tinymist or {}
      local prev_on_attach = tinymist_opts.on_attach

      tinymist_opts.on_attach = function(client, bufnr)
        if prev_on_attach then
          prev_on_attach(client, bufnr)
        end

        local function exec_cmd(args)
          client:exec_cmd(args, { bufnr = bufnr })
        end

        vim.keymap.set("n", "<localleader>tp", function()
          exec_cmd({
            title = "pin",
            command = "tinymist.pinMain",
            arguments = { vim.api.nvim_buf_get_name(bufnr) },
          })
        end, { buffer = bufnr, desc = "[T]inymist [P]in", noremap = true })

        vim.keymap.set("n", "<localleader>tu", function()
          exec_cmd({
            title = "unpin",
            command = "tinymist.pinMain",
            arguments = { vim.v.null },
          })
        end, { buffer = bufnr, desc = "[T]inymist [U]npin", noremap = true })

        vim.lsp.config["tinymist"] = {
          cmd = { "tinymist" },
          filetypes = { "typst" },
          settings = {
            formatterMode = "typstyle",
            exportPdf = "onSave",
            outputPath = "$dir/$name",
            -- semanticTokens = "disable",
            lint = {
              enabled = true,
              when = "onSave",
            },
          },
        }
      end

      opts.servers.tinymist = tinymist_opts
    end,
  },
}
