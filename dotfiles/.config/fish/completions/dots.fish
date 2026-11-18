if command -sq dots
    MISE_SAFE=1 MISE_NO_ENV=1 MISE_NO_HOOKS=1 MISE_OFFLINE=1 MISE_EXEC_AUTO_INSTALL=0 MISE_AUTO_INSTALL=0 command dots completions fish 2>/dev/null | source
end

complete -c dots -n '__fish_seen_subcommand_from houseatlas' -a 'check apply status' -d 'HouseAtlas maintenance action (binding unavailable)'
