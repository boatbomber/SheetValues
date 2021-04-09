--[[
	TypeTransformers are functions that take in a entry of the CSV as a string,
	and then transform it into the desired datatype.
	Note that dict keys in here must be entirely lowercase.
]]

return {
	["string"] = function(v)
		return tostring(v)
	end,
	["number"] = function(v)
		return tonumber(v)
	end,
	["boolean"] = function(v)
		return string.lower(v)=="true" and true or false
	end,
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
	["color3"] = function(v)
		local comps = string.split(v,",")
		return Color3.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0,
		)
	end,
	["brickcolor"] = function(v)
		return BrickColor.new(v)
	end,
	["rgb"] = function(v)
		local comps = string.split(v,",")
		return Color3.fromRGB(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0,
		)
	end,
	["cframe"] = function(v)
		local comps = string.split(v,",")
		return CFrame.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0,
		)
	end,
	["enum"] = function(v)
		local comps = string.split(v,".")
		return Enum[comps[1]][comps[2]]
	end,
	["rect"] = function(v)
		local comps = string.split(v,",")
		return Rect.new(
			tonumber(comps[1]) or 0,
			tonumber(comps[2]) or 0,
			tonumber(comps[3]) or 0,
			tonumber(comps[4]) or 0
		)
	end,
}