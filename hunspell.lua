VERSION = "0.1.0"

local micro = import("micro")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local config = import("micro/config")
local util = import("micro/util")
local utf = import("unicode/utf8")

config.RegisterCommonOption("hunspell", "check", "auto")
config.RegisterCommonOption("hunspell", "dict", "")
config.RegisterCommonOption("hunspell", "args", "")

function init()
    config.MakeCommand("addpersonal", addpersonal, config.NoComplete)
    config.MakeCommand("acceptsug", acceptsug, config.NoComplete)
    config.MakeCommand("togglecheck", togglecheck, config.NoComplete)
    config.AddRuntimeFile("hunspell", config.RTHelp, "help/hunspell.md")
end

local filterModes = {
    xml = "-H",
    html = "-H",
    html4 = "-H",
    html5 = "-H",
    tex = "-t",
    groff = "-n",
    man = "-n"
}

local lock = false
local next = nil

function runHunspell(buf, onExit, ...)
    -- "-a" enables Ispell compatibility mode. "-i utf-8" sets encoding.
    local options = {"-a", "-i", "utf-8"}
    
    if filterModes[buf:FileType()] then
        options[#options + 1] = filterModes[buf:FileType()]
    end
    
    -- Hunspell uses -d for dictionaries (e.g., -d en_US)
    if buf.Settings["hunspell.dict"] ~= "" then
        options[#options + 1] = "-d"
        options[#options + 1] = buf.Settings["hunspell.dict"]
    end
    
    for _, argument in ipairs(split(buf.Settings["hunspell.args"], " ")) do
        options[#options + 1] = argument
    end

    local job = shell.JobSpawn("hunspell", options, nil,
            nil, onExit, buf, unpack(arg))
            
    -- Enable terse mode (outputs only misspellings)
    shell.JobSend(job, "!\n")
    for i=0, buf:LinesNum() - 1 do
        local line = util.String(buf:LineBytes(i))
        -- Escape lines starting with special characters
        line = "^" .. line .. "\n"

        shell.JobSend(job, line)
    end
    job.Stdin:Close()
end

function spellcheck(buf)
    local check = buf.Settings["hunspell.check"]
    local readcheck = buf.Type.Readonly
    if (check == "on" or (check == "auto" and filterModes[buf:FileType()])) and (not readcheck) then
        if lock then
            next = buf
        else
            lock = true
            runHunspell(buf, highlight)
        end
    else
        -- If we aren't supposed to spellcheck, clear the messages
        buf:ClearMessages("hunspell")
    end
end

-- Parses the output of Hunspell and returns the list of all misspells.
function parseOutput(out)
    local patterns = {"^# (.-) (%d+)$", "^& (.-) %d+ (%d+): (.+)$"}

    if out:find("command not found") then
        micro.InfoBar():Error(
                "Make sure that Hunspell is installed and available in your PATH")
        return {}
    elseif not (out:find("Ispell Version") or out:find("Hunspell")) then
        -- Something went wrong, we'll show what Hunspell has to say
        micro.InfoBar():Error("Hunspell: " .. out)
        return {}
    end

    local misspells = {}

    local linenumber = 1
    local lines = split(out, "\n")
    for _, line in ipairs(lines) do
        if line == "" then
            linenumber = linenumber + 1
        else
            for _, pattern in ipairs(patterns) do
                if string.find(line, pattern) then
                    local word, offset, suggestions = string.match(line, pattern)
                    offset = tonumber(offset)
                    local len = utf.RuneCountInString(word)

                    misspells[#misspells + 1] = {
                        word = word,
                        mstart = buffer.Loc(offset - 1, linenumber - 1),
                        mend = buffer.Loc(offset - 1 + len, linenumber - 1),
                        suggestions = suggestions and split(suggestions, ", ") or {},
                    }
                end
            end
        end
    end

    return misspells
end

function highlight(out, args)
    local buf = args[1]

    buf:ClearMessages("hunspell")

    -- This is a hack that keeps the text shifted two columns to the right
    -- even when no gutter messages are shown
    local msg = "This message shouldn't be visible (Hunspell plugin)"
    local bmsg = buffer.NewMessageAtLine("hunspell", msg, 0, buffer.MTError)
    buf:AddMessage(bmsg)

    for _, misspell in ipairs(parseOutput(out)) do
        local msg = nil
        if #(misspell.suggestions) > 0 then
            msg = misspell.word .. " -> " .. table.concat(misspell.suggestions, ", ")
        else
            msg = misspell.word .. " ->X"
        end
        local bmsg = buffer.NewMessage("hunspell", msg, misspell.mstart,
                misspell.mend, buffer.MTWarning)
        buf:AddMessage(bmsg)
    end

    lock = false
    if next ~= nil then
        spellcheck(next)
        next = nil
    end
end

function parseMessages(messages)
    local patterns = {"^(.-) %-> (.+)$", "^(.-) %->X$"}

    if messages == nil then
        return {}
    end

    local misspells = {}

    for i=1, #messages do
        local message = messages[i]
        if message.Owner == "hunspell" then
            for _, pattern in ipairs(patterns) do
                if string.find(message.Msg, pattern) then
                    local word, suggestions = string.match(message.Msg, pattern)

                    misspells[#misspells + 1] = {
                        word = word,
                        mstart = -message.Start,
                        mend = -message.End,
                        suggestions = suggestions and split(suggestions, ", ") or {},
                    }
                end
            end
        end
    end

    return misspells
end

function togglecheck(bp, args)
	local buf = bp.Buf
	local check = buf.Settings["hunspell.check"]
    if check == "on" or (check == "auto" and filterModes[buf:FileType()]) then
		buf.Settings["hunspell.check"] = "off"
	else
		buf.Settings["hunspell.check"] = "on"
	end
	spellcheck(buf)
	if args then
        return
    end
    return true
end

function addpersonal(bp, args)
    local buf = bp.Buf

    local loc = buf:GetActiveCursor().Loc

    for _, misspell in ipairs(parseMessages(buf.Messages)) do
        local wordInBuf = util.String(buf:Substr(misspell.mstart, misspell.mend))
        if loc:GreaterEqual(misspell.mstart) and loc:LessEqual(misspell.mend)
                and wordInBuf == misspell.word then
            local options = {"-a", "-i", "utf-8"}
            if buf.Settings["hunspell.dict"] ~= "" then
                options[#options + 1] = "-d"
                options[#options + 1] = buf.Settings["hunspell.dict"]
            end
            for _, argument in ipairs(split(buf.Settings["hunspell.args"], " ")) do
                options[#options + 1] = argument
            end

            local job = shell.JobSpawn("hunspell", options, nil, nil, function ()
                spellcheck(buf)
            end)
            
            -- '*' adds word to personal dictionary, '#' saves the dictionary
            shell.JobSend(job, "*" .. misspell.word .. "\n#\n")
            job.Stdin:Close()

            if args then
                return
            end
            return true
        end
    end

    if args then
        return
    end
    return false
end

function acceptsug(bp, args)
    local buf = bp.Buf
    local n = nil
    if args and #args > 0 then
        n = tonumber(args[1])
    end

    local loc = buf:GetActiveCursor().Loc

    for _, misspell in ipairs(parseMessages(buf.Messages)) do
        local wordInBuf = util.String(buf:Substr(misspell.mstart, misspell.mend))
        if loc:GreaterEqual(misspell.mstart) and loc:LessEqual(misspell.mend)
                and wordInBuf == misspell.word then
            if misspell.suggestions[n] then
                -- If n is in the range we'll accept n-th suggestion
                buf:GetActiveCursor():GotoLoc(misspell.mend)
                buf:Replace(misspell.mstart, misspell.mend, misspell.suggestions[n])

                spellcheck(buf)
                if args then
                    return
                end
                return true
            elseif #(misspell.suggestions) > 0 then
                -- If n is 0 indicating acceptsug was called with no arguments
                -- we will cycle through the suggestions autocomplete-like
                buf:GetActiveCursor():GotoLoc(misspell.mend)
                buf:Remove(misspell.mstart, misspell.mend)
                buf:Autocomplete(function ()
                    return misspell.suggestions, misspell.suggestions
                end)

                spellcheck(buf)
                if args then
                    return
                end
                return true
            end
        end
    end

    if args then
        return
    end
    return false
end

function split(str, pat)
    local t = {}
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end
        last_end = e+1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

-- We need to spellcheck every time, the buffer is modified. Sadly there's
-- no such thing as onBufferModified()

function onBufferOpen(buf)
    spellcheck(buf)
end

-- The following callbacks are undocumented

function onRune(bp)
    spellcheck(bp.Buf)
end

function onCycleAutocompleteBack(bp)
    spellcheck(bp.Buf)
end

-- The following were copied from help keybindings

-- function onCursorUp(bp)
-- end

-- function onCursorDown(bp)
-- end

-- function onCursorPageUp(bp)
-- end

-- function onCursorPageDown(bp)
-- end

-- function onCursorLeft(bp)
-- end

-- function onCursorRight(bp)
-- end

-- function onCursorStart(bp)
-- end

-- function onCursorEnd(bp)
-- end

-- function onSelectToStart(bp)
-- end

-- function onSelectToEnd(bp)
-- end

-- function onSelectUp(bp)
-- end

-- function onSelectDown(bp)
-- end

-- function onSelectLeft(bp)
-- end

-- function onSelectRight(bp)
-- end

-- function onSelectToStartOfText(bp)
-- end

-- function onSelectToStartOfTextToggle(bp)
-- end

-- function onWordRight(bp)
-- end

-- function onWordLeft(bp)
-- end

-- function onSelectWordRight(bp)
-- end

-- function onSelectWordLeft(bp)
-- end

function onMoveLinesUp(bp)
    spellcheck(bp.Buf)
end

function onMoveLinesDown(bp)
    spellcheck(bp.Buf)
end

function onDeleteWordRight(bp)
    spellcheck(bp.Buf)
end

function onDeleteWordLeft(bp)
    spellcheck(bp.Buf)
end

-- function onSelectLine(bp)
-- end

-- function onSelectToStartOfLine(bp)
-- end

-- function onSelectToEndOfLine(bp)
-- end

function onInsertNewline(bp)
    spellcheck(bp.Buf)
end

function onInsertSpace(bp)
    spellcheck(bp.Buf)
end

function onBackspace(bp)
    spellcheck(bp.Buf)
end

function onDelete(bp)
    spellcheck(bp.Buf)
end

-- function onCenter(bp)
-- end

function onInsertTab(bp)
    spellcheck(bp.Buf)
end

-- function onSave(bp)
-- end

-- function onSaveAll(bp)
-- end

-- function onSaveAs(bp)
-- end

-- function onFind(bp)
-- end

-- function onFindLiteral(bp)
-- end

-- function onFindNext(bp)
-- end

-- function onFindPrevious(bp)
-- end

function onUndo(bp)
    spellcheck(bp.Buf)
end

function onRedo(bp)
    spellcheck(bp.Buf)
end

-- function onCopy(bp)
-- end

-- function onCopyLine(bp)
-- end

function onCut(bp)
    spellcheck(bp.Buf)
end

function onCutLine(bp)
    spellcheck(bp.Buf)
end

function onDuplicateLine(bp)
    spellcheck(bp.Buf)
end

function onDeleteLine(bp)
    spellcheck(bp.Buf)
end

function onIndentSelection(bp)
    spellcheck(bp.Buf)
end

function onOutdentSelection(bp)
    spellcheck(bp.Buf)
end

function onOutdentLine(bp)
    spellcheck(bp.Buf)
end

function onIndentLine(bp)
    spellcheck(bp.Buf)
end

function onPaste(bp)
    spellcheck(bp.Buf)
end

-- function onSelectAll(bp)
-- end

-- function onOpenFile(bp)
-- end

-- function onStart(bp)
-- end

-- function onEnd(bp)
-- end

-- function onPageUp(bp)
-- end

-- function onPageDown(bp)
-- end

-- function onSelectPageUp(bp)
-- end

-- function onSelectPageDown(bp)
-- end

-- function onHalfPageUp(bp)
-- end

-- function onHalfPageDown(bp)
-- end

-- function onStartOfLine(bp)
-- end

-- function onEndOfLine(bp)
-- end

-- function onStartOfText(bp)
-- end

-- function onStartOfTextToggle(bp)
-- end

-- function onParagraphPrevious(bp)
-- end

-- function onParagraphNext(bp)
-- end

-- function onToggleHelp(bp)
-- end

-- function onToggleDiffGutter(bp)
-- end

-- function onToggleRuler(bp)
-- end

-- function onJumpLine(bp)
-- end

-- function onClearStatus(bp)
-- end

-- function onShellMode(bp)
-- end

-- function onCommandMode(bp)
-- end

-- function onQuit(bp)
-- end

-- function onQuitAll(bp)
-- end

-- function onAddTab(bp)
-- end

-- function onPreviousTab(bp)
-- end

-- function onNextTab(bp)
-- end

-- function onNextSplit(bp)
-- end

-- function onUnsplit(bp)
-- end

-- function onVSplit(bp)
-- end

-- function onHSplit(bp)
-- end

-- function onPreviousSplit(bp)
-- end

-- function onToggleMacro(bp)
-- end

function onPlayMacro(bp)
    spellcheck(bp.Buf)
end

-- function onSuspend(bp) -- Unix only
-- end

-- function onScrollUp(bp)
-- end

-- function onScrollDown(bp)
-- end

-- function onSpawnMultiCursor(bp)
-- end

-- function onSpawnMultiCursorUp(bp)
-- end

-- function onSpawnMultiCursorDown(bp)
-- end

-- function onSpawnMultiCursorSelect(bp)
-- end

-- function onRemoveMultiCursor(bp)
-- end

-- function onRemoveAllMultiCursors(bp)
-- end

-- function onSkipMultiCursor(bp)
-- end

-- function onNone(bp)
-- end

-- function onJumpToMatchingBrace(bp)
-- end

function onAutocomplete(bp)
    spellcheck(bp.Buf)
end
