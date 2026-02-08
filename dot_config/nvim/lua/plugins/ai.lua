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
  {
    "ThePrimeagen/99",
    config = function()
      local _99 = require("99")

      -- For logging that is to a file if you wish to trace through requests
      -- for reporting bugs, i would not rely on this, but instead the provided
      -- logging mechanisms within 99.  This is for more debugging purposes
      local cwd = vim.uv.cwd()
      local basename = vim.fs.basename(cwd)
      _99.setup({
        logger = {
          level = _99.DEBUG,
          path = "/tmp/" .. basename .. ".99.debug",
          print_on_error = true,
        },

        --- A new feature that is centered around tags
        completion = {
          --- Defaults to .cursor/rules
          -- I am going to disable these until i understand the
          -- problem better.  Inside of cursor rules there is also
          -- application rules, which means i need to apply these
          -- differently
          -- cursor_rules = "<custom path to cursor rules>"

          --- A list of folders where you have your own SKILL.md
          --- Expected format:
          --- /path/to/dir/<skill_name>/SKILL.md
          ---
          --- Example:
          --- Input Path:
          --- "scratch/custom_rules/"
          ---
          --- Output Rules:
          --- {path = "scratch/custom_rules/vim/SKILL.md", name = "vim"},
          --- ... the other rules in that dir ...
          ---
          custom_rules = {
            "scratch/custom_rules/",
          },

          --- What autocomplete do you use.  We currently only
          --- support cmp right now
          source = "cmp",
        },

        --- md_files is a list of files to look for and auto add based on the location
        --- of the originating request.  That means if you are at /foo/bar/baz.lua
        --- the system will automagically look for:
        --- /foo/bar/AGENT.md
        --- /foo/AGENT.md
        --- assuming that /foo is project root (based on cwd)
        md_files = {
          "AGENT.md",
          "CLAUDE.md",
        },
      })

      vim.keymap.set("n", "<leader>9f", function()
        _99.fill_in_function()
      end)
      -- take extra note that i have visual selection only in v mode
      -- technically whatever your last visual selection is, will be used
      -- so i have this set to visual mode so i dont screw up and use an
      -- old visual selection
      --
      -- likely ill add a mode check and assert on required visual mode
      -- so just prepare for it now
      vim.keymap.set("v", "<leader>9v", function()
        _99.visual()
      end)

      --- if you have a request you dont want to make any changes, just cancel it
      vim.keymap.set("v", "<leader>9q", function()
        _99.stop_all_requests()
      end)
    end,
  },
}
