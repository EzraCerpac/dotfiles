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
        http = {
          copilot = function()
            return require("codecompanion.adapters").extend("copilot", {
              schema = {
                model = {
                  default = "gpt-5.4-mini",
                },
                ["reasoning.effort"] = {
                  mapping = "parameters",
                  type = "string",
                  default = "medium",
                },
                max_tokens = {
                  enabled = function()
                    return false
                  end,
                },
                n = {
                  enabled = function()
                    return false
                  end,
                },
                top_p = {
                  enabled = function()
                    return false
                  end,
                },
              },
            })
          end,
        },
        acp = {
          codex = function()
            return require("codecompanion.adapters").extend("codex", {
              commands = {
                default = {
                  "codex-acp",
                  "-c",
                  'model="gpt-5.5"',
                  "-c",
                  'model_reasoning_effort="low"',
                  "-c",
                  'approval_policy="never"',
                  "-c",
                  'sandbox_mode="danger-full-access"',
                },
              },
              defaults = {
                auth_method = "chatgpt",
                session_config_options = {
                  model = "gpt-5.5",
                },
              },
            })
          end,
          copilot_acp = "copilot_acp",
        },
      },
      interactions = {
        chat = {
          adapter = {
            name = "codex",
            model = "gpt-5.5",
          },
          tools = {
            ["create_file"] = { opts = { require_approval_before = false } },
            ["delete_file"] = { opts = { allowed_in_yolo_mode = true, require_approval_before = false } },
            ["grep_search"] = { opts = { require_approval_before = false } },
            ["read_file"] = { opts = { require_approval_before = false } },
            ["run_command"] = {
              opts = {
                allowed_in_yolo_mode = true,
                require_approval_before = false,
                require_cmd_approval = false,
              },
            },
            ["insert_edit_into_file"] = {
              opts = {
                require_approval_before = { buffer = false, file = false },
                require_confirmation_after = false,
              },
            },
            opts = {
              default_tools = { "agent" },
              notify_on_approval = false,
            },
          },
        },
        inline = {
          adapter = "copilot",
        },
        shared = {
          editor_context = {
            ["buffer"] = {
              opts = {
                default_params = "all",
              },
            },
          },
        },
      },
      display = {
        chat = {
          window = {
            layout = "vertical",
            position = "right",
            width = 0.45,
          },
          show_context = true,
        },
      },
    },
    config = function(_, opts)
      require("codecompanion").setup(vim.tbl_deep_extend("force", opts, {}))

      local function chat_with_current_buffer()
        require("codecompanion").chat({
          auto_submit = false,
          params = { adapter = "codex" },
          user_prompt = "#{buffer}{all}\n\n",
        })
      end

      vim.keymap.set(
        { "n", "v" },
        "<LocalLeader>a",
        chat_with_current_buffer,
        { noremap = true, silent = true, desc = "CodeCompanion edit buffer" }
      )
      vim.keymap.set(
        "v",
        "<LocalLeader>ca",
        "<cmd>CodeCompanionChat Add<cr>",
        { noremap = true, silent = true, desc = "Add selection to chat" }
      )
      vim.cmd([[cab cc CodeCompanion adapter=copilot #{buffer}]])
      vim.cmd([[cab ccc CodeCompanionChat adapter=codex]])
      vim.cmd([[cab ccp CodeCompanionChat adapter=copilot_acp]])
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
}
