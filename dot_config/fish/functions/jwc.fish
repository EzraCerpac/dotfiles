function jwc --description "Switch to a jj workspace by name"
    if test (count $argv) -ne 1
        echo "Usage: jwc NAME" >&2
        return 1
    end

    jw switch $argv[1]
end
