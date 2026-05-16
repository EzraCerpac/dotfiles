function fish_user_key_bindings
    # Initialize fzf key bindings first (they may add their own maps)
    if command -q fzf
        fzf --fish | source
    end

    # Remove any existing Alt-e (Meta-e) bindings in both vi default (normal) and insert modes
    bind -M default --erase \ee
    bind -M insert  --erase \ee

    # Bind Ctrl-e (\ce) to edit the current command buffer in both normal and insert modes
    bind -M default \ce edit_command_buffer
    bind -M insert  \ce edit_command_buffer

    # WezTerm Option/Alt escape sequences in vi insert mode
    bind -M insert \e\[1\;3D backward-word
    bind -M insert \e\[1\;9D backward-word
    bind -M insert \e\[1\;3C forward-word
    bind -M insert \e\[1\;9C forward-word
    bind -M insert \e\x7f backward-kill-word
    bind -M insert \e\b backward-kill-word
    bind -M insert \e\[1\;13D beginning-of-line
    bind -M insert \e\[1\;13C end-of-line
    bind -M insert \e\[1\;13~ backward-kill-line

    # Fish 4 binds Ctrl-V to clipboard paste by default; keep paste on Cmd-V in WezTerm.
    bind -M default \cv begin-selection repaint-mode
    bind -M visual \cv end-selection repaint-mode
    bind -M insert \cv self-insert

    if functions -q _atuin_search
        bind -M default \cr _atuin_search
        bind -M insert \cr _atuin_search
    end

    if functions -q _atuin_ai_question_mark
        bind -M default ? _atuin_ai_question_mark
        bind -M insert ? _atuin_ai_question_mark
    end

    if functions -q tv_smart_autocomplete
        bind -M default \ct tv_smart_autocomplete
        bind -M insert \ct tv_smart_autocomplete
    end
end
