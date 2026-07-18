--!strict
--[=[
	Selects the consuming game's profile contract before DataService initializes.
	DataService defaults to `ProfileData`; feature services such as SaveSlotService
	may select a more specialized contract in their own `Init` method.

	@util DataServiceProfile
]=]

const require = require("../../Loader").load()

const ProfileData = require("ProfileData")

export type ProfileDefinition = {
	Template: any,
	Schema: any,
	StoreName: string?,
	StoreVersion: number?,
	SlotDataSchema: any?,
}

const DataServiceProfile = {}

local selectedProfile = ProfileData :: ProfileDefinition
local selectedName = "ProfileData"
local isLocked = false

--[=[
	Selects the profile contract used by DataService in the current realm. This
	must happen before DataService or DataServiceClient initializes.

	@within DataServiceProfile
	@param profileDefinition ProfileDefinition
	@param profileName string
]=]
function DataServiceProfile.Select(profileDefinition: ProfileDefinition, profileName: string)
	assert(type(profileDefinition) == "table", "Bad profileDefinition")
	assert(type(profileDefinition.Template) == "table", "Profile definition must provide Template")
	assert(
		type(profileDefinition.Schema) == "table"
			and type(profileDefinition.Schema.ser) == "function"
			and type(profileDefinition.Schema.des) == "function",
		"Profile definition must provide a Squash Schema"
	)
	assert(type(profileName) == "string" and profileName ~= "", "Bad profileName")

	if isLocked then
		assert(
			selectedProfile == profileDefinition,
			`DataService already initialized with {selectedName}; {profileName} must be selected earlier`
		)
		return
	end

	selectedProfile = profileDefinition
	selectedName = profileName
end

--[=[
	Returns the currently selected profile contract.

	@within DataServiceProfile
	@return ProfileDefinition
]=]
function DataServiceProfile.Get(): ProfileDefinition
	return selectedProfile
end

--[=[
	Returns the name of the selected profile contract.

	@within DataServiceProfile
	@return string
]=]
function DataServiceProfile.GetName(): string
	return selectedName
end

--[=[
	Locks and returns the selected profile contract. DataService and
	DataServiceClient call this during initialization.

	@within DataServiceProfile
	@return ProfileDefinition
]=]
function DataServiceProfile.Lock(): ProfileDefinition
	isLocked = true
	return selectedProfile
end

return DataServiceProfile
