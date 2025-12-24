return {
  {
    "olimorris/codecompanion.nvim",
    event = "VeryLazy",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
      { "ravitemer/mcphub.nvim" },
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
      require("codecompanion").setup(vim.tbl_deep_extend("force", opts, {
        extensions = {
          mcphub = {
            callback = "mcphub.extensions.codecompanion",
            opts = {
              make_vars = true,
              make_slash_commands = true,
              show_result_in_chat = true,
            },
          },
        },
      }))

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
    "ravitemer/mcphub.nvim",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    build = "npm install -g mcp-hub@latest",
    config = function()
      require("mcphub").setup()
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
}
