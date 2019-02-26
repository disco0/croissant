local colors    = require "term.colors"
local dump      = require "croissant.utils".dump
local conf      = require "croissant.conf"
local LuaPrompt = require "croissant.luaprompt"
local Lexer     = require "croissant.lexer"

local function doREPL(frame, commands)
    local _, where = commands.where()
    print(colors.reset .. "\n" .. where .. "\n")

    local multiline
    while true do
        local info = debug.getinfo(4)

        local code = LuaPrompt {
            prompt      = "["
                .. colors.green(info.short_src)
                .. ":"
                .. (info.name and colors.blue(info.name) .. ":" or "")
                .. colors.yellow(info.currentline)
                .. "] "
                .. (not multiline and "→ " or ".... "),
            multiline   = multiline,
            history     = {},
            tokenColors = conf.syntaxColors,
            help        = require(conf.help),
            quit        = function() end
        }:ask()

        -- Is it a command ?
        local cmd
        for command, fn in pairs(commands) do
            if command == code then
                cmd = command
                if fn() then
                    return
                end
            end
        end

        if not cmd then
            local fn, err = load("return " .. (multiline or "") .. code, "croissant")
            if not fn then
                fn, err = load((multiline or "") .. code, "croissant")
            end

            if fn then
                multiline = false

                local result = table.pack(xpcall(fn, debug.traceback))

                if result[1] then
                    local dumps = {}
                    for i = 2, result.n do
                        local r = result[i]
                        table.insert(dumps, dump(r))
                    end

                    if #dumps > 0 then
                        print(table.concat(dumps, "\t"))
                    else
                        -- Look for assignments
                        local names = { code:match("^([^{=]+)%s?=[^=]") }
                        if names then
                            dumps = {}
                            for _, n in ipairs(names) do
                                local assignement = load("return " .. n)
                                local assigned = assignement and assignement()
                                if assigned then
                                    table.insert(dumps, dump(assigned))
                                end
                            end

                            print(table.concat(dumps, "\t"))
                        end
                    end
                else
                    print(
                        colors.red
                        .. result[2]
                        .. colors.reset
                    )
                end
            else
                -- Syntax error near <eof>
                if err:match("<eof>") or (err and multiline) then
                    multiline = (multiline or "") .. code .. "\n"
                else
                    multiline = nil
                    print(colors.red .. err .. colors.reset)
                end
            end
        end
    end
end

local function highlight(code)
    local lexer = Lexer()
    local highlighted = ""

    for kind, text, _ in lexer:tokenize(code) do
        highlighted = highlighted
            .. (conf.syntaxColors[kind] or "")
            .. text
            .. colors.reset
    end

    return highlighted
end

return function()
    local frame = 0
    local frameLimit = -2

    local commands
    commands = {
        step = function()
            frameLimit = -1
            return true
        end,

        next = function()
            frameLimit = frame
            return true
        end,

        out = function()
            frameLimit = frame - 1
            return true
        end,

        up = function()
            return true
        end,

        down = function()
            return true
        end,

        where = function()
            local info = debug.getinfo(4)

            local source = ""
            local srcType = info.source:sub(1, 1)
            if srcType == "@" then
                local file, _ = io.open(info.source:sub(2), "r")

                if file then
                    source = file:read("*all")

                    file:close()
                end
            elseif srcType == "=" then
                source = info.source:sub(2)
            else
                source = info.source
            end

            source = highlight(source)

            local lines = {}
            for line in source:gmatch("([^\n]*)\n") do
                table.insert(lines, line)
            end

            local minLine = math.max(1, info.currentline - 4)
            local maxLine = math.min(#lines, info.currentline + 4)

            local w = ""
            for count, line in ipairs(lines) do
                if count >= minLine
                    and count <= maxLine then
                    w = w ..
                        (count == info.currentline
                            and colors.bright(colors.green("    ❱ " .. count .. " │ ")) .. line
                            or  colors.bright(colors.black("      " .. count .. " │ ")) .. line)
                        .. "\n"
                end
            end

            return false, w
        end,

        continue = function()
            debug.sethook()
            return true
        end,
    }

    debug.sethook(function(event, line)
        if event == "line" and frame <= frameLimit then
            doREPL(frame, commands)
        elseif event == "call" then
            frame = frame + 1
        elseif event == "return" then
            frame = frame - 1
        end
    end, "clr")
end
