--!strict
--[=[
    @utils CmdrServiceUtils
]=]

const require = require("../loader").load()

const ServiceBag = require("ServiceBag")

const CmdrServiceUtils = {}

--[=[
    Gets the ServiceBag within Context:GetStore

    @within CmdrServiceUtils
    @param context any
    @returns ServiceBag.ServiceBag
]=]
function CmdrServiceUtils.getServiceBag(context: any): ServiceBag.ServiceBag
	return context:GetStore("ServiceBag").ServiceBag
end

--[=[
    Writes the ServiceBag into the Context's store

    @within CmdrServiceUtils
    @param context any
]=]
function CmdrServiceUtils.writeServiceBagInContext(context: any, serviceBag: ServiceBag.ServiceBag)
	const store = context:GetStore("ServiceBag")
	store.ServiceBag = serviceBag
end

return CmdrServiceUtils
