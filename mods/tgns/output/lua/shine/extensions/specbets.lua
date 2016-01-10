-- todo format report numbers

local md = TGNSMessageDisplayer.Create("SPECBETS-BETA")
local playerGameBets = {}
local playerBanks = {}
local playerGameTransactions = {}
local karmaTransactions = {}
local MAXIMUM_KARMA_TRANSACTIONS = 10

local Plugin = {}

-- Plugin.HasConfig = true
-- Plugin.ConfigName = "specbets.json"
local MinumumHiveSkillRank = 150

local function clientCanBePartOfBet(client)
	local result = TGNS.ClientIsOnPlayingTeam(client) and not TGNS.GetIsClientVirtual(client)
	if not TGNS.IsProduction() then
		result = true
	end
	return result
end

local function refundBets(client)
	local steamId = TGNS.GetClientSteamId(client)
	playerGameBets[steamId] = playerGameBets[steamId] or {}
	if #playerGameBets[steamId] > 0 then
		local refund = TGNS.GetSumFor(TGNS.Select(playerGameBets[steamId], function(b) return b.amount end))
		playerBanks[steamId] = playerBanks[steamId] + refund
		md:ToPlayerNotifyInfo(TGNS.GetPlayer(client), string.format("%s cleared. %s refunded. You have %s.", Pluralize(#playerGameBets[steamId], "Spectator Bet"), refund, TGNS.RoundPositiveNumberDown(playerBanks[steamId])))
	end
	playerGameBets[steamId] = {}
end

local function showReport(transactions)
	local topEarner = { net = 0, transactionsCount = 0 }
	local topLoser = { net = 0, transactionsCount = 0 }
	local totalSpent = 0
	TGNS.DoForPairs(transactions, function(steamId, gameTransactions)
		gameTransactions = TGNS.Where(gameTransactions, function(t) return t.type ~= 'playcredit' end)
		local count = #gameTransactions
		local amounts = TGNS.Select(gameTransactions, function(t) return t.amount end)
		totalSpent = totalSpent + TGNS.GetSumFor(TGNS.Where(amounts, function(a) return a < 0 end))
		local net = TGNS.GetSumFor(amounts)
		if (net > topEarner.net) or (topEarner.net == 0 and net == 0 and topEarner.transactionsCount <= count) then
			topEarner = { net = net, steamId = steamId, transactionsCount = count }
		end
		if (net < topLoser.net) or (topLoser.net == 0 and net == 0 and topLoser.transactionsCount <= count) then
			topLoser = { net = net, steamId = steamId, transactionsCount = count }
		end
	end)
	local topFormatter = function(top)
		local result
		if top.steamId then
			local topClient = TGNS.GetClientByNs2Id(top.steamId)
			if topClient then
				result = string.format("%s: %s", TGNS.GetClientName(topClient), TGNS.RoundPositiveNumberDown(math.abs(top.net)))
			end
		end
		return result
	end
	local topEarnerDisplay = topEarner.net > 0 and topFormatter(topEarner) or nil
	local topLoserDisplay = topLoser.net < 0 and topFormatter(topLoser) or nil
	local topDisplay = nil
	if topEarnerDisplay then
		topDisplay = string.format("\n  Most Earned:\n    %s", topEarnerDisplay)
	end
	if topLoserDisplay and (topEarner.steamId ~= topLoser.steamId) then
		topDisplay = string.format("%s\n  Most Lost:\n    %s", topDisplay and topDisplay or "", topLoserDisplay)
	end
	if topDisplay then
		topDisplay = string.format("SpecBets BETA (total spent last game: %s):%s", TGNS.RoundPositiveNumberDown(math.abs(totalSpent)), topDisplay)
		Shine.ScreenText.Add(62, {X = 0.2, Y = 0.75, Text = topDisplay, Duration = 60, R = 255, G = 255, B = 255, Alignment = TGNS.ShineTextAlignmentMin, Size = 2, FadeIn = 1, IgnoreFormat = true})
	end
end

local function refreshPlayerBank(steamId)
	if playerBanks[steamId] == nil then
		playerBanks[steamId] = 0
		local url = string.format("%s&i=%s", TGNS.Config.BetsEndpointBaseUrl, steamId)
		TGNS.GetHttpAsync(url, function(betResponseJson)
			local betResponse = json.decode(betResponseJson) or {}
			if betResponse.success then
				playerBanks[steamId] = betResponse.result
			else
				TGNS.DebugPrint(string.format("bets ERROR: Unable to access bets data for NS2ID %s. msg: %s | response: %s | stacktrace: %s", steamId, betResponse.msg, betResponseJson, betResponse.stacktrace))
			end
		end)
	end
end

local function persistTransaction(steamId, amount, killerId, victimId, type)
	local transaction = {steamId=steamId,amount=amount,killerId=killerId,victimId=victimId,type=type}

	playerGameTransactions[steamId] = playerGameTransactions[steamId] or {}
	table.insert(playerGameTransactions[steamId], transaction)

	local url = string.format("%s&m=%s&k=%s&v=%s&t=%s&a=%s", TGNS.Config.BetsEndpointBaseUrl, transaction.steamId, transaction.killerId, transaction.victimId, TGNS.UrlEncode(transaction.type), TGNS.UrlEncode(transaction.amount))
	TGNS.GetHttpAsync(url, function(betResponseJson)
		local betResponse = json.decode(betResponseJson) or {}
		if not betResponse.success then
			TGNS.DebugPrint(string.format("bets ERROR: Unable to save bets data for NS2ID %s. url: %s | msg: %s | response: %s | stacktrace: %s", transaction.steamId, url, betResponse.msg, betResponseJson, betResponse.stacktrace))
		end
	end)

	if not TGNS.IsProduction() then
		showReport(playerGameTransactions)
	end
end

local function getBetClient(predicate, opponentClient)
	local result
	local resultError
	local opponentTeamNumber
	local predicateTeamNumber
	local predicateTeamName
	local opponentName
	local opponentTeamName
	if opponentClient then
		opponentTeamNumber = TGNS.GetClientTeamNumber(opponentClient)
		predicateTeamNumber = TGNS.GetOtherPlayingTeamNumber(opponentTeamNumber)
		predicateTeamName = TGNS.GetTeamName(predicateTeamNumber)
		opponentName = TGNS.GetClientName(opponentClient)
		opponentTeamName = TGNS.GetTeamName(opponentTeamNumber)
	end

	local player = TGNS.GetPlayerMatching(predicate, predicateTeamNumber)
	if player ~= nil then
		local client = TGNS.GetClient(player)
		local clientName = TGNS.GetClientName(client)
		if clientCanBePartOfBet(client) then
			local hiveSkillRank = TGNS.GetClientHiveSkillRank(client)
			if hiveSkillRank >= MinumumHiveSkillRank then
				result = client
			elseif hiveSkillRank == 0 then
				resultError = string.format("%s has an unknown Hive Skill Rank and cannot be included in bets at the moment.", clientName)
			else
				resultError = string.format("%s doesn't have a high enough Hive Skill Rank to be included in bets.", clientName)
			end
		else
			resultError = string.format("%s must be a human player on the Marine or Alien team.", clientName)
		end
	else
		local teamAddendum
		if predicateTeamNumber ~= nil then
			teamAddendum = string.format(" on %s (required since %s is %s)", predicateTeamName, opponentName, opponentTeamName)
		end
		resultError = string.format("'%s' does not uniquely match a player%s.", predicate, teamAddendum and teamAddendum or "")
	end
	return result, resultError
end

local function getKillerAndVictimBetClients(killerPredicate, victimPredicate)
	local killerClient
	local victimClient
	local errorMessage
	killerClient, errorMessage = getBetClient(killerPredicate)
	if killerClient then
		victimClient, errorMessage = getBetClient(victimPredicate, killerClient)
	end
	return killerClient, victimClient, errorMessage
end

local function getClientBetDetails(client)
	local result = {}
	result.playerId = TGNS.GetClientSteamId(client)
	result.teamNumber = TGNS.GetClientTeamNumber(client)

	-- Shared.Message(string.format("getClientBetDetails> for %s", TGNS.GetClientName(client)))
	-- Shared.Message(string.format("getClientBetDetails> result.playerId: %s", result.playerId))
	-- Shared.Message(string.format("getClientBetDetails> result.teamNumber: %s", result.teamNumber))

	return result
end

local function betPlayersAndTeamsMatch(bet1, bet2)
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet1.killer.playerId: %s", bet1.killer.playerId))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet1.killer.teamNumber: %s", bet1.killer.teamNumber))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet1.victim.playerId: %s", bet1.victim.playerId))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet1.victim.teamNumber: %s", bet1.victim.teamNumber))

	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet2.killer.playerId: %s", bet2.killer.playerId))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet2.killer.teamNumber: %s", bet2.killer.teamNumber))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet2.victim.playerId: %s", bet2.victim.playerId))
	-- Shared.Message(string.format("betPlayersAndTeamsMatch> bet2.victim.teamNumber: %s", bet2.victim.teamNumber))

	local betPlayerDetailsMatch = function(d1, d2) return (d1.playerId == d2.playerId) and (d1.teamNumber == d2.teamNumber) end
	local killersMatch = betPlayerDetailsMatch(bet1.killer, bet2.killer)

	-- Shared.Message(string.format("betPlayersAndTeamsMatch> killersMatch: %s", killersMatch))

	local victimsMatch = betPlayerDetailsMatch(bet1.victim, bet2.victim)

	-- Shared.Message(string.format("betPlayersAndTeamsMatch> victimsMatch: %s", victimsMatch))

	local result = killersMatch and victimsMatch

	-- Shared.Message(string.format("betPlayersAndTeamsMatch> result: %s", result))

	return result
end

local function getBet(killerClient, victimClient)
	local result = { killer = getClientBetDetails(killerClient), victim = getClientBetDetails(victimClient) }
	return result
end

local function getInversePlayersBet(bet)
	local originalKiller = bet.killer
	local originalVictim = bet.victim
	local result = bet
	result.killer = originalVictim
	result.victim = originalKiller
	return result
end

local function getAmountWithSkillMultiplier(killerClient, victimClient, amount)
	local killerClientSkill = TGNS.GetClientHiveSkillRank(killerClient) 
	                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	local victimClientSkill = TGNS.GetClientHiveSkillRank(victimClient)
	local multiplier = (victimClientSkill / killerClientSkill) + 1
	local result = amount * multiplier
	return result
end

local function onBetKill(steamId, killerClient, victimClient, amount, shouldPayout)
	local killerName = TGNS.GetClientName(killerClient)
	local victimName = TGNS.GetClientName(victimClient)
	local message, messageDisplayer
	if shouldPayout then
		local multipliedAmount = getAmountWithSkillMultiplier(killerClient, victimClient, amount)
		local roundedMultipliedAmount = TGNS.RoundPositiveNumberDown(multipliedAmount)
		local net = roundedMultipliedAmount - amount
		persistTransaction(steamId, multipliedAmount, TGNS.GetClientSteamId(killerClient), TGNS.GetClientSteamId(victimClient), 'payout')
		playerBanks[steamId] = playerBanks[steamId] + multipliedAmount
		message = string.format("%s killed %s! You won %s on a %s bet (+%s)! You have %s.", killerName, victimName, roundedMultipliedAmount, amount, net, TGNS.RoundPositiveNumberDown(playerBanks[steamId]))
		messageDisplayer = md.ToPlayerNotifyGreen
	else
		message = string.format("%s killed %s. %s for %s to kill %s did not pay out. You have %s.", killerName, victimName, amount, victimName, killerName, TGNS.RoundPositiveNumberDown(playerBanks[steamId]))
		messageDisplayer = md.ToPlayerNotifyRed
	end
	local client = TGNS.GetClientByNs2Id(steamId)
	if client then
		messageDisplayer(md, TGNS.GetPlayer(client), message)
	end
	persistTransaction(steamId, amount * -1, TGNS.GetClientSteamId(killerClient), TGNS.GetClientSteamId(victimClient), 'bet')
end

local function onKill(killerClient, victimClient)
	TGNS.DoForPairs(playerGameBets, function(steamId, bets)
		local client = TGNS.GetClientByNs2Id(steamId)
		if client and TGNS.IsClientSpectator(client) then
			local player = TGNS.GetPlayer(client)
			TGNS.DoForReverse(bets, function(b, index)
				local betAppliesToThisKill
				local betShouldPayout
				local attackerBet = getBet(killerClient, victimClient)
				local victimBet = getBet(victimClient, killerClient)

-- Shared.Message(string.format("onKill> attackerBet.killer.playerId: %s", attackerBet.killer.playerId))
-- Shared.Message(string.format("onKill> attackerBet.killer.teamNumber: %s", attackerBet.killer.teamNumber))
-- Shared.Message(string.format("onKill> attackerBet.victim.playerId: %s", attackerBet.victim.playerId))
-- Shared.Message(string.format("onKill> attackerBet.victim.teamNumber: %s", attackerBet.victim.teamNumber))

-- Shared.Message(string.format("onKill> getInversePlayersBet(b).killer.playerId: %s", getInversePlayersBet(b).killer.playerId))
-- Shared.Message(string.format("onKill> getInversePlayersBet(b).killer.teamNumber: %s", getInversePlayersBet(b).killer.teamNumber))
-- Shared.Message(string.format("onKill> getInversePlayersBet(b).victim.playerId: %s", getInversePlayersBet(b).victim.playerId))
-- Shared.Message(string.format("onKill> getInversePlayersBet(b).victim.teamNumber: %s", getInversePlayersBet(b).victim.teamNumber))

-- Shared.Message(string.format("onKill> victimBet.killer.playerId: %s", victimBet.killer.playerId))
-- Shared.Message(string.format("onKill> victimBet.killer.teamNumber: %s", victimBet.killer.teamNumber))
-- Shared.Message(string.format("onKill> victimBet.victim.playerId: %s", victimBet.victim.playerId))
-- Shared.Message(string.format("onKill> victimBet.victim.teamNumber: %s", victimBet.victim.teamNumber))


-- Shared.Message("onKill> betPlayersAndTeamsMatch(b, attackerBet)...")
				local betMatchesAttackerBet = betPlayersAndTeamsMatch(b, attackerBet)
-- Shared.Message("onKill> betPlayersAndTeamsMatch(b, victimBet)...")
				local betMatchesVictimBet = betPlayersAndTeamsMatch(b, victimBet)

-- Shared.Message(string.format("onKill> ----------------------------------------- betMatchesVictimBet: %s", betMatchesVictimBet))

				if betMatchesAttackerBet then
					betAppliesToThisKill = true
					betShouldPayout = true
				elseif betMatchesVictimBet then
					betAppliesToThisKill = true
				end
				if betAppliesToThisKill then
					onBetKill(steamId, killerClient, victimClient, b.amount, betShouldPayout)
					table.remove(bets, index)
					return true;
				end
			end)
		end
	end)
end

local function placeBet(client, killerPredicate, victimPredicate, amount)
	local player = TGNS.GetPlayer(client)
	local steamId = TGNS.GetClientSteamId(client)
	local killerClient, victimClient, errorMessage = getKillerAndVictimBetClients(killerPredicate, victimPredicate)
	if killerClient and victimClient then
		if TGNS.IsNumberWithNonZeroPositiveValue(amount) then
			amount = TGNS.RoundPositiveNumberDown(amount)
			local bet = getBet(killerClient, victimClient)
			local betOpposite = getBet(victimClient, killerClient)
			playerGameBets[steamId] = playerGameBets[steamId] or {}
			local victimName = TGNS.GetClientName(victimClient)
			local victimTeamName = TGNS.GetClientTeamName(victimClient)
			local killerName = TGNS.GetClientName(killerClient)
			local killerTeamName = TGNS.GetClientTeamName(killerClient)
			if TGNS.Any(playerGameBets[steamId], function(b) return betPlayersAndTeamsMatch(b, betOpposite) end) then
				errorMessage = string.format("Opposite bet already placed: %s (%s) against %s (%s)", victimName, victimTeamName, killerName, killerTeamName)
			else
				if playerBanks[steamId] - amount >= 0 then
					playerBanks[steamId] = playerBanks[steamId] - amount
					local message
					bet.amount = amount
					local existingBet = TGNS.FirstOrNil(playerGameBets[steamId], function(b) return betPlayersAndTeamsMatch(b, bet) end)
					if existingBet then
						local originalAmount = existingBet.amount
						local newAmount = existingBet.amount + amount
						existingBet.amount = newAmount
						message = string.format("Raise! %s to %s that %s (%s) will kill %s (%s).", originalAmount, newAmount, killerName, killerTeamName, victimName, victimTeamName)
					else
						table.insert(playerGameBets[steamId], bet)
						message = string.format("Bet! %s that %s (%s) will kill %s (%s).", amount, killerName, killerTeamName, victimName, victimTeamName)
					end
					message = string.format("%s You have %s.", message, TGNS.RoundPositiveNumberDown(playerBanks[steamId]))
					md:ToPlayerNotifyInfo(player, message)
					if not TGNS.IsProduction() then
						if math.random() < 0.5 then
							local shouldWin = math.random() < 0.5
							if shouldWin then
								-- Shared.Message("placeBet> onKill(killerClient, victimClient)...")
								onKill(killerClient, victimClient)
							else
								-- Shared.Message("placeBet> onKill(victimClient, killerClient)...")
								onKill(victimClient, killerClient)
							end
						else
							md:ToPlayerNotifyYellow(player, "No kill.")
						end
					end
				else
					errorMessage = string.format("Bet (%s) halted. Insufficient bank (%s). Earn more by playing full games!", amount, TGNS.RoundPositiveNumberDown(playerBanks[steamId]))
				end
			end
		else
			errorMessage = string.format("'%s' is not a positive bet amount.", amount)
		end
	end
	if errorMessage then
		md:ToPlayerNotifyInfo(player, string.format("You have %s.", TGNS.RoundPositiveNumberDown(playerBanks[steamId])))
		md:ToPlayerNotifyError(player, errorMessage)
		-- todo show some kind of 'get help' message
	end
end

function Plugin:EndGame(gamerules, winningTeam)
	local reportTransactions = playerGameTransactions
	TGNS.ScheduleAction(TGNS.ENDGAME_TIME_TO_READYROOM + 5, function()
		if Shine.Plugins.mapvote:VoteStarted() or (not TGNS.IsProduction()) then
			showReport(reportTransactions)
		end
	end)
	TGNS.DoFor(TGNS.GetClientList(), refundBets)
	playerGameBets = {}
	TGNS.DoForPairs(playerGameTransactions, function(steamId, transactions)
		karmaTransactions[steamId] = karmaTransactions[steamId] or 0
		local numberOfTransactionsToGiveKarmaFor = karmaTransactions[steamId] < MAXIMUM_KARMA_TRANSACTIONS and (MAXIMUM_KARMA_TRANSACTIONS - karmaTransactions[steamId]) or 0
		TGNS.DoFor(TGNS.Take(TGNS.Where(transactions, function(t) return TGNS.Has({'bet','payout'}, t.type) end), numberOfTransactionsToGiveKarmaFor), function(t)
			TGNS.Karma(steamId, "SpecBet")
			karmaTransactions[steamId] = karmaTransactions[steamId] + 1
		end)
	end)
	playerGameTransactions = {}
end

function Plugin:OnEntityKilled(gamerules, victimEntity, attackerEntity, inflictorEntity, point, direction)
	if attackerEntity and victimEntity and attackerEntity:isa("Player") and victimEntity:isa("Player") then
		local attackerClient = TGNS.GetClient(attackerEntity)
		local victimClient = TGNS.GetClient(victimEntity)
		if attackerClient and victimClient then
			onKill(attackerClient, victimClient)
		end
	end
end

function Plugin:PlayerSay(client, networkMessage)
	local cancel = false
	local player = TGNS.GetPlayer(client)
	local teamOnly = networkMessage.teamOnly
	local message = StringTrim(networkMessage.message)
	local isBetChat = TGNS.StartsWith(networkMessage.message, 'bet ')
	if isBetChat then
		local errorMessage
		if TGNS.IsPlayerSpectator(player) then
			if TGNS.IsGameInProgress() then
				message = TGNS.Substring(message, 4)
				message = StringTrim(message)
				local parts = TGNS.Split(' ', message)
				local firstPlayerPredicate = #parts > 0 and parts[1] or ""
				local secondPlayerPredicate = #parts > 1 and parts[2] or ""
				local amount = #parts > 2 and parts[3] or ""
				-- Shared.Message("PlayerSay> ====== placeBet =========================================================================================")
				placeBet(client, firstPlayerPredicate, secondPlayerPredicate, amount)
			else
				errorMessage = "Spectator Bets are allowed only during gameplay."
			end
		else
			errorMessage = "Spectate Bets are allowed only while you're spectating."
		end
		if errorMessage then
			md:ToPlayerNotifyError(player, errorMessage)
		end
		cancel = true
	end
	if cancel then
		return ""
	end
end

function Plugin:PostJoinTeam(gamerules, player, oldTeamNumber, newTeamNumber, force, shineForce)
	local client = TGNS.GetClient(player)
	local steamId = TGNS.GetClientSteamId(client)
	if TGNS.ClientIsOnPlayingTeam(client) then
		refundBets(client)
	elseif TGNS.IsClientSpectator(client) then
		refreshPlayerBank(steamId)
		TGNS.ScheduleAction(6, function()
			if Shine:IsValidClient(client) and TGNS.IsClientSpectator(client) and playerBanks[steamId] > 0 then
				md:ToPlayerNotifyInfo(TGNS.GetPlayer(client), string.format("You have %s. You may bet during gameplay (team chat example: bet wyz brian 5).", TGNS.RoundPositiveNumberDown(playerBanks[steamId])))
			end
		end)
	end
end

function Plugin:ClientConnect(client)
end

function Plugin:ClientConfirmConnect(client)
	local player = TGNS.GetPlayer(client)
end

function Plugin:Initialise()
    self.Enabled = true

	TGNS.RegisterEventHook("FullGamePlayed", function(clients, winningTeam, gameDurationInSeconds)
		if gameDurationInSeconds >= 300 or (not TGNS.IsProduction()) then
			local PerGameBankCredit = 5
			local humanClients = TGNS.Where(clients, function(c) return not TGNS.GetIsClientVirtual(c) end)
			TGNS.DoFor(humanClients, function(c)
				local steamId = TGNS.GetClientSteamId(c)
				local amount = PerGameBankCredit
				if winningTeam and winningTeam:GetTeamNumber() == TGNS.GetClientTeamNumber(c) then
					amount = amount * 1.2
				end
				persistTransaction(steamId, amount, nil, nil, 'playcredit')
				playerBanks[steamId] = playerBanks[steamId] or 0
				playerBanks[steamId] = playerBanks[steamId] + amount
			end)
		end
	end)

    return true
end

function Plugin:Cleanup()
    --Cleanup your extra stuff like timers, data etc.
    self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension("specbets", Plugin )