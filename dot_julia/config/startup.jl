atreplinit() do repl
    InteractiveUtils.define_editor("zed") do cmd, path, line, column
        `$cmd $path:$line:$column`
    end
end# using Revise

ENV["PLUTO_USER_JS"] = expanduser("~/.julia/config/pluto_user.js")

