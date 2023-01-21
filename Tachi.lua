local t = {}

-- Code shamelessly stolen from ParseGrooveStatsIni. Sorry!
function GetTachiConfig(player)
	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	if not profile_slot[player] then return "" end

	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])

	-- We require an explicit profile to be loaded.
	if not dir or #dir == 0 then return end

	local path = dir.. "Tachi.json"

	if not FILEMAN:DoesFileExist(path) then
		return
	end

	local file = RageFileUtil.CreateRageFile()

	if not file:Open(path, 1) then
		Warn( string.format("ReadFile(%s): %s",path,file:GetError()) )
		file:destroy()
		return
	end

	local jsonStr = ""

	while not file:AtEOF() do
		local str = file:GetLine()
		jsonStr = jsonStr .. str;
	end

	local json = JsonDecode(jsonStr)

	return json
end

-- When we get to the score screen, fire the score off to Tachi
-- This is ugly, has no retry code, and is generally lazy. Maybe
-- this can be integrated better in the future. For now, this is
-- a neat prototype.
t["ScreenEvaluationStage"] = Def.ActorFrame {
	ModuleCommand= function(self)
		if GAMESTATE:IsCourseMode() then return end

		local Players = GAMESTATE:GetHumanPlayers()

		for player in ivalues(Players) do
			-- Do the same validation as GrooveStats.
			-- totally stolen now
			local _, valid = ValidForGrooveStats(player)

			if not valid then
				return
			end


			-- get this users authorisation
			-- yeah, we're parsing the JSON each time and not storing it
			-- i'm lazy to write invalidation code or find the right place
			-- to call this

			local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
			local stageStats = STATSMAN:GetCurStageStats()

			local song = GAMESTATE:GetCurrentSong()
			local songPos = GAMESTATE:GetSongPosition()

			local counts = GetExJudgmentCounts(player)

			local judgements = {
				["fantastic+"] = counts.W0,
				fantastic = counts.W1,
				excellent = counts.W2,
				great = counts.W3,
				decent = counts.W4,
				wayoff = counts.W5,
				miss = counts.Miss
			}

			local scorePercent = pss:GetPercentDancePoints() * 100.0

			if scorePercent > 100 then
				scorePercent = 100
			end

			local lamp = "FAILED";

			-- user hasn't failed? what kind of clear is this then.
			if not pss:GetFailed() then
				if
					judgements.fantastic +
					judgements.excellent +
					judgements.great +
					judgements.decent +
					judgements.wayoff +
					judgements.miss == 0
				then
					lamp = "QUINT"
				elseif
					judgements.excellent +
					judgements.great +
					judgements.decent +
					judgements.wayoff +
					judgements.miss == 0
				then
					lamp = "QUAD"
				elseif
					judgements.great +
					judgements.decent +
					judgements.wayoff +
					judgements.miss == 0
				then
					lamp = "FULL EXCELLENT COMBO"
				elseif
					judgements.decent +
					judgements.wayoff +
					judgements.miss == 0
				then
					lamp = "FULL COMBO"
				else
					lamp = "CLEAR"
				end
			end

			local pn = ToEnumShortString(player)
			local chartHash = SL[pn].Streams.Hash

			local lifebarHistory = pss:GetLifeRecord(song:GetLastSecond())

			local survivedPercent = 0;

			for val in ivalues(lifebarHistory) do
				if val > 0 then
					survivedPercent = survivedPercent + 1
				else
					break
				end
			end

			local scaledLifebar = {}
			for key, val in ipairs(lifebarHistory) do
				local newVal = val * 100

				if newVal < 0 then
					newVal = 0
				elseif newVal > 100 then
					newVal = 100
				end
				
				scaledLifebar[key] =  newVal
			end

			if stageStats:GaveUp() and survivedPercent == 100 then
				scaledLifebar = nil
				survivedPercent = 0
			end

			local tachiScore = {
				scorePercent = scorePercent,
				survivedPercent = survivedPercent,
				lamp = lamp,
				judgements = judgements,
				matchType = "itgChartHash",
				identifier = chartHash,
				optional = {
					lifebarHistory = scaledLifebar
				}
			}

			local batchManual = {
				meta = {
					game = "itg",
					playtype = "Stamina",
					service = ProductID() .. " v" .. ProductVersion() .. " (tsl v0.1.2)",
				},
				-- array with one score
				scores = { tachiScore }
			}

			local config = GetTachiConfig(player)

			if not config then
				return
			end

			for conf in ivalues(config) do
				NETWORK:HttpRequest {
					url = conf.url,
					method = "POST",
					body = JsonEncode(batchManual),
					headers = {
						Authorization = "Bearer " .. conf.token,
						["Content-Type"] = "application/json",
	
						-- We don't have access to the system clock really inside
						-- this sandbox, so lets just let the server decide when
						-- the score happened instead.
						["X-Infer-Score-TimeAchieved"] = "true"
					},
					onResponse = function(response)
						if response.errorMessage then
							SM("Failed to submit to Tachi: " .. response.errorMessage)
						else
							SM("Score submitted to Tachi!")
						end
					end,
				}
			end
		end
	end
}

return t