local ok, starship = pcall(require, "starship")

if ok and type(starship) == "table" and type(starship.setup) == "function" then
    starship:setup()
end
