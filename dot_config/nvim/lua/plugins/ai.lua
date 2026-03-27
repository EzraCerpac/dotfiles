return {
  {
    "olimorris/codecompanion.nvim",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "HakonHarnes/img-clip.nvim" },
    },
    opts = {
      adapters = {
        acp = {
          opencode = function()
            return require("codecompanion.adapters").extend("opencode", {
              commands = {
                default = { "opencode", "acp" },
                sonnet_4_5 = {
                  "opencode",
                  "acp",
                  "-m",
                  "github-copilot/claude-sonnet-4.5",
                },
                opus_4_5 = {
                  "opencode",
                  "acp",
                  "-m",
                  "github-copilot/claude-opus-4.5",
                },
                gpt_5_2 = {
                  "opencode",
                  "acp",
                  "-m",
                  "github-copilot/gpt-5.2",
                },
                glm_4_7_free = {
                  "opencode",
                  "acp",
                  "-m",
                  "opencode/glm-4.7-free",
                },
              },
            })
          end,
        },
      },
      strategies = {
        chat = {
          adapter = "opencode",
        },
      },
    },
    config = function(_, opts)
      require("codecompanion").setup(vim.tbl_deep_extend("force", opts, {}))

      vim.keymap.set(
        { "n", "v" },
        "<LocalLeader>a",
        "<cmd>CodeCompanionChat Toggle<cr>",
        { noremap = true, silent = true, desc = "Toggle CodeCompanion chat" }
      )
      vim.keymap.set(
        "v",
        "<LocalLeader>ca",
        "<cmd>CodeCompanionChat Add<cr>",
        { noremap = true, silent = true, desc = "Add selection to chat" }
      )
      vim.cmd([[cab cc CodeCompanion]])
      vim.g.codecompanion_yolo_mode = true

      local progress = require("fidget.progress")
      local handles = {}
      local group = vim.api.nvim_create_augroup("CodeCompanionFidget", {})

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeCompanionRequestStarted",
        callback = function(e)
          handles[e.data.id] = progress.handle.create({
            title = "CodeCompanion",
            message = "Thinking...",
            lsp_client = { name = e.data.adapter.formatted_name },
          })
        end,
      })

      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CodeCompanionRequestFinished",
        callback = function(e)
          local h = handles[e.data.id]
          if h then
            h.message = e.data.status == "success" and "Done" or "Failed"
            h:finish()
            handles[e.data.id] = nil
          end
        end,
      })
    end,
  },
  {
    "piersolenski/wtf.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "ibhagwan/fzf-lua",
    },
    opts = {
      provider = "copilot",
      providers = {
        copilot = {
          model_id = "claude-sonnet-4.5",
        },
      },
    },
    keys = {
      {
        "<localLeader>wd",
        mode = { "n", "x" },
        function()
          require("wtf").diagnose()
        end,
        desc = "Debug diagnostic with AI",
      },
      {
        "<localLeader>wf",
        mode = { "n", "x" },
        function()
          require("wtf").fix()
        end,
        desc = "Fix diagnostic with AI",
      },
      {
        mode = { "n" },
        "<localLeader>ws",
        function()
          require("wtf").search()
        end,
        desc = "Search diagnostic with Google",
      },
      {
        mode = { "n" },
        "<localLeader>wp",
        function()
          require("wtf").pick_provider()
        end,
        desc = "Pick provider",
      },
      {
        mode = { "n" },
        "<localLeader>wh",
        function()
          require("wtf").history()
        end,
        desc = "Populate the quickfix list with previous chat history",
      },
      {
        mode = { "n" },
        "<localLeader>wg",
        function()
          require("wtf").grep_history()
        end,
        desc = "Grep previous chat history with fzf-lua",
      },
    },
  },
  {
    "ThePrimeagen/99",
    event = "VeryLazy",
    dependencies = {
      "ibhagwan/fzf-lua",
    },
    config = function()
      local _99 = require("99")
      local cwd = vim.uv.cwd()
      local basename = vim.fs.basename(cwd)
      _99.setup({
        provider = _99.Providers.OpenCodeProvider,
        tmp_dir = "./tmp",
        auto_add_skills = true,
        logger = {
          level = _99.DEBUG,
          path = "/tmp/" .. basename .. ".99.debug",
          print_on_error = true,
        },
        completion = {
          custom_rules = {
            vim.fn.expand("~/.agents/skills"),
            vim.fn.expand("~/.config/opencode/skills"),
          },
          source = "native",
        },
        md_files = {
          "AGENTS.md",
          "AGENT.md",
          "CLAUDE.md",
        },
      })

      vim.keymap.set("n", "<leader>9f", function()
        _99.fill_in_function()
      end, { desc = "99 fill function" })
      vim.keymap.set("n", "<leader>9s", function()
        _99.search()
      end, { desc = "99 search" })
      vim.keymap.set("n", "<leader>9o", function()
        _99.open()
      end, { desc = "99 open last" })
      vim.keymap.set("v", "<leader>9v", function()
        _99.visual()
      end, { desc = "99 visual replace" })
      vim.keymap.set("n", "<leader>9x", function()
        _99.stop_all_requests()
      end, { desc = "99 stop requests" })
      vim.keymap.set("n", "<leader>9c", function()
        _99.clear_previous_requests()
      end, { desc = "99 clear history" })
      vim.keymap.set("n", "<leader>9l", function()
        _99.view_logs()
      end, { desc = "99 view logs" })
      vim.keymap.set("n", "<leader>9m", function()
        require("99.extensions.fzf_lua").select_model()
      end, { desc = "99 select model" })
      vim.keymap.set("n", "<leader>9p", function()
        require("99.extensions.fzf_lua").select_provider()
      end, { desc = "99 select provider" })
    end,
  },
}
