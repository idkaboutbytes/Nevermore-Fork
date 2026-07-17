--!strict
--[=[
    @utils DataServiceUtils
]=]

const require = require("../../Loader").load()

const StringUtils = require("StringUtils")
const TableUtils = require("TableUtils")
const ObservableMap = require("ObservableMap")
const DefaultValueUtils = require("DefaultValueUtils")

const DataServiceUtils = {}

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
