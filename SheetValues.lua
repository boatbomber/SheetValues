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
	> docs.google .com/spreadsheets/d/ALPHANUMERIC_SPREADSHEET_ID/edit?usp=sharing

	Copy the big spreadsheet id out of that link, as that's how our system will know what spreadsheet
	to read from. Pass that into `SheetValues.new("SPREADSHEET_ID")` and it will return
	a SheetManager linked to that spreadsheet.

	Your spreadsheet must be structured like this:

	Name              Type              Value       (Recommend that you freeze Row 1)
	SampleValueName   Vector3           10, 2, 6.2
	AnotherValueName  number            0.3
	FlagValueName     boolean           true
	ArrayExampleName  array             firstIndex,secondIndex,thirdIndex
	ArrayExampleName  dictionary        key1=stringvalue,key2=anotherstring,key1=anothaone

	API:
	-------

	function SheetValues.new(SpreadId)
	returns a new SheetManager

	function SheetManager:UpdateValues()
	gets the latest values of the sheet
	(This is called automatically and is only exposed for critical cases)

	function SheetManager:GetValue(ValueName, DefaultValue)
	returns the Value or DefaultValue if the Value doesn't exist
	(This is the same as doing `SheetManager.Values.ValueName or DefaultValue` and only exists for style purposes)

	function SheetManager:Destroy()
	cleans up the SheetManager

	table SheetManager.Values
	dictionary of your values

	number SheetManager.LastUpdated
	Unix timestamp of the last time SheetManager.Values was updated

	string SheetManager.LastSource
	Name of the service used to retrieve the current SheetManager.Values (Google API, Datastore, Datastore Override, MsgService Subscription)
	(Used for debugging)

	RBXScriptSignal SheetManager.Updated(newValues)
	Fires when SheetManager.Values is updated

	Supported value Types (not case sensitive):
	- number
	- boolean
	- array
	- dictionary
	- string
	- Vector3
	- Vector2
	- UDim2
	- UDim

	Example:
	-------
	
	## Example:

	A good use of live updating values is developing a anticheat system.
	You can flip a Punishments FFlag so that you can test various methods and thresholds
	without punishing false positives while you work. Additionally, you can use the
	sheet values to tweak and swap those methods and thresholds without needing to
	restart the servers, allowing you to gather analytics and polish your system with ease.


	local SheetValues = require(script.SheetValues)
	local AnticheatSheet = SheetValues.new("SPREADSHEET_ID")

	local function PunishCheater(Player)
		if AnticheatSheet.Values.PunishmentsDisabled then
			-- Punishments aren't enabled, don't punish
			return
		end
		
		Player:Kick("Cheating")
	end

	local function CheckSpeedCheat(Player)
		if Speeds[Player] > AnticheatSheet.Values.SpeedCheatThreshold then
			SendAnalytics("SpeedTriggered", Speeds[Player])
			PunishCheater(Player)
		end
	end
--]=]

local UPDATE_RATE = 30 -- every X seconds

local HttpService = game:GetService("HttpService")
local DatastoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

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

local SheetValues = {}

function SheetValues.new(SpreadId)

	local UpdateEvent = Instance.new("BindableEvent")

	local SheetManager = {
		Updated = UpdateEvent.Event,

		LastUpdated = 0,
		LastSource = "",
		Values = {},

		_DataStore = DatastoreService:GetDataStore(SpreadId, "SheetValues"),
		_Alive = true,

	}

	function SheetManager:_setValues(csv, timestamp)
		--print("Values Updating!\n  Time:",timestamp,"\n  Values:",values)

		self.LastUpdated = timestamp or self.LastUpdated

		local Values = string.split(csv, "\n")

		local isChanged = false

		for Row, Value in ipairs(Values) do
			if Row == 1 then continue end -- Skip the header row of "Name,Type,Value"

			local Components = string.split(Value, [[","]])
			local Name = string.gsub(Components[1], "^\"","")
			local Type = string.lower(Components[2])
			local Value = string.gsub(Components[3], "\"$","")

			--print("Components:",Name,Type,Value)

			local Transformer = TypeTransformer[Type] or TypeTransformer.string
			local FinalValue = Transformer(Value)

			if self.Values[Name] ~= FinalValue then
				isChanged = true
			end

			self.Values[Name] = FinalValue
		end

		if isChanged then
			UpdateEvent:Fire(self.Values)
		end
	end

	function SheetManager:_getFromHttp()
		-- Attempt to get values from Google's API
		local success, response = pcall(HttpService.RequestAsync, HttpService, {
			Url = string.format("https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv", SpreadId),
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
				local s,e = pcall(MessagingService.PublishAsync, MessagingService, SpreadId, response.Body)
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

	function SheetManager:Destroy()
		if SheetManager._MessageListener then
			SheetManager._MessageListener:Disconnect()
		end
		UpdateEvent:Destroy()
		table.clear(self)
	end

	pcall(function()
		SheetManager._MessageListener = MessagingService:SubscribeAsync(SpreadId, function(Msg)
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
