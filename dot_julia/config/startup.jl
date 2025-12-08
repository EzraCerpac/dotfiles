global_env = joinpath(DEPOT_PATH[1], "environments", "v$(VERSION.major).$(VERSION.minor)")
if isdir(global_env)
    push!(LOAD_PATH, global_env)  # append instead of prepend
end

using Pkg
atreplinit() do repl
    try
        @eval using OhMyREPL
    catch e
        @warn "Error initializing OhMyRepl in startup.jl" exception = (e, catch_backtrace())
    end
end

try
    using Revise
catch e
    @warn "Error initializing Revise in startup.jl" exception = (e, catch_backtrace())
end

try
    using BenchmarkTools
catch e
    @warn "Error initializing BenchmarkTools in startup.jl" exception = (e, catch_backtrace())
end

atreplinit() do repl
    InteractiveUtils.define_editor("zed") do cmd, path, line, column
        `$cmd $path:$line:$column`
    end
end

ENV["PLUTO_USER_JS"] = expanduser("~/.julia/config/pluto_user.js")

