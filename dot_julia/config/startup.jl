global_env = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)")
if isdir(global_env)
    push!(LOAD_PATH, global_env)  # append instead of prepend
end

using Pkg
function maybe_using(pkg::Symbol; repl_only::Bool = false)
    repl_only && !isinteractive() && return
    Base.find_package(string(pkg)) === nothing && return

    try
        Core.eval(Main, Expr(:toplevel, Expr(:using, Expr(:., pkg))))
    catch e
        @warn "Error initializing $(pkg) in startup.jl" exception = (e, catch_backtrace())
    end
end

maybe_using(:Revise)
maybe_using(:Cthulhu; repl_only = true)
maybe_using(:AbbreviatedStackTraces; repl_only = true)
maybe_using(:BenchmarkTools; repl_only = true)

atreplinit() do repl
    maybe_using(:OhMyREPL; repl_only = true)
end

atreplinit() do repl
    InteractiveUtils.define_editor("zed") do cmd, path, line, column
        `$cmd $path:$line:$column`
    end
end

ENV["PLUTO_USER_JS"] = expanduser("~/.julia/config/pluto_user.js")
