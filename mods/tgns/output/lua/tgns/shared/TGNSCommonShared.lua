TGNS = TGNS or {}

TGNS.HIGHEST_EVENT_HANDLER_PRIORITY = -20
TGNS.VERY_HIGH_EVENT_HANDLER_PRIORITY = -10
TGNS.NORMAL_EVENT_HANDLER_PRIORITY = 0
TGNS.VERY_LOW_EVENT_HANDLER_PRIORITY = 10
TGNS.LOWEST_EVENT_HANDLER_PRIORITY = 20

TGNS.ENDGAME_TIME_TO_READYROOM = 8

TGNS.MARINE_COLOR_R = 0.302
TGNS.MARINE_COLOR_G = 219.045
TGNS.MARINE_COLOR_B = 255
TGNS.ALIEN_COLOR_R = 255
TGNS.ALIEN_COLOR_G = 201.96
TGNS.ALIEN_COLOR_B = 57.885

TGNS.READYROOM_LOCATION_ID = 1000

TGNS.ShineTextAlignmentMin = 0
TGNS.ShineTextAlignmentCenter = 1
TGNS.ShineTextAlignmentMax = 2

function TGNS.ReplaceClassMethod(className, methodName, method)
	return Shine.ReplaceClassMethod(className, methodName, method)
end

function TGNS.GetTeamRgb(teamNumber)
	local r, g, b
	if teamNumber == kMarineTeamType or teamNumber == kAlienTeamType then
		r = teamNumber == kMarineTeamType and TGNS.MARINE_COLOR_R or TGNS.ALIEN_COLOR_R
		g = teamNumber == kMarineTeamType and TGNS.MARINE_COLOR_G or TGNS.ALIEN_COLOR_G
		b = teamNumber == kMarineTeamType and TGNS.MARINE_COLOR_B or TGNS.ALIEN_COLOR_B
	else
		r = 255
		g = 255
		b = 255
	end
	return {R=r,G=g,B=b}
end

function TGNS.GetRandomizedElements(elements)
	local result = {}
	TGNS.DoFor(elements, function(e) table.insert(result, e) end)
	TGNS.Shuffle(result)
	return result
end

function TGNS.Shuffle(elements)
	table.Shuffle(elements)
end

function TGNS.PrintInfo(message)
	Shared.Message(message)
end

function TGNS.RegisterNetworkMessage(messageName, variables)
	variables = variables or {}
	Shared.RegisterNetworkMessage(messageName, variables)
end

function TGNS.HookNetworkMessage(messageName, callback)
	if Server then
		Server.HookNetworkMessage(messageName, callback)
	elseif Client then
		Client.HookNetworkMessage(messageName, callback)
	end
end

function TGNS.RegisterEventHook(eventName, handler, priority)
	priority = priority or TGNS.NORMAL_EVENT_HANDLER_PRIORITY
	local stackInfo = debug.getinfo(2)
	local whereDidTheRegistrationOriginate = string.format("%s:%s", stackInfo.short_src, stackInfo.linedefined)
	Shine.Hook.Add(eventName, whereDidTheRegistrationOriginate, handler, priority)
end

function TGNS.ExecuteEventHooks(eventName, ...)
	Shine.Hook.Call(eventName, ... )
end

function TGNS.GetSecondsSinceMapLoaded()
	local result = Shared.GetTime()
	return result
end

function TGNS.GetSecondsSinceServerProcessStarted()
	local result = Shared.GetSystemTimeReal()
	return result
end

function TGNS.GetCurrentDateTimeAsGmtString()
	local result = Shared.GetGMTString(false)
	return result
end

function TGNS.GetSecondsSinceEpoch()
	local result = Shared.GetSystemTime()
	return result
end

function TGNS.GetCurrentMapName()
	local result = Shared.GetMapName()
	return result
end

function TGNS.EnhancedLog(message)
	Shine:LogString(message)
	Shared.Message(message)
end

function TGNS.IndexOf(s, part)
	return s:find(part) or -1
end

function TGNS.Contains(s, part)
	return TGNS.IndexOf(s, part) >= 1
end

function TGNS.Replace(original, pattern, replace)
	local result = string.gsub(original, pattern, replace)
	return result
end

function TGNS.HasNonEmptyValue(stringValue)
	local result = stringValue ~= nil and stringValue ~= ""
	return result
end

function TGNS.DoForPairs(t, pairAction)
	if t ~= nil then
		local index = 1
		for key, value in pairs(t) do
			if value ~= nil and pairAction(key, value, index) then break end
			index = index + 1
		end
	end
end

local function DoFor(elements, elementAction, start, stop, step)
	for index = start, stop, step do
		local element = elements[index]
		if element ~= nil then
			if elementAction(element, index) then
				break
			end
		end
	end
end

function TGNS.DoFor(elements, elementAction)
	if elements ~= nil then
		DoFor(elements, elementAction, 1, #elements, 1)
	end
end

function TGNS.DoForReverse(elements, elementAction)
	if elements ~= nil then
		DoFor(elements, elementAction, #elements, 1, -1)
	end
end

function TGNS.ConvertSecondsToMinutes(seconds)
	local result = seconds / 60
	return result
end

function TGNS.ConvertMinutesToSeconds(minutes)
	local result = minutes * 60
	return result
end