function fish_user_key_bindings
    # Initialize fzf key bindings first (they may add their own maps)
    fzf --fish | source

    # Remove any existing Alt-e (Meta-e) bindings in both vi default (normal) and insert modes
    bind -M default --erase \ee
    bind -M insert  --erase \ee

    # Bind Ctrl-e (\ce) to edit the current command buffer in both normal and insert modes
    bind -M default \ce edit_command_buffer
    bind -M insert  \ce edit_command_buffer
end
