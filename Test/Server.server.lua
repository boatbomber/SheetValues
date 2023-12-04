local ServerScriptService = game:GetService("ServerScriptService")
local SheetValues = require(ServerScriptService.Packages.SheetValues)

SheetValues.new("1gPkSWrkSdBgGG3_ZAxlffCzSTt5k6cd3vlE5I6nllVo", "0"):andThen(function(SheetManager)
	print(SheetManager.Values)
end)
