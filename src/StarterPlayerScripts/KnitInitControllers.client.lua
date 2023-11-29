local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
shared.Knit = Knit

Knit.AddControllers(script.Parent:WaitForChild("Controllers"))
Knit.Start({
	ServicePromises = false
}):andThen(function()
	print("Controllers loaded ✅")
end):catch(warn)