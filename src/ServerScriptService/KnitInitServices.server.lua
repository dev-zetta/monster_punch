local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
shared.Knit = Knit

Knit.AddServices(game:GetService("ServerStorage").Services)
Knit.Start():andThen(function()
	print("Services loaded ✅")
end):catch(warn)