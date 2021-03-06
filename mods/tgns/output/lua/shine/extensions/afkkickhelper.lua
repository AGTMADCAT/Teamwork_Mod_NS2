local isAfkResetEnabled
local md
local lastWarnTimes = {}
local lastMoveTimes = {}
local mayEarnRemovedFromPlayByAfkKarma = {}

local function resetAfk(client)
	if isAfkResetEnabled and client then
		Shine.Plugins.afkkick:ResetAFKTime(client)
	end
end

local Plugin = {}

local function isTimedStart()
	local result = Shared.GetTime() - Shine.Plugins.timedstart:GetWhenFifteenSecondAfkTimerWasLastAdvertised() < 30
	return result
end

function Plugin:GetAfkThresholdInSeconds(player)
	-- Shared.Message("TGNS.HasPlayerSignedPrimerWithGames: " .. tostring(TGNS.HasPlayerSignedPrimerWithGames(p)))
	local result = (isTimedStart() and not TGNS.IsPlayerSpectator(player)) and (TGNS.HasPlayerSignedPrimerWithGames(player) and 30 or 15) or 60
	return result
end

-- function Plugin:OnProcessMove(player, input)
-- 	if bit.band(input.commands, Move.Use) ~= 0 then
-- 		resetAfk(TGNS.GetClient(player))
-- 	end
-- end

function Plugin:PlayerSay(client, networkMessage)
	resetAfk(client)
end

function Plugin:PostJoinTeam(gamerules, player, oldTeamNumber, newTeamNumber, force, shineForce)
	local client = TGNS.GetClient(player)
    if TGNS.IsPlayerReadyRoom(player) then
    	if TGNS.IsGameInProgress() then
	    	if TGNS.IsGameplayTeamNumber(oldTeamNumber) and TGNS.GetCurrentGameDurationInSeconds() > 30 and TGNS.IsPlayerAFK(player) and #TGNS.GetPlayingClients(TGNS.GetPlayerList()) >= 7 and (not (force or shineForce)) then
	    		if mayEarnRemovedFromPlayByAfkKarma[client] then
		    		TGNS.Karma(client, "RemovedFromPlayByAFK")
		    		mayEarnRemovedFromPlayByAfkKarma[client] = false
	    		end
	    	end
	    else
	    	TGNS.MarkPlayerAFK(player)
	    	Shine.Plugins.scoreboard:AnnouncePlayerPrefix(player)
    	end
    elseif not (force or shineForce) then
    	TGNS.ClearPlayerAFK(player)
    end
end

function Plugin:Initialise()
    self.Enabled = true
    md = TGNSMessageDisplayer.Create("AFK")

	TGNS.RegisterEventHook("AFKChanged", function(client, playerIsAfk)
		if client and not playerIsAfk then
			mayEarnRemovedFromPlayByAfkKarma[client] = true
		end
	end)

    TGNS.ScheduleAction(5, function()
    	isAfkResetEnabled = Shine.Plugins.afkkick and Shine.Plugins.afkkick.Enabled and Shine.Plugins.afkkick.ResetAFKTime
    end)
	local originalGetCanPlayerHearPlayer
	originalGetCanPlayerHearPlayer = TGNS.ReplaceClassMethod("NS2Gamerules", "GetCanPlayerHearPlayer", function(self, listenerPlayer, speakerPlayer)
		resetAfk(TGNS.GetClient(speakerPlayer))
		return originalGetCanPlayerHearPlayer(self, listenerPlayer, speakerPlayer)
	end)

	local processAfkPlayers
	processAfkPlayers = function()
		local isReadyRoomCaptainsOptIn = function(c) return TGNS.IsClientReadyRoom(c) and Shine.Plugins.captains and Shine.Plugins.captains.IsOptedInAsPlayer and Shine.Plugins.captains:IsOptedInAsPlayer(client) end 
		local clientIsVulnerableToAfk = function(c)
			local result
			if Server.GetNumPlayersTotal() < Server.GetMaxPlayers() then
				result = TGNS.ClientIsOnPlayingTeam(c)
			else
				result = not TGNS.IsClientSpectator(c)
			end
			if result and Shine.GetGamemode() == "Infested" and TGNS.ClientIsMarine(c) and not TGNS.IsClientAlive(c) then
				result = false
			end
			if not TGNS.IsProduction() then
				result = false
			end
			return result
		end
		TGNS.DoFor(TGNS.GetHumanClientList(), function(c)
			local p = TGNS.GetPlayer(c)
			local afkThresholdInSeconds = self:GetAfkThresholdInSeconds(p);
			local afkScenarioDescriptor = isTimedStart() and " (pre/early game)" or ""
			if TGNS.IsPlayerAFK(p) then
				local lastMoveTime = Shine.Plugins.afkkick:GetLastMoveTime(c)
				if (lastMoveTime ~= nil) and (TGNS.GetSecondsSinceMapLoaded() - lastMoveTime >= afkThresholdInSeconds) and clientIsVulnerableToAfk(c) then
					local lastWarnTime = lastWarnTimes[c] or 0
					if Shared.GetTime() - lastWarnTime > 10 then
						local isReadyRoomCaptainsOptIn = isReadyRoomCaptainsOptIn(c)
						md:ToPlayerNotifyInfo(p, string.format("AFK %s%s. Move to avoid %s.", Pluralize(afkThresholdInSeconds, "second"), afkScenarioDescriptor, isReadyRoomCaptainsOptIn and "risking Captains opt-out" or "being sent to Spectate"))
						lastWarnTimes[c] = Shared.GetTime()
						local playAfkPingSoundToClient = function(level)
							if Shine:IsValidClient(c) and TGNS.IsClientAFK(c) and clientIsVulnerableToAfk(c) then
								TGNS.SendNetworkMessageToPlayer(TGNS.GetPlayer(c), Shine.Plugins.arclight.HILL_SOUND, {i=level})
							end
						end
						TGNS.ScheduleAction(1, function() playAfkPingSoundToClient(6) end)
						TGNS.ScheduleAction(2, function() playAfkPingSoundToClient(5) end)
						TGNS.ScheduleAction(3, function() playAfkPingSoundToClient(4) end)
						TGNS.ScheduleAction(4, function() playAfkPingSoundToClient(3) end)
						TGNS.ScheduleAction(5, function() playAfkPingSoundToClient(2) end)
					end
					TGNS.ScheduleAction(6, function()
						if Shine:IsValidClient(c) then
							p = TGNS.GetPlayer(c)
							if TGNS.IsPlayerAFK(p) then
								local lastMoveTime = lastMoveTimes[c] or 0
								if Shared.GetTime() - lastMoveTime > 10 then
									local isReadyRoomCaptainsOptIn = isReadyRoomCaptainsOptIn(c)
									md:ToPlayerNotifyInfo(p, string.format("AFK %s%s. Moved to Spectate.", Pluralize(afkThresholdInSeconds, "second"), afkScenarioDescriptor))
									if not TGNS.IsClientSpectator(c) then
										TGNS.SendToTeam(p, kSpectatorIndex, true)
									end
									if not isReadyRoomCaptainsOptIn then
										lastMoveTimes[c] = Shared.GetTime()
									end
								end
							end
						end
					end)
				end
			end
		end)
		TGNS.ScheduleAction(isTimedStart() and 1 or 15, processAfkPlayers)
	end
	TGNS.ScheduleAction(15, processAfkPlayers)
    return true
end

function Plugin:Cleanup()
    --Cleanup your extra stuff like timers, data etc.
    self.BaseClass.Cleanup( self )
end

Shine:RegisterExtension("afkkickhelper", Plugin )