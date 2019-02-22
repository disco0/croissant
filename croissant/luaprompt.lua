local Class  = require "hump.class"
local colors = require "term.colors"
local Prompt = require "sirocco.prompt"
local char   = require "sirocco.char"
local help   = require "croissant.help"
local C, Esc = char.C, char.Esc

local Lexer = require "croissant.lexer"

local LuaPrompt
LuaPrompt = Class {

    __includes = Prompt,

    init = function(self, options)
        options = options or {}

        Prompt.init(self, {
            prompt = options.prompt or "→ ",
            validator = function(code)
                return LuaPrompt.validateLua(self.multiline .. code)
            end,
            required = false
        })

        self.multiline = options.multiline or ""

        -- History
        self.history = options.history or {}
        self.historyIndex = #self.history + 1

        -- Lexing
        self.tokens = {}
        self.lexer = Lexer()

        self.tokenColors = options.colors or {
            constant   = colors.bright .. colors.yellow,
            string     = colors.green,
            comment    = colors.dim .. colors.cyan,
            number     = colors.yellow,
            operator   = colors.yellow,
            keywords   = colors.bright .. colors.magenta,
            identifier = colors.blue,
        }
    end

}

function LuaPrompt:registerKeybinding()
    Prompt.registerKeybinding(self)

    self.keybinding.command_get_next_history = {
        Prompt.escapeCodes.key_down,
        C "n",
        Esc "[B", -- backup
    }

    self.keybinding.command_get_previous_history = {
        Prompt.escapeCodes.key_up,
        C "p",
        Esc "[A", -- backup
    }

    self.keybinding.command_exit = {
        C "c"
    }

    self.keybinding.command_abort = {
        C "g"
    }

    self.keybinding.command_help = {
        C " "
    }
end

function LuaPrompt:selectHistory(dt)
    if #self.history > 0 then
        self.historyIndex = math.min(math.max(1, self.historyIndex + dt), #self.history + 1)
        self.buffer = self.history[self.historyIndex] or ""
        self:setOffset(Prompt.len(self.buffer) + 1)
    end
end

function LuaPrompt:renderDisplayBuffer()
    self.tokens = {}

    self.displayBuffer = ""

    -- Lua code
    local lastIndex
    for kind, text, index in self.lexer:tokenize(self.buffer) do
        self.displayBuffer = self.displayBuffer
            .. (self.tokenColors[kind] or "")
            .. text
            .. colors.reset

        lastIndex = index

        table.insert(self.tokens, {
            kind = kind,
            index = index - Prompt.len(text),
            text = text
        })
    end

    if lastIndex then
        self.displayBuffer = self.displayBuffer
            .. self.buffer:utf8sub(lastIndex)
    end
end

function LuaPrompt:getCurrentToken()
    local currentToken, currentTokenIndex
    for i, token in ipairs(self.tokens) do
        currentToken = token
        currentTokenIndex = i

        if token.index + Prompt.len(token.text) >= self.bufferOffset + 1 then
            break
        end
    end

    return currentToken, currentTokenIndex
end

local keywords = {
    "and", "break", "do", "else", "elseif", "end",
    "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while"
}

function LuaPrompt:command_complete()
    local currentToken, currentTokenIndex = self:getCurrentToken()

    local possibleValues = {}
    local highlightedPossibleValues = {}
    if currentToken.kind == "identifier" then
        -- Search in _G
        for k, _ in pairs(_G) do
            if k:utf8sub(1, #currentToken.text) == currentToken.text then
                table.insert(possibleValues, k)
                table.insert(highlightedPossibleValues,
                    self.tokenColors.identifier .. k .. colors.reset)
            end
        end

        -- Search in keywords
        for _, k in ipairs(keywords) do
            if k:utf8sub(1, #currentToken.text) == currentToken.text then
                table.insert(possibleValues, k)
                table.insert(highlightedPossibleValues,
                    self.tokenColors.keywords .. k .. colors.reset)
            end
        end
    elseif currentToken.kind == "operator"
        and (currentToken.text == "."
            or currentToken.text == ":") then
        -- TODO: this requires an AST
        -- We need to be able to evaluate previous expression to search
        -- possible values in it

        if currentTokenIndex > 1
            and self.tokens[currentTokenIndex - 1].kind == "identifier" then
            local fn = load("return " .. self.tokens[currentTokenIndex - 1].text)
            local parentTable = fn and fn()

            if type(parentTable) == "table" then
                for k, _ in pairs(parentTable) do
                    table.insert(possibleValues, k)
                    table.insert(highlightedPossibleValues,
                        self.tokenColors.identifier .. k .. colors.reset)
                end
            end
        end
    end

    local count = #possibleValues

    if count > 1 then
        self.message = table.concat(highlightedPossibleValues, " ")
    elseif count == 1 then
        local dt = Prompt.len(possibleValues[1]) - Prompt.len(currentToken.text)
        self:insertAtCurrentPosition(possibleValues[1]:utf8sub(#currentToken.text + 1))

        self:setOffset(self.bufferOffset + dt)

        if self.validator then
            local _, message = self.validator(self.buffer)
            self.message = message
        end
    end
end

function LuaPrompt.validateLua(code)
    local fn, err = load("return " .. code, "croissant")
    if not fn then
        fn, err = load(code, "croissant")
    end

    return fn, (err and colors.red .. err .. colors.reset)
end

function LuaPrompt:processedResult()
    return self.buffer
end

function LuaPrompt:command_get_next_history()
    self:selectHistory(1)
end

function LuaPrompt:command_get_previous_history()
    self:selectHistory(-1)
end

function LuaPrompt:command_delete_back()
    Prompt.command_delete_back(self)

    self.message = nil
end

function LuaPrompt:command_kill_line()
    Prompt.command_kill_line(self)

    self.message = nil
end

function LuaPrompt:command_help()
    local currentToken = self:getCurrentToken()

    if currentToken.kind == "identifier" then
        local doc = help[currentToken.text]

        if doc then
            self.message =
                colors.magenta " ? "
                .. colors.blue .. doc.title .. colors.reset
                .. "\n" .. colors.white .. doc.body
                .. colors.reset
                .. "\n"
        end
    end
end

return LuaPrompt
