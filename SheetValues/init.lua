--[=[

	SheetValues by boatbomber

	Using Google Sheets allows you to update your values from your phone, desktop, or tablet.
	It's supported on all devices which makes it a really good "console" for live value editing.
	This system updates every 30 seconds (and that number is configurable within the module).
	This allows you to propagate changes to all your servers really fast. Only one server actually calls the API,
	the rest get it through MessagingService or DatastoreService. This keeps your HttpService
	usage down to a minimum, and keeps Google from being annoyed at us.


	Setup:
	-------

	Getting started is really easy. Gone are the days of API keys and custom sheet macro scripts.
	All you need is the share link, set to "Anyone on the internet with this link can view". Copy that link.

	The link will look something like this:
	> docs.google .com/spreadsheets/d/ALPHANUMERIC_SPREAD_ID/edit?usp=sharing

	Copy the big spread id out of that link, as that's how our system will know what spread to read from.

	If you're using multiple sheets in a single spread, the SheetId will be at the end of the main url. Look for "#gid=" and
	copy everything after the equals symbol.
	> docs.google .com/spreadsheets/d/ALPHANUMERIC_SPREAD_ID/edit#gid=NUMERIC_SHEET_ID

	Pass that into `SheetValues.new("ALPHANUMERIC_SPREAD_ID", "NUMERIC_SHEET_ID")` and it will return
	a SheetManager linked to that sheet. Note that the SheetId parameter is optional and will default to
	the first (or only) sheet in your spread.

	Your sheet structure is not strictly enforced, but it is STRONGLY recommended that you have a Name column so
	that it can key your values by Name rather than Row number, making it much easier to work with.

	If you have a boolean or number property, it will attempt to convert the string into your intended datatype.
	To create special types, you can explicitly mark them by having the property be "Type(val)", like "Vector3(1,0,3)"

	Supported explicit property Types (not case sensitive):
	- string (for ensuring a number/boolean remains a string)
	- array
	- dictionary
	- Vector3
	- Vector2
	- UDim2
	- UDim

	Sample Sheet:

	Name                Prop                                              SecondaryProp           AnyPropNameYouLike        [Recommend that you freeze Row 1]
	BoostDirection      Vector3(10, 2, 6.2)                               100                     10000
	SpeedMultiplier     0.3 [will autodetect and convert to number]       1                       FALSE
	DebugEnabled        TRUE [will autodetect and convert to boolean]     JSONstring              you get the point
	DontAutodetect      string(TRUE) [will NOT convert to boolean]        TRUE                    you can add as many columns as you need
	ArrayOfStrings      array(firstIndex,secondIndex,thirdIndex)          Vector2(5,2)            and easily set the value type
	DictOfKeyedStrings  dictionary(key1=stringvalue,key2=anotherstring)   UDim2(0.3,-10,0,350)    it's great!

	API:
	-------

	function SheetValues.new(SpreadId: string [, SheetId: string])
	returns a new SheetManager

	function SheetManager:UpdateValues()
	gets the latest values of the sheet
	(This is called automatically and is only exposed for critical cases)

	function SheetManager:GetValue(ValueName: string, DefaultValue: any)
	returns the Value or DefaultValue if the Value doesn't exist
	(This is the same as doing `SheetManager.Values.ValueName or DefaultValue` and only exists for style purposes)

	function SheetManager:GetValueChangedSignal(ValueName: string)
	returns a RBXScriptSignal that fires when the given Value changes, passing two arguements in the fired event (NewValue, OldValue)

	function SheetManager:Destroy()
	cleans up the SheetManager

	table SheetManager.Values
	dictionary of your values

	number SheetManager.LastUpdated
	Unix timestamp of the last time SheetManager.Values was updated

	string SheetManager.LastSource
	Name of the service used to retrieve the current SheetManager.Values (Google API, Datastore, Datastore Override, MsgService Subscription)
	(Used for debugging)

	RBXScriptSignal SheetManager.Changed(NewValues: table)
	Fires when SheetManager.Values is changed

	Example:
	-------

	A good use of these live updating values is developing a anticheat system.
	You can flip a have a Value with a property like PunishmentsEnabled so that you can
	test various methods and thresholds without punishing false positives while you work.
	Additionally, you can add properties to that Value for thresholds and cheat parameters,
	so you can fine tune your system without needing to restart the game servers, allowing
	you to gather analytics and polish your system with ease.

	Sheet used by the Example Code:

	Name                        PunishmentEnabled      Threshold
	SheetCheat                  FALSE                  35

	local SheetValues = require(script.SheetValues)
	local AnticheatSheet = SheetValues.new("SPREADSHEET_ID")

	local function PunishCheater(Player)
		if not AnticheatSheet.Values.SpeedCheat.PunishmentEnabled then
			-- Punishments aren't enabled, don't punish
			return
		end

		Player:Kick("Cheating")
	end

	local function CheckSpeedCheat(Player)
		if Speeds[Player] > AnticheatSheet.Values.SpeedCheat.Threshold then
			SendAnalytics("SpeedTriggered", Speeds[Player])
			PunishCheater(Player)
		end
	end
--]=]

local UPDATE_RATE = 30 -- every X seconds

local HttpService = game:GetService("HttpService")
local DatastoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

local SHA1 = require(script.SHA1)

local TypeTransformer = {
	["array"] = function(v)
		return string.split(v,",")
	end,
	["dictionary"] = function(v)
		local values = string.split(v,",")
		local dict = table.create(#values)

		for _,value in ipairs(values) do
			local components = string.split(value,"=")
			dict[string.gsub(string.gsub(components[1],"^ ","")," $","")] = string.gsub(components[2],"^ ","")
		end

		return dict
	end,
	["number"] = function(v)
		return tonumber(v)
	end,
	["boolean"] = function(v)
		return string.lower(v)=="true" and true or false
	end,
	["string"] = function(v)
		return tostring(v)
	end,
	["vector3"] = function(v)
		local comps = string.split(v,",")
		return Vector3.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0
		)
	end,
	["vector2"] = function(v)
		local comps = string.split(v,",")
		return Vector2.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0
		)
	end,
	["udim2"] = function(v)
		local comps = string.split(v,",")
		return UDim2.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0,
			tonumber(comps[4]) or 0
		)
	end,
	["udim"] = function(v)
		local comps = string.split(v,",")
		return UDim.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0
		)
	end,
}

local function ConvertTyped(Input)
	local lowerInput = string.lower(Input)

	-- Check if it's explicitly a string first
	if string.match(lowerInput, "^string%(") then
		return string.gsub(string.sub(lowerInput, 8), "%)$","")
	end

	-- Check for boolean input
	if lowerInput == "true" or lowerInput == "false" then
		return lowerInput == "true"
	end

	-- Check for number input
	local n = tonumber(Input)
	if tostring(n) == Input then
		return n
	end

	-- Check for explicitly typed (ex: "Vector3(1,1,1)", "UDim2(0,100,0,80)")
	for Type, Transformer in pairs(TypeTransformer) do
		local Pattern = "^"..Type.."%("
		if string.match(lowerInput, Pattern) then
			local trimInput = string.gsub(string.sub(Input, #Pattern-1), "%)$","")
			return Transformer(trimInput)
		end
	end

	return Input
end

local function DictEquals(a, b)
	if type(a) ~= type(b) then return false end

	for k, v in pairs(a) do
		if (type(v)=="table") and (not DictEquals(b[k], v)) then
			return false
		end
		if (b[k] ~= v) then
			return false
		end
	end

	for k, v in pairs(b) do
		if (type(v)=="table") and (not DictEquals(a[k], v)) then
			return false
		end
		if (a[k] ~= v) then
			return false
		end
	end

	return true
end

local SheetValues = {}

function SheetValues.new(SpreadId: string, SheetId: string?)
	assert(type(SpreadId)=="string", "Invalid SpreadId")

	-- Default SheetId to 0 as that's Google's default SheetId
	SheetId = (SheetId or "0")

	local GUID = SHA1(SpreadId.."||"..SheetId)

	local ChangedEvent = Instance.new("BindableEvent")

	local SheetManager = {
		Changed = ChangedEvent.Event,

		LastUpdated = 0,
		LastSource = "",
		Values = {},

		_ValueChangeEvents = {},
		_DataStore = DatastoreService:GetDataStore(GUID, "SheetValues"),
		_Alive = true,
	}

	function SheetManager:_setValues(csv: string, timestamp: number)
		--print("Time:",timestamp,"\nCSV:\n"..csv)

		self.LastUpdated = timestamp or self.LastUpdated

		local Rows = string.split(csv, "\n")
		--print("CSV Split:",Rows)

		local isChanged = false

		local ColumnToKey = table.create(3)

		for Row, RawValue in ipairs(Rows) do
			local Components = string.split(RawValue, [[","]])
			-- Trim the trailing " chars
			Components[1] = string.gsub(Components[1], "^\"","")
			Components[#Components] = string.gsub(Components[#Components], "\"$","")

			if Row == 1 then
				-- Parse out the keys from the header row
				for i, Comp in ipairs(Components) do
					ColumnToKey[i] = Comp
				end
				continue
			end

			-- Parse the typed values into dictionary based on the header row keys
			local Value = table.create(#Components)
			for i, Comp in ipairs(Components) do
				Value[ColumnToKey[i]] = ConvertTyped(Comp)
			end

			local Name = Value.Name or Value.name or string.format("%d", Row) -- Index by name, or by row if no names exist
			local OldValue = self.Values[Name]

			if not DictEquals(OldValue, Value) then
				isChanged = true

				self.Values[Name] = Value

				local ValueChangeEvent = self._ValueChangeEvents[Name]
				if ValueChangeEvent then
					ValueChangeEvent:Fire(Value,OldValue)
				end
			end

		end

		if isChanged then
			ChangedEvent:Fire(self.Values)
		end
	end

	function SheetManager:_getFromHttp()
		-- Attempt to get values from Google's API
		local success, response = pcall(HttpService.RequestAsync, HttpService, {
			Url = string.format("https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv%headers=1&gid=%s", SpreadId, SheetId),
			Method = "GET",
			Headers = {},
		})

		if success then
			-- http request went through, decode and handle it
			if response.Success then
				-- request success, set these values

				local now = DateTime.now().UnixTimestamp

				self.LastSource =  "Google API"
				self:_setValues(response.Body, now)


				-- Put these new values into the store
				local s,e = pcall(self._DataStore.UpdateAsync, self._DataStore, "CSV", function(storeValues)
					storeValues = storeValues or table.create(2)

					if now <= (storeValues.Timestamp or 0) then
						-- The store is actually more recent than us, use it instead
						self.LastSource =  "Datastore Override"
						self:_setValues(storeValues.CSV, storeValues.Timestamp)
						return storeValues
					end

					storeValues.Timestamp = now
					storeValues.CSV = response.Body

					return storeValues
				end)
				if not s then warn(e) end

				-- Send these values to all other servers
				local s,e = pcall(MessagingService.PublishAsync, MessagingService, GUID, response.Body)
				if not s then warn(e) end

				return true, "Values updated"
			else
				-- API failure
				return false, response.StatusCode
			end
		else
			-- Http failure
			return false, response
		end
		--]=]
	end

	function SheetManager:_getFromStore()
		-- Attempt to get values from store
		local success, response = pcall(self._DataStore.GetAsync, self._DataStore, "CSV")
		if not success then
			-- Store failure
			return false, response
		end

		if not response then
			return false, "Cache doesn't exist"
		end

		local cacheTimestamp = response.Timestamp or 0
		local now = DateTime.now().UnixTimestamp

		if now - cacheTimestamp >= UPDATE_RATE then
			return false, "Cache expired"
		end
		if cacheTimestamp <= self.LastUpdated then
			return true, "Values up to date"
		end

		-- set these values
		self.LastSource =  "Datastore"
		self:_setValues(response.CSV, cacheTimestamp)

		return true, "Values updated"
	end

	function SheetManager:UpdateValues()

		-- Get values from DataStore cache
		local storeSuccess, storeResult = self:_getFromStore()
		--print(storeSuccess,storeResult)

		-- Get successful, update complete
		if storeSuccess then return end

		-- Store values too old, get from http and update/share
		if storeResult == "Cache expired" or storeResult == "Cache doesn't exist"  then
			local httpSuccess, httpResult = self:_getFromHttp()
			--print(httpSuccess,httpResult)
		end
	end

	function SheetManager:GetValue(Name: string, Default: any)
		return self.Values[Name] or Default
	end

	function SheetManager:GetValueChangedSignal(Name: string)
		local ValueChangeEvent = self._ValueChangeEvents[Name]
		if not ValueChangeEvent then
			ValueChangeEvent = Instance.new("BindableEvent")
			self._ValueChangeEvents[Name] = ValueChangeEvent
		end

		return ValueChangeEvent.Event
	end

	function SheetManager:Destroy()
		if SheetManager._MessageListener then
			SheetManager._MessageListener:Disconnect()
		end

		ChangedEvent:Destroy()
		for _,Event in pairs(self._ValueChangeEvents) do
			Event:Destroy()
		end

		table.clear(self)
	end

	pcall(function()
		SheetManager._MessageListener = MessagingService:SubscribeAsync(GUID, function(Msg)
			if math.floor(Msg.Sent) > SheetManager.LastUpdated then
				SheetManager.LastSource =  "MsgService Subscription"
				SheetManager:_setValues(Msg.Data, math.floor(Msg.Sent))
			end
		end)
	end)

	coroutine.wrap(function()
		while SheetManager._Alive do
			wait(UPDATE_RATE)
			SheetManager:UpdateValues()
		end
	end)()

	SheetManager:UpdateValues()

	return SheetManager

end


return SheetValues
