--!strict
--[=[
    @utils DataServiceUtils
]=]

const require = require("../../Loader").load()

const StringUtils = require("StringUtils")
const TableUtils = require("TableUtils")
const ObservableMap = require("ObservableMap")
const DefaultValueUtils = require("DefaultValueUtils")
const ProfileData = require("ProfileData")

const SETTINGS_KEY = "Settings"

const DataServiceUtils = {}

const SETTINGS_TEMPLATE: { [string]: any } = {}
do
	-- rawget, because a game whose profile has no Settings key at all would
	-- otherwise throw here at require time
	const settings = rawget(ProfileData.Template :: any, SETTINGS_KEY)

	if type(settings) == "table" then
		for name, default in settings do
			SETTINGS_TEMPLATE[name] = default
		end
	end
end

--[=[
    Splits a dot-separated path into its root key and the remaining path, if
    any. The root key is what an ObservableMap of profile data is keyed on; the
    remainder is resolved against that key's value.

    @within DataServiceUtils
    @param path string
    @return (string, string?)
]=]
function DataServiceUtils.splitValuePath(path: string): (string, string?)
	const parts = StringUtils.split(path, ".")

	if #parts == 1 then
		return parts[1], nil
	end

	return parts[1], table.concat(parts, ".", 2)
end

--[=[
	Returns whether two data paths overlap as an ancestor, descendant, or exact
	match. Segment boundaries are respected, so `Inventory.Item` does not overlap
	`Inventory.Items`.

	@within DataServiceUtils
	@param left string
	@param right string
	@return boolean
]=]
function DataServiceUtils.valuePathsOverlap(left: string, right: string): boolean
	assert(type(left) == "string" and left ~= "", "Bad left")
	assert(type(right) == "string" and right ~= "", "Bad right")

	return left == right
		or string.sub(left, 1, #right + 1) == right .. "."
		or string.sub(right, 1, #left + 1) == left .. "."
end

--[=[
    Reads a value out of an ObservableMap of profile data using a dot-separated
    path, descending into the root key's value for nested paths.

    @within DataServiceUtils
    @param map ObservableMap<string, any>
    @param path string
    @return any
]=]
function DataServiceUtils.readObservableValuePath(map: ObservableMap.ObservableMap<string, any>, path: string): any
	const rootKey, nestedPath = DataServiceUtils.splitValuePath(path)
	const rootValue = map:Get(rootKey)

	if not nestedPath then
		return rootValue
	end

	return DataServiceUtils.readValuePath(rootValue, nestedPath)
end

--[=[
    Writes a value into an ObservableMap of profile data using a dot-separated
    path. Nested writes copy the root value before mutating it, since the map
    ignores a Set that carries the same reference it already holds.

    @within DataServiceUtils
    @param map ObservableMap<string, any>
    @param path string
    @param value any
]=]
function DataServiceUtils.writeObservableValuePath(
	map: ObservableMap.ObservableMap<string, any>,
	path: string,
	value: any
)
	const rootKey, nestedPath = DataServiceUtils.splitValuePath(path)

	if not nestedPath then
		map:Set(rootKey, value)
		return
	end

	const currentRoot = map:Get(rootKey)
	const newRoot = if type(currentRoot) == "table" then TableUtils.deepCopy(currentRoot) else {}

	DataServiceUtils.writeValuePath(newRoot, nestedPath, value)
	map:Set(rootKey, newRoot)
end

--[=[
    Reads a value from a table using a dot-separated path.

    @within DataServiceUtils
    @param target table
    @param path string
    @return any
]=]
function DataServiceUtils.readValuePath(target: any, path: string): any
	local current = target

	for _, key in StringUtils.split(path, ".") do
		if type(current) ~= "table" then
			return nil
		end

		current = current[key]

		if current == nil then
			return nil
		end
	end

	return current
end

--[=[
    Writes a value to a table using a dot-separated path.
    Missing intermediate tables are created automatically.

    @within DataServiceUtils
    @param target table
    @param path string
    @param value any
    @return any
]=]
function DataServiceUtils.writeValuePath(target: any, path: string, value: any): any
	local current = target
	const parts = StringUtils.split(path, ".")

	for i = 1, #parts - 1 do
		local key = parts[i]

		assert(type(current) == "table", ("Invalid path '%s'"):format(path))

		if current[key] == nil then
			current[key] = {}
		end

		assert(type(current[key]) == "table", ("Invalid path '%s'"):format(path))

		current = current[key]
	end

	current[parts[#parts]] = value
	return value
end

--[=[
    Returns the profile root key settings are stored under.

    @within DataServiceUtils
    @return string
]=]
function DataServiceUtils.getSettingsKey(): string
	return SETTINGS_KEY
end

--[=[
    Returns the profile path a setting is stored at.

    @within DataServiceUtils
    @param name string
    @return string
]=]
function DataServiceUtils.getSettingPath(name: string): string
	return `{SETTINGS_KEY}.{name}`
end

--[=[
    Returns every setting name the profile template declares.

    @within DataServiceUtils
    @return { string }
]=]
function DataServiceUtils.getSettingNames(): { string }
	const names = {}

	for name in SETTINGS_TEMPLATE do
		table.insert(names, name)
	end

	return names
end

--[=[
    Returns whether a name is a setting, meaning a key of the profile template's
    Settings table. Gates reads -- see [DataServiceUtils.isWritableSettingName]
    for whether a client may also write it.

    @within DataServiceUtils
    @param name string
    @return boolean
]=]
function DataServiceUtils.isSettingName(name: string): boolean
	if type(name) ~= "string" then
		return false
	end

	return SETTINGS_TEMPLATE[name] ~= nil
end

--[=[
    Returns whether a client may write a setting: a key of the template whose
    default is a primitive.

    Table-valued settings are excluded deliberately. Validity is inferred from the
    default's type, and a type check cannot say anything about a table's shape --
    a wrong-shaped table written into a profile makes the next `Schema.ser` throw,
    which kills that player's whole profile buffer on every future join. Table
    settings stay server-only, through [DataService.SetValue].

    @within DataServiceUtils
    @param name string
    @return boolean
]=]
function DataServiceUtils.isWritableSettingName(name: string): boolean
	if not DataServiceUtils.isSettingName(name) then
		return false
	end

	-- type rather than typeof throughout: writable settings are primitives, which
	-- the two agree on, and a Roblox datatype reads as "userdata" here, so it
	-- fails the whitelist rather than being mistaken for a primitive
	const defaultType = type(SETTINGS_TEMPLATE[name])

	return defaultType == "boolean" or defaultType == "string" or defaultType == "number"
end

--[=[
    Returns whether a value may be written to a setting: the same type as the
    template's default for it, and a real number if numeric.

    @within DataServiceUtils
    @param name string
    @param value any
    @return boolean
]=]
function DataServiceUtils.isValidSettingValue(name: string, value: any): boolean
	if not DataServiceUtils.isWritableSettingName(name) then
		return false
	end

	const valueType = type(value)
	if valueType ~= type(SETTINGS_TEMPLATE[name]) then
		return false
	end

	if valueType == "number" then
		-- NaN and the infinities are all numbers to a type check, and all three
		-- would break the profile's serializer
		return value == value and value ~= math.huge and value ~= -math.huge
	end

	return true
end

--[=[
    Returns a copy of profile data safe to send to the client, with every hidden
    key blanked to its default value.

    The values are blanked rather than removed because the payload is serialized
    against a fixed schema, which has no way to express an absent key. The client
    is sent the hidden key list alongside and drops them on arrival.

    @within DataServiceUtils
    @param data table
    @param hiddenKeys { string }
    @return table
]=]
function DataServiceUtils.getReplicatedData(data: any, hiddenKeys: { string }): any
	if #hiddenKeys == 0 then
		return data
	end

	const replicated = TableUtils.deepCopy(data)
	for _, keyName in hiddenKeys do
		const currentValue = DataServiceUtils.readValuePath(replicated, keyName)
		if currentValue == nil then
			continue
		end

		const success, defaultValue = pcall(DefaultValueUtils.toDefaultValue, currentValue)
		if not success then
			warn(`[DataServiceUtils] - Cannot blank hidden key {keyName} ({defaultValue}), it will replicate as-is`)
			continue
		end

		DataServiceUtils.writeValuePath(replicated, keyName, defaultValue)
	end

	return replicated
end

--[=[
    Returns the root keys whose value differs between two profile data tables,
    removals included.

    Replication is done a whole root key at a time because a dot-separated path
    cannot express a removal either: the client would never hear that an entry
    left an array. Sending the root wholesale costs bandwidth but cannot desync.

    @within DataServiceUtils
    @param oldData table
    @param newData table
    @return { string }
]=]
function DataServiceUtils.getChangedRootKeys(oldData: any, newData: any): { string }
	const changed = {}

	for key, newValue in newData do
		if not TableUtils.deepEquivalent(oldData[key], newValue) then
			table.insert(changed, key)
		end
	end

	for key in oldData do
		if newData[key] == nil then
			table.insert(changed, key)
		end
	end

	return changed
end

--[=[
	Returns changed values as dot-separated paths.

	@param oldData table
	@param newData table
	@param prefix string?
	@return table
]=]
function DataServiceUtils.deepDiffPaths(oldData: any, newData: any, prefix: string?): { [string]: any }
	const changes = {}

	for key, newValue in newData do
		const path = if prefix then prefix .. "." .. key else key
		const oldValue = oldData[key]

		if type(newValue) == "table" and type(oldValue) == "table" then
			const nestedChanges = DataServiceUtils.deepDiffPaths(oldValue, newValue, path)

			for nestedKey, nestedValue in nestedChanges do
				changes[nestedKey] = nestedValue
			end
		elseif oldValue ~= newValue then
			changes[path] = newValue
		end
	end

	return changes
end

return DataServiceUtils
