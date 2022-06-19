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

	What should your Google Sheet look like?
	Well, rows are turned into Values with each column entry being a Property of the Value.
	Here's the structure:
	The first row of the Sheet is the Header. This row will NOT become a Value, rather it defines how we parse
	the subsequent rows into Values. Each entry into row 1 becomes the key for that column (Property).

	Example:
	Name          PropertyName     AnotherProp
	TestValue     100              true
	NextValue     300              false

	This results in two Values being stored and structured like so:
	SheetManager.Values = {
		["TestValue"] = {
			PropertyName = 100,
			AnotherProp = true
		},
		["NextValue"] = {
			PropertyName = 300,
			AnotherProp = false
		},
	}

	It's not strictly enforced, but it is STRONGLY recommended that you have a "Name" Property so
	that it will index your values by Name (will use row number if no Name prop exists), as it is much
	easier to for you to work with.

	SheetValues will attempt to convert the string in each cell into your intended datatype, using familiar Lua syntax.
	Numbers and booleans are written plainly, strings are wrapped in quotes, and tables are wrapped in {}.
	Special Roblox types are written as Type.new(...), to align with their Luau counterparts.
	It will default back to string if it cannot figure out a type, but it is recommended to explicilty write
	your strings in "quotes" to avoid relying on this.

	Supported property Types:
	- string
	- array
	- dictionary
	- Vector3
	- Vector2
	- UDim2
	- UDim
	- Color3 (0-1)
	- RGB (0-255)
	- BrickColor
	- CFrame
	- Enum
	- Rect

	Sample Sheet:

	Name                Prop                                              SecondaryProp               AnyPropNameYouLike        [Recommend that you freeze Row 1]
	BoostDirection      Vector3.new(10, 2, 6.2)                           100                         10000
	SpeedMultiplier     0.3 [will autodetect and convert to number]       1                           FALSE
	DebugEnabled        TRUE [will autodetect and convert to boolean]     "JSONstring"                "you get the point"
	DontAutodetect      "TRUE" [will NOT convert to boolean]       	      TRUE                        "you can add as many columns as you need"
	ArrayOfNumbers      {1, 2, 3}                                         Vector2.new(5,2)            "and easily set the value type"
	DictOfStrings       {Foo = "hello", Bar = "world"}                    UDim2.new(0.3,-10,0,350)    "it's great!"

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
	returns a RBXScriptSignal that fires when the given Value changes, passing two arguments in the fired event (NewValue, OldValue)

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
	You can create Values with properties like PunishmentsEnabled so that you can
	test various methods and thresholds without punishing false positives while you work.
	Additionally, you can add properties to the Values for thresholds and cheat parameters,
	so you can fine tune your system without needing to restart the game servers, allowing
	you to gather analytics and polish your system with ease.

	Sheet used by the Example Code:

	Name                        PunishmentEnabled      Threshold
	SpeedCheat                  FALSE                  35

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
local TypeTransformer = require(script.TypeTransformer)

local function ConvertTyped(Input)
	if type(Input) ~= "string" then
		-- Already typed
		return Input
	end

	local lowerInput = string.lower(Input)

	-- Check if explicitly string
	if string.match(lowerInput, "^[\"']") and string.match(lowerInput, "[\"']$") then
		return string.sub(Input, 2, #Input - 1)
	end

	-- Check if boolean
	if lowerInput == "true" or lowerInput == "false" then
		return lowerInput == "true"
	end

	-- Check if number
	local n = tonumber(Input)
	if tostring(n) == Input then
		return n
	end

	-- Check if table
	if string.match(lowerInput, "^{") and string.match(lowerInput, "}$") then
		local output = {}

		-- TODO: Instead of splitting by commas, parse it yourself so that Vector3(1,1,1) doesn't cause 2 incorrect splits
		local keyvalues = string.split(string.sub(Input, 2, #Input - 1), ",")
		for i, keyvalue in ipairs(keyvalues) do
			-- Remove leading whitespace
			keyvalue = string.gsub(keyvalue, "^ ", "")

			-- Check if dictionary
			local key, value = string.match(keyvalue, "(%w+)%s*=%s*(.+)")
			if key and value then
				output[key] = ConvertTyped(value)
				continue
			end

			-- Default to array
			output[i] = ConvertTyped(keyvalue)
		end

		return output
	end

	-- Check if explicitly typed (ex: "Vector3.new(1,1,1)", "UDim2.new(0,100,0,80)")
	local Type, Value = string.match(Input, "^(%w+)%.?[new]*%((.-)%)$")
	if Type and Value then
		local Transformer = TypeTransformer[string.lower(Type)]
		if Transformer then
			return Transformer(Value)
		end
	end

	-- Fallback to string
	return Input
end

local function DictEquals(a, b)
	if type(a) ~= type(b) then
		return false
	end

	for k, v in pairs(a) do
		if (type(v) == "table") and (not DictEquals(b[k], v)) then
			return false
		end
		if b[k] ~= v then
			return false
		end
	end

	for k, v in pairs(b) do
		if (type(v) == "table") and (not DictEquals(a[k], v)) then
			return false
		end
		if a[k] ~= v then
			return false
		end
	end

	return true
end

local SheetValues = {}

function SheetValues.new(SpreadId: string, SheetId: string?)
	assert(type(SpreadId) == "string", "Invalid SpreadId")

	-- Default SheetId to 0 as that's Google's default SheetId
	SheetId = (SheetId or "0")

	local GUID = SHA1(SpreadId .. "||" .. SheetId)

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

	function SheetManager:_setValues(json: string, timestamp: number)
		local decodeSuccess, sheet = pcall(HttpService.JSONDecode, HttpService, json)
		if not decodeSuccess then
			return
		end
		if sheet.status ~= "ok" then
			return
		end

		--print("Time:", timestamp, "\nJSON:", sheet)

		self.LastUpdated = timestamp or self.LastUpdated

		local isChanged = false

		for Row, RowValue in ipairs(sheet.table.rows) do
			-- Parse the typed values into dictionary based on the header row keys
			local Value = table.create(#RowValue.c)
			for i, Comp in ipairs(RowValue.c) do
				local key = sheet.table.cols[i].label
				if not key or key == "" then
					continue
				end

				Value[key] = ConvertTyped(if Comp.v ~= nil then Comp.v else "")
			end

			local Name = Value.Name or Value.name or string.format("%d", Row) -- Index by name, or by row if no names exist
			local OldValue = self.Values[Name]

			if not DictEquals(OldValue, Value) then
				isChanged = true

				self.Values[Name] = Value

				local ValueChangeEvent = self._ValueChangeEvents[Name]
				if ValueChangeEvent then
					ValueChangeEvent:Fire(Value, OldValue)
				end
			end
		end

		if isChanged then
			ChangedEvent:Fire(self.Values)
		end
	end

	function SheetManager:_getFromHttp()
		-- Attempt to get values from Google's API
		local httpSuccess, httpResponse = pcall(HttpService.RequestAsync, HttpService, {
			Url = string.format(
				"https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:json&headers=1&gid=%s",
				SpreadId,
				SheetId
			),
			Method = "GET",
			Headers = {},
		})

		if not httpSuccess then
			-- Http failure
			return false, httpResponse
		end

		if not httpResponse.Success then
			-- API failure
			return false, httpResponse.StatusCode
		end

		-- Request successful, now set these values

		local now = DateTime.now().UnixTimestamp
		local json = string.match(httpResponse.Body, "{.+}")

		self.LastSource = "Google API"
		self:_setValues(json, now)

		-- Put these new values into the store
		local datastoreSuccess, datastoreResponse = pcall(
			self._DataStore.UpdateAsync,
			self._DataStore,
			"JSON",
			function(storeValues)
				storeValues = storeValues or table.create(2)

				if now <= (storeValues.Timestamp or 0) then
					-- The store is actually more recent than us, use it instead
					self.LastSource = "Datastore Override"
					self:_setValues(storeValues.JSON, storeValues.Timestamp)
					return storeValues
				end

				storeValues.Timestamp = now
				storeValues.JSON = json

				return storeValues
			end
		)
		--if not datastoreSuccess then warn(datastoreResponse) end

		-- Send these values to all other servers
		if self.LastSource == "Google API" then
			local msgSuccess, msgResponse = pcall(
				MessagingService.PublishAsync,
				MessagingService,
				GUID,
				#json < 1000 and json or "TriggerStore"
			)
			--if not msgSuccess then warn(msgResponse) end
		end

		return true, "Values updated"
	end

	function SheetManager:_getFromStore()
		-- Attempt to get values from store
		local success, response = pcall(self._DataStore.GetAsync, self._DataStore, "JSON")
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
		self.LastSource = "Datastore"
		self:_setValues(response.JSON, cacheTimestamp)

		return true, "Values updated"
	end

	function SheetManager:UpdateValues()
		-- Get values from DataStore cache
		local storeSuccess, storeResult = self:_getFromStore()
		--print(storeSuccess,storeResult)

		-- Get successful, update complete
		if storeSuccess then
			return
		end

		-- Store values too old or store failed, get from http and update/share
		local httpSuccess, httpResult = self:_getFromHttp()
		--print(httpSuccess,httpResult)
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
		for _, Event in pairs(self._ValueChangeEvents) do
			Event:Destroy()
		end

		table.clear(self)
	end

	pcall(function()
		SheetManager._MessageListener = MessagingService:SubscribeAsync(GUID, function(Msg)
			local msgTimestamp = math.floor(Msg.Sent)
			if msgTimestamp <= SheetManager.LastUpdated then
				-- Ignore outdated data
				return
			end

			local json = Msg.Data
			if json == "TriggerStore" then
				-- Datastore was updated with a file too large to send directly, this is a blank trigger
				local storeSuccess, storeResult = SheetManager:_getFromStore()
			else
				SheetManager.LastSource = "MsgService Subscription"
				SheetManager:_setValues(json, msgTimestamp)
			end
		end)
	end)

	task.defer(function()
		while SheetManager._Alive do
			task.wait(UPDATE_RATE)
			SheetManager:UpdateValues()
		end
	end)

	SheetManager:UpdateValues()

	return SheetManager
end

return SheetValues
