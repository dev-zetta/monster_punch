--MonsterPunch
--Author: Gabriel Max

local Knit = shared.Knit

local GameState = { -- TODO: Duplicated in Controller/Service
    Running = 0,
    Win = 1,
    Failed = 2
}

local GameStateToText = {
    [GameState.Running] = "",
    [GameState.Win] = "You won!",
    [GameState.Failed] = "You lose! Try again!"
}

local GameController = Knit.CreateController {
    Name = "GameController";
}

function GameController:KnitStart()
    local GameService = Knit.GetService("GameService")
    GameService.GameUpdate:Connect(function(...)
        self:OnGameUpdate(...)
    end)
end

function GameController:OnGameUpdate(data)
    local player : Player = game.Players.LocalPlayer
    local topGui : ScreenGui? = player.PlayerGui:FindFirstChild("TopGui")
    if not topGui then
        return
    end

    topGui.Frame.MonstersPassed.Text = string.format("Monsters passed: %i/%i", data.MonstersPassed, data.MonstersLimit)
    topGui.Frame.MonstersKilled.Text = string.format("Monsters killed: %i", data.MonstersKilled)
    topGui.Frame.TimeRemaining.Text = string.format("Time left: %02i:%02i", data.TimeRemaining / 60%60, data.TimeRemaining % 60)
    topGui.Frame.GameState.Text = GameStateToText[data.GameState] or ""

    topGui.Enabled = true
end

return GameController
