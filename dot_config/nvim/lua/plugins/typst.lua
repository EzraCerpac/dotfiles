local uv = vim.uv or vim.loop

local function typst_root(path_of_main_file)
  local root = os.getenv("TYPST_ROOT")
  if root then
    return root
  end

  local project_root
  if path_of_main_file and path_of_main_file ~= "" then
    local start_dir = vim.fs.dirname(path_of_main_file)
    if start_dir then
      local git_root = vim.fs.find(".git", {
        path = start_dir,
        upward = true,
        type = "directory",
      })[1]
      if git_root then
        project_root = vim.fs.dirname(git_root)
      end
    end
  end

  if project_root then
    return project_root
  end

  return vim.fn.fnamemodify(path_of_main_file, ":p:h")
end

local function run_typst_template(name, params, on_complete)
  require("lazy").load({ plugins = { "overseer.nvim" } })
  local ok, overseer = pcall(require, "overseer")
  if not ok then
    return
  end
  overseer.run_template({ name = name, params = params }, function(task)
    if not task then
      return
    end
    if on_complete then
      task:subscribe("on_complete", function(_, status)
        if status == "SUCCESS" then
          on_complete(params)
        end
      end)
    end
    overseer.open({ enter = false })
  end)
end

local function open_pdf_for_file(file)
  if not file or file == "" or not file:match("%.typ$") then
    return
  end
  local pdf = file:gsub("%.typ$", ".pdf")
  if uv.fs_stat(pdf) then
    vim.system({ "open", pdf }, { detach = true })
  end
end

return {
  {
    "chomosuke/typst-preview.nvim",
    ft = "typst",
    version = "1.*",
    opts = {
      -- This function will be called to determine the root of the typst project
      get_root = typst_root,
    },
    config = function(_, opts)
      require("typst-preview").setup(opts)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "typst",
        callback = function(event)
          vim.keymap.set("n", "\\tc", function()
            local file = vim.api.nvim_buf_get_name(event.buf)
            run_typst_template("Typst: compile pdf", { file = file })
          end, { buffer = event.buf, desc = "[T]ypst [C]ompile (overseer)" })

          vim.keymap.set("n", "\\to", function()
            local file = vim.api.nvim_buf_get_name(event.buf)
            run_typst_template("Typst: compile pdf", { file = file }, function()
              open_pdf_for_file(file)
            end)
          end, { buffer = event.buf, desc = "[T]ypst [O]pen PDF (overseer)" })

          vim.keymap.set("n", "<localleader>tw", function()
            local file = vim.api.nvim_buf_get_name(event.buf)
            run_typst_template("Typst: watch", { file = file })
          end, { buffer = event.buf, desc = "[T]ypst [W]atch (overseer)" })

          vim.keymap.set("n", "<localleader>tt", "<CMD>TypstPreview<CR>", {
            buffer = event.buf,
            desc = "[T]ypst [T]oggle Preview",
          })
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
          vim.cmd("LspTinymistPinMain")
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
