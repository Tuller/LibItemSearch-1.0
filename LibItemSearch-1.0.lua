--[[
	ItemSearch
		An item text search engine of some sort
--]]

local Lib = LibStub:NewLibrary('LibItemSearch-1.0', 5)
if not Lib then
  return
else
  Lib.searchTypes = Lib.searchTypes or {}
end


--[[ Locals ]]--

local tonumber, select, split = tonumber, select, strsplit
local function useful(a) -- check if the search has a decent size
  return a and #a > 1
end

local function compare(op, a, b)
  if op == '<=' then
    return a <= b
  end

  if op == '<' then
    return a < b
  end

  if op == '>' then
    return a > b
  end

  if op == '>=' then
    return a >= b
  end

  return a == b
end

local function match(search, ...)
  for i = 1, select('#', ...) do
    local text = select(i, ...)
    if text and text:lower():find(search) then
      return true
    end
  end
  return false
end


--[[ User API ]]--

function Lib:Find(itemLink, search)
	if not useful(search) then
		return true
	end

	if not itemLink then
		return false
	end

  return self:FindUnionSearch(itemLink, split('\124', search:lower()))
end


--[[ Top-Layer Processing ]]--

-- union search: <search>&<search>
function Lib:FindUnionSearch(item, ...)
	for i = 1, select('#', ...) do
		local search = select(i, ...)
		if useful(search) and self:FindIntersectSearch(item, split('\038', search)) then
      return true
		end
	end
end


-- intersect search: <search>|<search>
function Lib:FindIntersectSearch(item, ...)
	for i = 1, select('#', ...) do
		local search = select(i, ...)
		if useful(search) and not self:FindNegatableSearch(item, search) then
        return false
		end
	end
	return true
end


-- negated search: !<search>
function Lib:FindNegatableSearch(item, search)
  local negatedSearch = search:match('^[!~][%s]*(.+)$')
  if negatedSearch then
    return not self:FindTypedSearch(item, negatedSearch)
  end
  return self:FindTypedSearch(item, search, true)
end


--[[
     Search Types:
      easly defined search types

      A typed search object should look like the following:
        {
          string id
            unique identifier for the search type,

          string searchCapture = function isSearch(self, search)
            returns a capture if the given search matches this typed search

          bool isMatch = function findItem(self, itemLink, searchCapture)
            returns true if <itemLink> is in the search defined by <searchCapture>
          }
--]]

function Lib:RegisterTypedSearch(object)
	self.searchTypes[object.id] = object
end

function Lib:GetTypedSearches()
	return pairs(self.searchTypes)
end

function Lib:GetTypedSearch(id)
	return self.searchTypes[id]
end

function Lib:FindTypedSearch(item, search, default)
  if useful(search) then
    local operator, search = search:match('^[%s]*([%>%<%=]*)[%s]*(.*)$')
    if not useful(search) then
      return
    elseif operator == '' then
      operator = nil
    end

    for id, searchType in self:GetTypedSearches() do
      local capture1, capture2, capture3 = searchType:isSearch(operator, search)
      if capture1 then
        if searchType:findItem(item, operator, capture1, capture2, capture3) then
          return true
        end
      end
    end

    return false
  end
  return default
end


--[[ Item name ]]--

Lib:RegisterTypedSearch{
	id = 'itemName',

	isSearch = function(self, operator, search)
		return not operator and search
	end,

	findItem = function(self, item, _, search)
		local name = GetItemInfo(item)
		return match(search, name)
	end
}


--[[ Item type, subtype and equiploc ]]--

Lib:RegisterTypedSearch{
	id = 'itemTypeGeneric',

	isSearch = function(self, operator, search)
		return not operator and search
	end,

	findItem = function(self, item, _, search)
		local type, subType, _, equipSlot = select(6, GetItemInfo(item))
		return match(search, type, subType, _G[equipSlot])
	end
}


--[[ Item quality ]]--

local qualities = {}
for i = 0, #ITEM_QUALITY_COLORS do
  qualities[i] = _G['ITEM_QUALITY' .. i .. '_DESC']:lower()
end

Lib:RegisterTypedSearch{
	id = 'itemQuality',

	isSearch = function(self, _, search)
    for i, name in pairs(qualities) do
      if name:find(search) then
        return i
      end
    end
	end,

	findItem = function(self, link, operator, num)
		local quality = select(3, GetItemInfo(link))
    return compare(operator, quality, num)
	end,
}


--[[ Item level ]]--

Lib:RegisterTypedSearch{
	id = 'itemLevel',

	isSearch = function(self, _, search)
    return tonumber(search)
	end,

	findItem = function(self, link, operator, num)
		local lvl = select(4, GetItemInfo(link))
    if lvl then
      return compare(operator, lvl, num)
    end
	end,
}


--[[ Tooltip keywords ]]--

local tooltipCache = setmetatable({}, {__index = function(t, k) local v = {} t[k] = v return v end})
local tooltipScanner = _G['LibItemSearchTooltipScanner'] or CreateFrame('GameTooltip', 'LibItemSearchTooltipScanner', UIParent, 'GameTooltipTemplate')
tooltipScanner:SetOwner(UIParent, 'ANCHOR_NONE')

local function link_FindSearchInTooltip(itemLink, search)
	--look in the cache for the result
	local itemID = itemLink:match('item:(%d+)')
	local cachedResult = tooltipCache[search][itemID]
	if cachedResult ~= nil then
		return cachedResult
	end

	--no match?, pull in the resut from tooltip parsing
	tooltipScanner:SetHyperlink(itemLink)

	local result = false
	if tooltipScanner:NumLines() > 1 and _G[tooltipScanner:GetName() .. 'TextLeft2']:GetText() == search then
		result = true
	elseif tooltipScanner:NumLines() > 2 and _G[tooltipScanner:GetName() .. 'TextLeft3']:GetText() == search then
		result = true
	end

	tooltipCache[search][itemID] = result
	return result
end

Lib:RegisterTypedSearch{
	id = 'tooltip',

	isSearch = function(self, _, search)
		return self.keywords[search]
	end,

	findItem = function(self, itemLink, _, search)
		return search and link_FindSearchInTooltip(itemLink, search)
	end,

	keywords = {
		['boe'] = ITEM_BIND_ON_EQUIP,
		['bop'] = ITEM_BIND_ON_PICKUP,
		['bou'] = ITEM_BIND_ON_USE,
		['quest'] = ITEM_BIND_QUEST,
		['boa'] = ITEM_BIND_TO_BNETACCOUNT
	}
}

Lib:RegisterTypedSearch{
	id = 'tooltipDesc',

	isSearch = function(self, _, search)
		return search and search:match('^tt:(.+)$')
	end,

	findItem = function(self, itemLink, _, search)
		--no match?, pull in the resut from tooltip parsing
		tooltipScanner:SetHyperlink(itemLink)

		local i = 1
		while i <= tooltipScanner:NumLines() do
			local text =  _G[tooltipScanner:GetName() .. 'TextLeft' .. i]:GetText():lower()
			if text and text:find(search) then
				return true
			end
			i = i + 1
		end

		return false
	end,
}


--[[ Equipment sets ]]--

local function IsWardrobeLoaded()
	local name, title, notes, enabled, loadable, reason, security = GetAddOnInfo('Wardrobe')
	return enabled
end

local function findEquipmentSetByName(search)
	local startsWithSearch = '^' .. search
	local partialMatch = nil

	for i = 1, GetNumEquipmentSets() do
		local setName = (GetEquipmentSetInfo(i))
		local lSetName = setName:lower()

		if lSetName == search then
			return setName
		end

		if lSetName:find(startsWithSearch) then
			partialMatch = setName
		end
	end

	-- Wardrobe Support
	if Wardrobe then
		for i, outfit in ipairs( Wardrobe.CurrentConfig.Outfit) do
			local setName = outfit.OutfitName
			local lSetName = setName:lower()

			if lSetName == search then
				return setName
			end

			if lSetName:find(startsWithSearch) then
				partialMatch = setName
			end
		end
	end

	return partialMatch
end

local function isItemInEquipmentSet(itemLink, setName)
	if not setName then
		return false
	end

	local itemIDs = GetEquipmentSetItemIDs(setName)
	if not itemIDs then
		return false
	end

	local itemID = tonumber(itemLink:match('item:(%d+)'))
	for inventoryID, setItemID in pairs(itemIDs) do
		if itemID == setItemID then
			return true
		end
	end

	return false
end

local function isItemInWardrobeSet(itemLink, setName)
	if not Wardrobe then return false end

	local itemName = (GetItemInfo(itemLink))
	for i, outfit in ipairs(Wardrobe.CurrentConfig.Outfit) do
		if outfit.OutfitName == setName then
			for j, item in pairs(outfit.Item) do
				if item and (item.IsSlotUsed == 1) and (item.Name == itemName) then
					return true
				end
			end
		end
	end

	return false
end

Lib:RegisterTypedSearch{
	id = 'equipmentSet',

	isSearch = function(self, _, search)
		return search and search:match('^s:(.+)$')
	end,

	findItem = function(self, itemLink, _, search)
		local setName = findEquipmentSetByName(search)
		if not setName then
			return false
		end

		return isItemInEquipmentSet(itemLink, setName)
			or isItemInWardrobeSet(itemLink, setName)
	end,
}