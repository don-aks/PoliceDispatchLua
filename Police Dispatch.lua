-- vk.com/donakslua
script_name('Police Dispatch')
script_author('donaks')
script_version('2.0-beta')
script_url("blast.hk/threads/59503")
script_version_number(2)

require 'lib.moonloader'
local download_status = require('lib.moonloader').download_status
local sampev = require 'lib.samp.events'
local inicfg = require 'inicfg'
local memory = require 'memory'

require 'config.PoliceDispatchConfig.config'

local DISP_IS_SPEAK = false
local VARS = {}
local MAP_ICONS = {}
local CFG, INI


function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(100) end
	while sampGetCurrentServerName() == 'SA-MP' do wait(100) end

	-- Подгрузка .json
	local f = io.open(PATCH.config.."config.json", 'r')
	-- удаляем комментарии
	local f_text = f:read('*a'):gsub("//[^\n]+", ''):gsub("/%*(.-)%*/", '')

	CFG = decodeJson(f_text)
	f:close()

	if not CFG then
		local f = io.open(PATCH.config.."json_err.log", 'w')
		f:write(f_text)
		f:close()

		print("Текст .json файла, который читал скрипт находится в moonloader/config/PoliceDispatchConfig/json_err.log")
		chatMessage("Не удалось считать .json файл! Подробности в moonloader.log.")
		thisScript():unload()
		return
	end

	local serverName = sampGetCurrentServerName()
	local ip, port = sampGetCurrentServerAddress()
	local serverIP = ip..":"..port

	local isFindServer = false
	-- Подбор нужного сервера
	for _, server in ipairs(CFG.servers) do
		if server.server.ip == serverIP or serverName:find(server.server.name, 1, true) then
			-- соединяем главный config и
			-- конфиг сервера для удобства
			-- CFG -> config, call, find ...
			local c = server
			c.config = CFG.config
			CFG = c

			isFindServer = true
			break
		end
	end

	-- Подгрузка .ini
	local tUser = {}
	if CFG.user then
		for i, it in ipairs(CFG.user) do
			tUser[i] = true
		end
	end

	if not isFindServer then
		print("Данного сервера не найдено в конфиге. Завершаю работу скрипта.")
		thisScript():unload()
		return
	end

	INI = inicfg.load({
		INI={
			state=true,
			isCheckUpdates=true,
			callsVolume=3,
			findVolume=3,
			radioVolume=3.5,
			userVolume=3
		}
	}, "PoliceDispatchConfig/config.ini")

	local keyServer = CFG.name.."_UserEvents"
	if #tUser > 0 and (not INI[keyServer] or #tUser ~= #INI[keyServer]) then
		INI[keyServer] = tUser
	end
	inicfg.save(INI, "PoliceDispatchConfig/config.ini")

	checkUpdates()

	sampRegisterChatCommand('pdradio', mainMenu)


	if INI.INI.state then
		chatMessage("Загружен. Управление скриптом: {32B4FF}/pdradio{FFFFFF}. Автор: {32B4FF}vk.com/donakslua{FFFFFF}.")
	else
		chatMessage("Отключен! Управление скриптом: {32B4FF}/pdradio{FFFFFF}. Автор: {32B4FF}vk.com/donakslua{FFFFFF}.")
	end

	local radioVol = memory.read(0xBA6798, 1)
	if INI.INI.state and radioVol == 0 then
		chatMessage("Внимание! У вас отключено радио в настройках. Включите его, если хотите что-то услышать.")
	end

	while true do
		wait(0)
		checkDialogsRespond()
	end
end



function sampev.onServerMessage(color, message)
	if not INI or not CFG or not INI.INI.state then return true end

	handleEvent(message, color)
	return true
end




function handleEvent(str, color)
	local ev, pattern, markerId, idUserEvent = getEventInfo(str, color)
	if not ev then
		-- очищаем, потому что инфа должна быть на следующей строке
		if #VARS > 0 then
			print("VARS = {}")
			VARS = {}
		end
		return false, 'not ev'
	end

	local vars = getVariablesFromMessage(str, pattern)
	-- Чекаем остался ли глобальный VARS от предыдущего вызова.
	vars = concatWithGlobalVars(vars, ev)

	if ev == 'find' then
		if INI.INI.findVolume == 0 then return false, 'volume' end
		print("find")
		-- Если нет обязательного параметра
		if not vars.area then
			if markerId then
				vars.area = getMarkerArea(markerId)
				if not vars.area then
					print("Иконка на карте с id "..markerId.." в эвенте find не найдена.")
					return false
				end
			elseif type(CFG.find.pattern) == 'table' and #CFG.find.pattern > 1 then
				-- Оставляем данные на потом
				VARS['find'] = vars
				return true
			else
				print("Ошибка! Перменная @area не указана в эвенте find!")
				print("Укажите markerId или @area в сообщении и перезагрузите скрипт!")
				return false
			end
		end

		vars.vehid = vars.vehid or vars.vehname and getCarModelByName(vars.vehname)

		if CFG.find.vehOnFoot and vars.vehname == CFG.find.vehOnFoot then
			vars.onFoot = true
		elseif vars.nick or vars.id then
			-- Берем инфу об авто исходя из данных игрока
			local playerId = tonumber(vars.id) or sampGetPlayerIdByNickname(vars.nick)
			local playerInStream, playerHandle = sampGetCharHandleBySampPlayerId(playerId)

			if playerInStream and isCharInAnyCar(playerHandle) then
				local carHandle = storeCarCharIsInNoSave(playerHandle)
				vars.vehid = getCarModel(carHandle)
				vars.vehcolor, _ = getCarColours(carHandle)
			end
		end

	elseif ev == 'call' then
		if INI.INI.callsVolume == 0 then return false, 'volume' end
		if not vars.area or not vars.text then
			if type(CFG.call.pattern) == 'table' and #CFG.call.pattern > 1 then
				VARS['call'] = vars
				return true
			else
				print("Ошибка! Перменная @area или @text не указана в эвенте call!")
				return false
			end
		end

		if inArray(vars.text, CFG.config.stopWords) then
			return
		end

		if 		CFG.call.isPlayGangActivity and
				inArray(str, CFG.config.dictionaryGangActivity) and
				varInElementsArray(vars.area, GANG_ACTIVITY_SOUNDS)
		then
			ev = 'gangActivity'
		elseif 	math.random(3) == 2 and
				varInElementsArray(vars.area, AREA_AND_CODE_SOUNDS) 
		then
			math.randomseed(os.time())
			ev = 'areaAndCode'
		end

	elseif ev == 'radio' then
		if INI.INI.radioVolume == 0 then return false, 'volume' end
		if CFG.radio.isPlayShotsFired then
			if inArray(vars.text, CFG.config.code0Words) then
				ev = 'code0'
			elseif inArray(vars.text, CFG.config.code1Words) then
				ev = 'code1'
			end
		end

		-- Пользовательские эвенты на радио
		if 	ev == 'radio' and 
			type(CFG.radio.userMessages) == "table" and 
			#CFG.radio.userMessages > 0 
		then
			for _, usermsg in ipairs(CFG.radio.userMessages) do
				print(vars.text, usermsg.textFind)
				if inArray(vars.text, toTable(usermsg.textFind), usermsg.useRegexInPattern) then
					local sounds = toTable(usermsg.sounds)
					for i, sound in ipairs(sounds) do
						sounds[i] = PATCH.config..'audio\\'..sound:gsub('/', '\\')
					end

					lua_thread.create(
						playSounds,
						sounds,
						'radioVolume',
						usermsg.isPlayRadioOn
					)
					return
				else
					return false, 'not ev'
				end
			end
		elseif inArray(vars.text, QUESTION_WORDS) then
			return
		end

	elseif ev == 'user' then
		if INI.INI.userVolume == 0 then return false, 'volume' end
		local arrSounds = parceSounds(idUserEvent, vars)
		if type(arrSounds) == 'table' and #arrSounds > 0 then
			lua_thread.create(playSounds, arrSounds, 'userVolume', CFG.user[idUserEvent].isPlayRadioOn)
			return
		else
			return arrSounds
		end
	end

	playDispatch(ev, vars)
end




function playDispatch(event, vars)
	local CFGev = CFG[event]

	if event == 'call' then
		lua_thread.create(playSounds, {
			DISPATCH_SOUNDS.words.weGot10,
			randomChoice(DISPATCH_SOUNDS.codesWithIn),
			getAreaSoundPatch(vars.area)
		}, 'callsVolume', true)

	elseif event == 'gangActivity' then
		-- функция для файлов типа Jefferson2.
		local msgs = {}
		for _, fname in ipairs(GANG_ACTIVITY_SOUNDS) do
			if fname:find(vars.area, 1, true) then
				msgs[#msgs+1] = fname
			end
		end

		lua_thread.create(playSounds, randomChoice(msgs), 'callsVolume')

	elseif event == 'areaAndCode' then
		lua_thread.create(playSounds, PATCH.config..PATCH.areaAndCode..vars.area..'.ogg', 'callsVolume')

	elseif event == 'find' then
		lua_thread.create(playSounds, {
			DISPATCH_SOUNDS.suspect.lastSeen,
			DISPATCH_SOUNDS.words.inA,
			getAreaSoundPatch(vars.area),
			(
				vars['vehid'] and DISPATCH_SOUNDS.words.onA or
				vars['onFoot'] and DISPATCH_SOUNDS.suspect.onFoot or
				nil
			),
			getCarColorSound(vars.vehcolor),
			getVehSound(vars.vehid)
		}, 'findVolume', true)

	elseif event == 'code1' then
		lua_thread.create(playSounds, randomChoice(CODE_1_SOUNDS), 'radioVolume')

	elseif event == 'code0' then
		lua_thread.create(playSounds, randomChoice(CODE_0_SOUNDS), 'radioVolume')
	end
end



function concatWithGlobalVars(vars, event)
	if VARS[event] then
		local t = concatTablesWithKeys(vars, VARS[event])
		VARS[event] = {}
		return t
	end
	return vars
end

function getEventInfo(str, color)
	local ev, patt, idUserEvent = getEventAndPattern(str, color)
	if ev == false then return end
	local markerId = CFG[ev].markerId

	return ev, patt, markerId, idUserEvent
end

function getEventAndPattern(str, color)
	for _, key in ipairs({'call', 'find', 'radio'}) do
		local patterns = CFG[key].pattern
		local colors = CFG[key].color

		patterns = toTable(patterns)
		colors = toTable(colors)

		local isColor = true
		for _, col in pairs(colors) do
			if col ~= tonumber(color) then
				isColor = false
			else
				isColor = true
				break
			end
		end
		if not isColor then return false end

		for _, patt in ipairs(patterns) do
			if not CFG[key].useRegexInPattern then
				patt = '^'..esc(patt)
			end
			local pattWithoutVars = getPatternWithoutVars(patt)
			if str:find(pattWithoutVars) then
				return key, patt
			end
		end
	end
	
	local userPattern, idUserEvent = getUserPatternAndId(str, color)
	if userPattern then
		return 'user', userPattern, idUserEvent
	end

	return false
end

function getUserPatternAndId(str, color)
	if not CFG.user or #CFG.user == 0 then
		return false
	end

	for i, ev in ipairs(CFG.user) do
		if INI[CFG.name.."_UserEvents"][i] then
			local patterns = ev.pattern
			local colors = ev.color

			patterns = toTable(patterns)
			colors = toTable(colors)

			local isColor = true
			for _, col in pairs(colors) do
				if col ~= tonumber(color) then
					isColor = false
				else
					isColor = true
					break
				end
			end

			if isColor then
				for _, patt in ipairs(patterns) do
					if not ev.useRegexInPattern then
						patt = '^'..esc(patt)
					end

					local pattWithoutVars = getPatternWithoutVars(patt)
					if str:find(pattWithoutVars) then
						return patt, i
					end
				end
			end
		end
	end
end

function getVariablesFromMessage(message, pattern)
	-- возвращает массив {var: value}
	local arrVars = {}
	local vars = {}

	-- ищем все @var
	local start = 1
	local var
	for _ = 1, #message do
		_, start, var = pattern:find("@([%a_]+)", start)
		if var then
			vars[#vars+1] = var
		else
			break
		end
	end

	for _, var in ipairs(vars) do
		local patternWithoutVar = pattern:gsub("@"..var, "(.+)"):gsub("@([%a_]+)", '.+')
		arrVars[var] = message:match(patternWithoutVar)
		if arrVars[var] == nil then
			print("Не найдена переменная @"..var.." в строке \""..message.."\"!")
		end
	end

	return arrVars
end

function getPatternWithoutVars(pattern)
	return pattern:gsub("@([%a_]+)", ".+")
end


function esc(s)
      return (s:gsub('%^', '%%^')
               :gsub('%$', '%%$')
               :gsub('%(', '%%(')
               :gsub('%)', '%%)')
               :gsub('%.', '%%.')
               :gsub('%[', '%%[')
               :gsub('%]', '%%]')
               :gsub('%*', '%%*')
               :gsub('%+', '%%+')
               :gsub('%-', '%%-')
               :gsub('%?', '%%?'))
end


function parceSounds(idUserEvent, vars)
	local arrSounds = {}
	local CFGuser = CFG.user[idUserEvent]
	for i, sound in ipairs(CFGuser.sounds) do

		if type(sound) ~= 'string' then
			print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
			print("Пользовательские звуки должны быть между кавычками!")
			return false

		-- DISP.key1.key2
		elseif sound:find("^DISP%.") then
			local s = sound:split('%.')
			if #s == 2 or #s == 3 then
				local newSound
				if #s == 3 then
					if s[2] == 'codes' or s[2] == 'codesWithIn' then
						s[3] = tonumber(s[3])
					end
					newSound = DISPATCH_SOUNDS[s[2]][s[3]]
				else
					newSound = DISPATCH_SOUNDS[s[2]]
				end

				if not newSound then
					print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
					print("Звук не найден! Убедитесь что вы все верно написали.")
					print("Сравните свои ключи с ключами в переменной DISPATCH_SOUNDS в файле config.lua.")
					print("Регистр символов имеет значение!")
					return false
				end
				sound = newSound
			else
				print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
				print("Указывать звук нужно: DISP.key1.key2. Пример: DISP.words.headTo10.")
				return false
			end

		-- @var
		elseif sound:find("^@") then
			local varname = sound:match("@([%a_]+)")
			if not varname then
				print("Некорректная переменная в звуке "..tostring(sound).." (№"..i..")"..
					" в user эвенте '"..CFGuser.name.."'!")
				print("Переменные пишутся только латиницей или нижним подчеркиванием!")
				return false
			end

			-- Если переменной нет в строке.
			if 	(not vars[varname]) and 
				(not (CFGuser.vars and CFGuser.vars[varname])) and
				(varname ~= 'veh' or not (vars.vehname or vars.vehid))
			then
				if varname == 'area' and CFGuser.markerId then
					local markerId = CFGuser.markerId
					local area = getMarkerArea(markerId)
					if not area then
						print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("Иконка на карте с id "..markerId.." в эвенте user не найдена.")
						return false
					end
					sound = getAreaSoundPatch(area)
					if not sound then
						print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("@area не найдено.")
						return false
					end

				elseif varname == 'veh' then
					if vars.id or vars.nick then
						vars.id = tonumber(vars.id) or sampGetPlayerIdByNickname(vars.nick)
						local playerInStream, playerHandle = sampGetCharHandleBySampPlayerId(vars.id)
						
						if playerInStream and isCharInAnyCar(playerHandle) then
							local carHandle = storeCarCharIsInNoSave(playerHandle)
							vars.vehid = getCarModel(carHandle)
							vars.vehcolor, _ = getCarColours(carHandle)

							table.insert(arrSounds, getVehSound(vars.vehid))
							table.insert(arrSounds, getCarColorSound(vars.vehcolor))
							sound = nil
						else
							print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
							print("Переменной @vehname или @vehid нет в строке!")
							print("И игрок, указанный в переменных @id или @nick вне зоне стрима!")
							return false 
						end
					else
						print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("Переменной @vehname или @vehid нет в строке!")
						return false
					end
				else
					print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
					print("Переменной @"..varname.." нет в строке!")
					return false
				end

			-- Есть конструкция с пользовательскими заменами переменных
			elseif 
				CFGuser.vars and
				((CFGuser.vars[varname]) or
					(varname == 'veh' and (
							CFGuser.vars['vehname'] or
							CFGuser.vars['vehid']
						)
					)
				)
			then
				if varname ~= 'veh' then
					newSound = CFGuser.vars[varname][vars[varname]]
					if newSound then
						sound = newSound
					else
						print("Warning! В vars."..varname.." нет значения "..vars[varname]..". "..
							"Переменная не перезаписалась.")
					end
				end

				-- Дополнительная обработка переменных.
				if varname == 'area' then
					local area = sound
					sound = getAreaSoundPatch(area)
					if not sound then
						print("Ошибка в звуке '@area' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("После замены на пользовательскую конструкцию, район "..area.." не был найден.")
						return false
					end
				elseif varname == 'veh' then
					if vars['vehname'] or vars['vehid'] then
						if CFGuser.vars['vehname'] then
							local newSound = CFGuser.vars.vehname[vars.vehname]
							if newSound then
								vars.vehname = newSound
							end
						end
						if CFGuser.vars['vehid'] then
							local newSound = CFGuser.vars.vehid[vars.vehid]
							if newSound then
								vars.vehid = newSound
							end
						end

						vars.vehid = vars.vehid or vars.vehname and getCarModelByName(vars.vehname)
						sound = getVehSound(vars.vehid)
						if not sound then
							print("Ошибка в звуке '@veh' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
							if vars.vehid then
								print("Автомобиль с id '"..tostring(vars.vehid).."' не был найден!")
							elseif vars.vehname then
								print("Автомобиль с названием '"..tostring(vars.vehname).."' не был найден!")
							end
							return false
						end

						if CFGuser.veh and vars.vehname == CFGuser.vehOnFoot then
							table.insert(arrSounds, DISPATCH_SOUNDS.suspect.onFoot)
							sound = nil

						elseif vars.id or vars.nick then
							vars.id = tonumber(vars.id) or sampGetPlayerIdByNickname(vars.nick)
							local playerInStream, playerHandle = sampGetCharHandleBySampPlayerId(vars.id)
							if playerInStream and isCharInAnyCar(playerHandle) then
								local carHandle = storeCarCharIsInNoSave(playerHandle)
								vars.vehid = getCarModel(carHandle)
								vars.vehcolor, _ = getCarColours(carHandle)

								table.insert(arrSounds, getVehSound(vars.vehid))
								table.insert(arrSounds, getCarColorSound(vars.vehcolor))
								sound = nil
							else
								print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
								print("Переменной @vehname или @vehid нет в строке!")
								print("И игрок, указанный в переменных @id или @nick вне зоне стрима!")
								return false 
							end
						end
					else
						print("Ошибка в звуке '@area' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("Переменной @vehname или @vehid нет в строке!")
						return false
					end
				else
					if type(sound) ~= 'string' then
						print("Ошибка в звуке '"..tostring(sound).."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
						print("Значение переменной должна быть строка!")
						return false
					elseif sound:find("^DISP%.") then
						local s = sound:split('%.')
						local newSound
						if #s == 3 then
							if s[2] == 'codes' or s[2] == 'codesWithIn' then
								s[3] = tonumber(s[3])
							end
							newSound = DISPATCH_SOUNDS[s[2]][s[3]]
						else
							newSound = DISPATCH_SOUNDS[s[2]]
						end

						if not newSound then
							print("Ошибка в звуке '"..sound.."' (№"..i..") в user эвенте '"..CFGuser.name.."'!")
							print("Звук не найден! Убедитесь что вы все верно написали.")
							print("Сравните свои ключи с ключами в переменной DISPATCH_SOUNDS в файле config.lua.")
							print("Регистр символов имеет значение!")
							return false
						end
						sound = newSound
					else
						sound = PATCH.config.."audio\\"..newSound
					end
				end

			else
				if varname == 'area' then
					sound = getAreaSoundPatch(vars.area)
					if not sound then
						print("Ошибка в звуке №"..i.." в user эвенте '"..CFGuser.name.."'!")
						print("@area не найдено.")
						return false
					end

				elseif varname == 'veh' then
					if vars['vehname'] or vars['vehid'] then
						vars.vehid = vars.vehid or vars.vehname and getCarModelByName(vars.vehname)
						sound = getVehSound(vars.vehid)

						if CFGuser.veh and vars.vehname == CFGuser.vehOnFoot then
							sound = DISPATCH_SOUNDS.suspect.onFoot
						elseif vars.id or vars.nick then
							vars.id = tonumber(vars.id) or sampGetPlayerIdByNickname(vars.nick)
							local playerInStream, playerHandle = sampGetCharHandleBySampPlayerId(vars.id)
							if playerInStream and isCharInAnyCar(playerHandle) then
								local carHandle = storeCarCharIsInNoSave(playerHandle)
								vars.vehcolor, _ = getCarColours(carHandle)

								table.insert(arrSounds, vars.vehid)
								table.insert(arrSounds, vars.vehcolor)
								sound = nil
							end
						end
					else
						print("Ошибка в звуке №"..i.." в user эвенте '"..CFGuser.name.."'!")
						print("Невозможно получить звук автомобиля, так как ...")
						print("... в паттерне не указана ни @vehname, ни @vehid!")
						return false
					end
				else
					sound = vars[varname]
				end
			end
		-- относительный путь
		elseif sound:find("%.") then
			sound = sound:gsub("/", "\\")
			sound = PATCH.config.."audio\\"..sound
		else
			print("Неизвестный звук "..sound.." (№"..i..") в user эвенте '"..CFGuser.name.."'!")
			return false
		end

		arrSounds[#arrSounds+1] = sound
	end

	return arrSounds
end


function playSounds(array, volume, isPlayRadioOn)
	-- запуск в lua_thread
	array = toTable(array)

	while DISP_IS_SPEAK do wait(0) end
	DISP_IS_SPEAK = true

	local radioOnSound
	if isPlayRadioOn then
		radioOnSound = loadAudioStream(DISPATCH_SOUNDS.radioOn)
		play(radioOnSound, volume)
		wait(1000)
	end

	for _, sound in pairs(array) do
		if type(sound) == 'string' then
			sound = loadAudioStream(sound)
		end
		if sound then
			wait(play(sound, volume))
		end
	end

	if isPlayRadioOn then
		wait(300)
		play(radioOnSound, volume)
	end
	wait(1000)

	DISP_IS_SPEAK = false
end

function play(sound, volume)
	--[[функция проигрывает звук sound с громкостью volume
	если параметр строка, то он берет громкость из ини файла
	а возвращает длинну данного звука в миллисекундах, 
	специально для функции wait(), 
	чтобы следующий звук в коде проигрался после этого.
	Получается: wait(play(loadAudioStream('find.mp3'), 'find'))]]

	if tonumber(volume) then
		volume = tonumber(volume)
	elseif type(volume) == 'string' then
		volume = INI.INI[volume]
	else
		volume = 1
	end

	setAudioStreamVolume(sound, volume)
	setAudioStreamState(sound, 1)
	return getAudioStreamLength(sound) * 1000 + 40
end



function getMarkerArea(markerId)
	local markerPos
	for _, icon in ipairs(MAP_ICONS) do
		if icon.type == markerId then
			markerPos = icon.pos
			break
		end
	end
	if not markerPos then
		print("Не найдена позиция маркера с id "..markerId..'!')
		return false 
	end

	return calculateArea(markerPos.x, markerPos.y)
end

function calculateArea(x, y)
	for i, v in ipairs(AREAS) do
		if (x >= v[2]) and (y >= v[3]) and (x <= v[5]) and (y <= v[6]) then
			return v[1]
		end
	end
	return "Unknown"
end



function getCarModelByName(nameModel)
	for id, name in pairs(CAR_NAMES) do
		if name:tolower() == nameModel:tolower() then
			return id
		end
	end
	-- пользовательские
	if CFG.serverConfig then
		for name, id in pairs(CFG.serverConfig.vehNames) do
			if name:tolower() == nameModel:tolower() then
				return id
			end
		end
	end
end

function getVehSound(modelCarId)
	for class, arrayIds in pairs(CARS) do
		for _, idModel in ipairs(arrayIds) do
			if idModel == modelCarId then
				return loadAudioStream(PATCH.config..PATCH.vehicles..class..'.wav')
			end
		end
	end
end

function getCarColorSound(colorId)
	for colorName, colorsArray in pairs(COLORS) do
		for _, idColor in ipairs(colorsArray) do
			if colorId == idColor then
				return loadAudioStream(PATCH.config..'audio\\colors\\'..colorName..'.wav')
			end
		end
	end
end

function getAreaSoundPatch(area)
	area = area:gsub('-', ' '):gsub('_', ' '):gsub("'", '')

	local patch = PATCH.config..PATCH.area..area..'.wav'
	if doesFileExist(patch) then
		return patch
	else
		local newArea = AREAS_NOT_VOICED[area:tolower()]

		-- пользовательские
		if not newArea and CFG.serverConfig and CFG.serverConfig.areas then
			for name, ar in pairs(CFG.serverConfig.areas) do
				if name:tolower() == area:tolower() then
					newArea = ar
				end
			end
		end

		if newArea then
			return getAreaSoundPatch(newArea)
		else
			print("Района \""..area.."\" не найдено.")
			return false
		end
	end
end



function sampGetPlayerIdByNickname(nick)
    local _, myid = sampGetPlayerIdByCharHandle(playerPed)
    if tostring(nick) == sampGetPlayerNickname(myid) then return myid end
    for i = 0, 1000 do if sampIsPlayerConnected(i) and sampGetPlayerNickname(i) == tostring(nick) then return i end end
end



function inArray(variable, arr, isRegEx)
	for i, element in pairs(arr) do
		if type(i) == 'string' then
			element = i
		end
		if string.find(variable:tolower(), element:tolower(), 1, not isRegEx) then
			return true
		end
	end
	return false
end

function varInElementsArray(var, arr)
	for _, el in pairs(arr) do
		if string.find(el:tolower(), var:tolower(), 1, true) then
			return true
		end
	end
	return false
end

function randomChoice(arr)
	-- возвращает случайный элемент arr
	if #arr == 0 then
		local iter = 0
		newArr = {}
		for i, it in pairs(arr) do
			iter = iter + 1
			newArr[iter] = it
		end
		arr = newArr
	end
	math.randomseed(os.time())
	return arr[math.random(#arr)]
end

function string:split(sep)
	if sep == nil then
		sep = "%s"
	end
	local t={}
	for str in string.gmatch(self, "([^"..sep.."]+)") do
		t[#t+1] = str
	end
	return t
end

function concatTablesWithKeys(t1, t2)
	for k,v in pairs(t2) do
		t1[k] = v
	end

	return t1
end

function toTable(var)
	if type(var) ~= 'table' then
		return {var}
	else
		return var
	end
end



-- иконки на карте
function sampev.onSetMapIcon(id, pos, typeIcon, color, style)
	-- print("onSetMapIcon id="..id..", type="..typeIcon..", ("..pos.x..", "..pos.y..")")
	MAP_ICONS[#MAP_ICONS+1] = {
		id=id, 
		pos=pos, 
		type=typeIcon
	}
end

function sampev.onRemoveMapIcon(id)
	-- print("onRemoveMapIcon id="..id)
	for i, v in ipairs(MAP_ICONS) do
		if v.id == id then
			MAP_ICONS[i] = nil
		end
	end
end

-- красная метка
function sampev.onSetCheckpoint(pos, radius)
	-- print("onSetCheckpoint ("..pos.x..", "..pos.y..")")
	-- Удаляем предыдущую метку
	for i, icon in ipairs(MAP_ICONS) do
		if icon.type == 1 then
			print("Удалили предыдущий")
			MAP_ICONS[i] = nil
			break
		end
	end

	MAP_ICONS[#MAP_ICONS+1] = {
		id='check',
		pos=pos,
		type=1
	}
end

function sampev.onDisableCheckpoint()
	-- print("onDisableCheckpoint")
	for i, v in ipairs(MAP_ICONS) do
		if v.id == 'check' then
			MAP_ICONS[i] = nil
		end
	end
end



function checkUpdates()
	if not INI.INI.isCheckUpdates then return end

	local fpath = os.tmpname()
	downloadUrlToFile(
		"https://raw.githubusercontent.com/don-aks/PoliceDispatchLua/main/Police%20Dispatch.lua", 
		fpath,
		function(_, status, _, _)
			if status == download_status.STATUS_ENDDOWNLOADDATA then
				if doesFileExist(fpath) then
					local f = io.open(fpath, "r")
					local f_text = f:read("*a")
					f:close()
					local versNum = string.match(f_text, "script_version_number%s*%((%d+)%)")

					if versNum and tonumber(versNum) > thisScript().version_num then
						local versStr = string.match(f_text, "script_version%s*%([\"'](.-)[\"']%)")
						chatMessage("Внимание! Доступно обновление {32B4FF}v. "..versStr..'{ffffff}.')
						chatMessage("Для перехода на страницу скрипта используйте меню {32B4FF}/pdradio{ffffff}.")
					end
				end
			end
		end
	)
end



function mainMenu()
	local text = string.format(
		"Скрипт:\t%s\n".. -- 0
		"Проверка обновлений\t%s\n".. -- 1
		"Громкость {FF4400}вызовов 911:\t{FFFFFF}%s\n".. -- 2
		"Громкость {ABCDEF}/find:\t{FFFFFF}%s\n".. -- 3
		"Громкость {8D8DFF}/r:\t{FFFFFF}%s\n".. -- 4
		"Громкость {66DDAA}user-эвентов:\t{FFFFFF}%s\n".. -- 5
		"  \n".. -- 6
		"Отключение {66DDAA}user-эвентов\n".. -- 7
		"Проверка паттерна\n".. -- 8
		"  \n".. -- 9
		"Страница скрипта", -- 10

		(INI.INI.state and "{21C90E}Вкл." or '{C91A14}Откл.'),
		(INI.INI.isCheckUpdates and "{21C90E}Вкл." or '{C91A14}Откл.'),
		(INI.INI.callsVolume == 0 and "{C91A14}Откл." or INI.INI.callsVolume), 
		(INI.INI.findVolume == 0 and "{C91A14}Откл." or INI.INI.findVolume),
		(INI.INI.radioVolume == 0 and "{C91A14}Откл." or INI.INI.radioVolume),
		(INI.INI.userVolume == 0 and "{C91A14}Откл." or INI.INI.userVolume)
	)
	sampShowDialog(20000, "Настройки - Police Dispatch v"..thisScript().version.." | "..CFG.name, text, BTN1, BTN2, 4)
end

function checkDialogsRespond()
	-- Находится в main() while true do
	local result, button, list, _ = sampHasDialogRespond(20000)
	if result and button == 1 then
		listMainMenu = list
		if list == 0 then
			INI.INI.state = not INI.INI.state
			inicfg.save(INI, "PoliceDispatchConfig/config.ini")
			mainMenu()
		elseif list == 1 then
			INI.INI.isCheckUpdates = not INI.INI.isCheckUpdates
			inicfg.save(INI, "PoliceDispatchConfig/config.ini")
			mainMenu()
		elseif list == 2 then
			sampShowDialog(20001, "Громкость {FF4400}вызовов 911:", "Если вы хотите отключить озвучку, введите 0.", 
				BTN1, BTN2, 1)
		elseif list == 3 then
			sampShowDialog(20001, "Громкость {ABCDEF}/find:", "Если вы хотите отключить озвучку, введите 0.", 
				BTN1, BTN2, 1)
		elseif list == 4 then
			sampShowDialog(20001, "Громкость {8D8DFF}/r:", "Если вы хотите отключить озвучку, введите 0.", 
				BTN1, BTN2, 1)
		elseif list == 5 then
			sampShowDialog(20001, "Громкость {66DDAA}user-эвентов:", "Если вы хотите отключить озвучку, введите 0.", 
				BTN1, BTN2, 1)
		elseif list == 6 then
			mainMenu()
		elseif list == 7 then
			local userEvents = ""
			for i, it in ipairs(INI[CFG.name.."_UserEvents"]) do
				userEvents = userEvents .. CFG.user[i].name.."\t"..(it and "{21C90E}Вкл." or "{C91A14}Откл.").."\n"
			end
			if userEvent == "" then
				chatMessage("User-эвентов не найдено!")
				mainMenu()
			else
				sampShowDialog(20002, "Отключение user-эвентов", userEvents,
					BTN1, BTN2, 4)
			end
		elseif list == 8 then
			sampShowDialog(20003, "Проверка паттерна", "Введите нужную строку из чата для проверки и воспроизведения:",
				BTN1, BTN2, 1)
		elseif list == 9 then
			mainMenu()
		elseif list == 10 then
			os.execute("start https://"..thisScript().url)
		end
	end

	-- Громкость
	local result, button, _, input = sampHasDialogRespond(20001)
	if result and button == 1 then
		if not tonumber(input) or tonumber(input) < 0 then
			chatMessage("Громкость должно быть числом большим или равным нулю.")
		else
			input = tonumber(input)
			if listMainMenu == 2 then INI.INI.callsVolume = input
			elseif listMainMenu == 3 then INI.INI.findVolume = input
			elseif listMainMenu == 4 then INI.INI.radioVolume = input
			elseif listMainMenu == 5 then INI.INI.userVolume = input end
			inicfg.save(INI, "PoliceDispatchConfig/config.ini")
		end
		mainMenu()
	elseif result then
		mainMenu()
	end

	-- Отключение user эвентов
	local result, button, list, _ = sampHasDialogRespond(20002)
	if result and button == 1 then
		local key = CFG.name.."_UserEvents"
		INI[key][list+1] = not INI[key][list+1]
		inicfg.save(INI, "PoliceDispatchConfig/config.ini")

		local userEvents = ""
		for i, it in ipairs(INI[CFG.name.."_UserEvents"]) do
			userEvents = userEvents .. CFG.user[i].name.."\t"..(it and "{21C90E}Вкл." or "{C91A14}Откл.").."\n"
		end
		sampShowDialog(20002, "Отключение user-эвентов", userEvents,
			BTN1, BTN2, 4)
	elseif result then
		mainMenu()
	end

	-- Проверка строки
	local result, button, _, input = sampHasDialogRespond(20003)
	if result and button == 1 then
		local h, s = handleEvent(input)
		if h == false and s == 'not ev' then
			chatMessage("Эвент не найден. Возможно вы неправильно ввели строку в config.json или в поле для ввода.")
			chatMessage("Либо, если это user-эвент, он может быть отключен в настройках.")
		elseif h == false and s == 'volume' then
			chatMessage("Эвент, который вы пытаетесь воспроизвести, отключен.")
		elseif h == false then
			chatMessage("При проверки строки произошла ошибка. Подробнее в moonloader.log.")
		elseif h == true then
			chatMessage("Ваша строка содержала мало данных, поэтому сохранена до следующего эвента.")
			chatMessage("Примечание: как только придет новая строка в чате, данные обнуляться.")
		else
			chatMessage("Кажется, все прошло успешно.")
		end
	elseif result then
		mainMenu()
	end
end

function chatMessage(text)
	return sampAddChatMessage("[Police Disp v"..thisScript().version.."]: {ffffff}"..text, 0xFF3523)
end
-- Спасибо за поддержку youtube.com/c/Brothersincompany <3
-- vk.com/donakslua