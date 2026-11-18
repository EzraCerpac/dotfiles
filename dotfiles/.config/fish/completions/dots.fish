if command -sq dots
    command dots completions fish 2>/dev/null | source
end

complete -c dots -n '__fish_seen_subcommand_from houseatlas' -a 'check apply status' -d 'HouseAtlas maintenance action (binding unavailable)'
