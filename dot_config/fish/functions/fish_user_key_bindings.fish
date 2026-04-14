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
