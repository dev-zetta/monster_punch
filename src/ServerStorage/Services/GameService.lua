--MonsterPunch
--Author: Gabriel Max

local Knit = shared.Knit

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MONSTER_TAG = "MONSTER"
local GameDir = workspace.GameLevel

local ASSETS_IN_WORKSPACE = true
if ASSETS_IN_WORKSPACE then
    workspace.Assets.Parent = ServerStorage
end

local AssetsDir = ServerStorage.Assets.Game
--local PlatformDimensions = AssetsDir.Platform:GetE

AssetsDir.Sounds.Parent = ReplicatedStorage.Assets
local SoundsDir = ReplicatedStorage.Assets.Sounds

type PlatformData = {
    id : number,
    model : Model
}

type LevelData = {
    difficulty: number,
    platforms : {PlatformData},
    startCFrame : CFrame,
    monsters : {Model},
    startedAt : number,
    monsterSpawnRate : number,
    monsterSpawnAt : number,
    monstersLimit : number,
    monstersPassed : number,
    monstersKilled : number,
    nextMonsterId : number,
    failHitbox : Part,
}

local GameState = { -- TODO: Duplicated in Controller/Service
    Running = 0,
    Win = 1,
    Failed = 2
}

local Config = {
    --TODO: Move constants from code to this struct

    PlatformSpacing = 5,
    PlatformDifficultyMul = 5,

    MonsterMinSpawnRate = 5,
    MonsterMaxSpawnRate = 15,
    MonsterDifficultyMul = 3,
    LevelFailsOnPassedMonsters = 5,
    LiveUpdateRate = 1,

    GameDuration = 5 * 60
}

local GameService = Knit.CreateService {
    Name = "GameService";
    Client = {
        GameUpdate = Knit.CreateSignal(),
    };
}

function GameService:KnitStart()
    -- Code to run when the service starts
    self:RestartGame()
end

function GameService:GenerateLevel(difficulty : number) : LevelData
    local platformCount = difficulty * Config.PlatformDifficultyMul
    local startCFrame : CFrame = GameDir.StartLocation.CFrame

    local levelData : LevelData = {
        difficulty = difficulty,
        platforms = {},
        startCFrame = startCFrame,
        monsters = {},
        monstersPassed = 0,
        monstersKilled = 0,
        nextMonsterId = 1,
    }

    local platformModel : Model = AssetsDir.Platform
    local platformDimension = platformModel:GetExtentsSize()
    local platformCFrame = startCFrame + ((platformDimension.Y * 0.5) * startCFrame.UpVector)

    for i = 1, platformCount, 1 do
        local platform = platformModel:Clone()
        platform:PivotTo(platformCFrame)
        platformCFrame = platformCFrame + (platformCFrame.LookVector * (platformDimension.Z + Config.PlatformSpacing))
        platform.Parent = GameDir

        local platformData : PlatformData = {
            id = i,
            model = platform
        }

        local activatorPart : Part = platform.Activator.PrimaryPart
        activatorPart.Touched:Connect(function(touched)
            if touched.Parent:IsA("Model") and touched.Parent:FindFirstChild("Humanoid") then --TODO: Use Collision Groups
                local player = Players:GetPlayerFromCharacter(touched.Parent)

                if player then
                    self:OnPlatformActivated(levelData, platformData, player)
                end
            end
        end)

        local hitboxPart : Part = platform.DefenseSystem.Handle
        hitboxPart.Touched:Connect(function(touched)
            if touched.Parent:HasTag(MONSTER_TAG) then
                self:OnMonsterHit(levelData, platformData, touched.Parent)
            end
        end)

        table.insert(levelData.platforms, platformData)
    end

    local failHitbox : Part = AssetsDir.FailHitbox:Clone()
    failHitbox.Size = Vector3.new(100, 10, 3)
    failHitbox.CFrame = platformCFrame - ((failHitbox.Size.X * 0.5) * platformCFrame.RightVector)
    failHitbox.Parent = GameDir

    failHitbox.Touched:Connect(function(touched)
        if touched.Parent:HasTag(MONSTER_TAG) then
            self:OnMonsterPassed(levelData, touched.Parent)
        end
    end)

    levelData.failHitbox = failHitbox

    return levelData
end

function GameService:StartGame(difficulty : number)
    self:FinishGame()

    local levelData = self:GenerateLevel(difficulty)
    levelData.startedAt = os.clock()
    levelData.monsterSpawnRate = math.random(Config.MonsterMinSpawnRate, Config.MonsterMaxSpawnRate) / difficulty
    levelData.monsterSpawnAt = levelData.startedAt + levelData.monsterSpawnRate
    levelData.monstersLimit = Config.MonsterDifficultyMul * difficulty

    self.levelData = levelData
    self.lastLiveUpdate = 0

    levelData.updateTask = RunService.Heartbeat:Connect(function(deltaTime)
        if not self:UpdateGame(deltaTime) then
            self:FinishGame()
        end
    end)

    local music : Sound = SoundsDir.Music
    music.Looped = true
    music.Volume = 0.1
    music:Play()
end

function GameService:FinishGame()
    local levelData = self.levelData
    if not levelData then
        return
    end

    if levelData.updateTask then
        levelData.updateTask:Disconnect()
        levelData.updateTask = nil
    end

    if levelData.platforms then
        for _, value : Model in levelData.platforms do
            value.model:Destroy()
        end
        levelData.platforms = nil
    end

    if levelData.monsters then
        for _, value : Model in levelData.monsters do
            value:Destroy()
        end
        levelData.monsters = nil
    end

    if levelData.failHitbox then
        levelData.failHitbox:Destroy()
        levelData.failHitbox = nil
    end

    self.levelData = nil
end

function GameService:UpdateGame(dt: number) : boolean
    local levelData : LevelData = self.levelData

    local now = os.clock()

    local monsterCount = 0
    for _ in levelData.monsters do
        monsterCount += 1
    end

    --Respawn monsters
    if now >= levelData.monsterSpawnAt and monsterCount < levelData.monstersLimit then
        levelData.monsterSpawnAt = now + levelData.monsterSpawnRate
        levelData.monsterSpawnRate -= 0.1

        self:AddMonster(levelData)
    end

    local gameState
    local timeRemaining = Config.GameDuration - (now - levelData.startedAt)
    if timeRemaining <= 0 then
        gameState = GameState.Win
    elseif levelData.monstersPassed >= Config.LevelFailsOnPassedMonsters then
        gameState = GameState.Failed
    else
        gameState = GameState.Running
    end

    if gameState ~= GameState.Running or (now - self.lastLiveUpdate) >= Config.LiveUpdateRate then
        self.lastLiveUpdate = now
        self.Client.GameUpdate:FireAll({
            TimeRemaining = timeRemaining,
            MonstersPassed = levelData.monstersPassed,
            MonstersLimit = Config.LevelFailsOnPassedMonsters,
            MonstersKilled = levelData.monstersKilled,
            GameState = gameState
        })
    end

    if gameState == GameState.Win then
        self:OnGameWin(levelData)
        return false
    end

    if gameState == GameState.Failed then
        self:OnGameFailed(levelData)
        return false
    end

    return true
end

function GameService:AddMonster(levelData : LevelData)
    local models = AssetsDir.Monster:GetChildren()

    local monster : Model = models[math.random(1, #models)]:Clone()
    local rootPart : Part = AssetsDir.MonsterRoot:Clone()
    rootPart.CFrame = monster:GetPivot()
    rootPart.Parent = monster
    monster.PrimaryPart.Name = "Body"
    monster.PrimaryPart = rootPart

    monster.Body.CollisionGroup = "Monster"

    local size = math.random(3, 6)
    monster.Body.Size = monster.Body.Mesh.Scale * size
    monster.Body.Mesh.Scale = monster.Body.Mesh.Scale * (size - 1)

    rootPart.WeldConstraint.Part1 = monster.Body

    local hitboxSize = monster:GetExtentsSize()

    local randomPosition : CFrame = levelData.startCFrame - ((hitboxSize.X * 0.5 + math.random(2, 6) * 10) * (levelData.startCFrame.RightVector))
    randomPosition += (2.5 + (hitboxSize.Y * 0.5)) * randomPosition.UpVector

    monster:PivotTo(randomPosition)
    monster.Body.Massless = true

    local id = levelData.nextMonsterId
    levelData.nextMonsterId += 1

    monster:SetAttribute("MonsterId", id)
    monster.Parent = GameDir

    local distance = (randomPosition.Position - levelData.failHitbox.Position).Magnitude + 2

    local alignPosition : AlignPosition = rootPart.AlignPosition
    alignPosition.Position = (randomPosition + (randomPosition.LookVector * distance)).Position
    alignPosition.MaxVelocity = 2 + (math.random(1, 3) * levelData.difficulty)

    local alignOrientation : AlignOrientation = rootPart.AlignOrientation
    alignOrientation.CFrame = randomPosition

    levelData.monsters[id] = monster

    SoundsDir.MonsterSpawn:Play()
end

function GameService:OnPlatformActivated(levelData : LevelData, platformData : PlatformData, player : Player)
    if platformData.activated then
        return
    end

    print("Platform activated", platformData.id)
    platformData.activated = true

    local model = platformData.model
    local cylindricalConstraint : CylindricalConstraint = model.DefenseSystem.PrimaryPart.CylindricalConstraint

    local force = cylindricalConstraint.MotorMaxForce
    cylindricalConstraint.MotorMaxForce = force * 100

    task.delay(5, function()
        cylindricalConstraint.MotorMaxForce = force
        platformData.activated = false
    end)

    platformData.model.Base.Sounds.PushSound:Play()
end

function GameService:OnMonsterHit(levelData : LevelData, platformData : PlatformData, monster : Model)
    local id = monster:GetAttribute("MonsterId")

    if not levelData.monsters[id] then
        return
    end

    levelData.monsters[id] = nil
    levelData.monstersKilled += 1

    print("Monster hit", id)

    monster.Body.Transparency = 0.4
    monster.PrimaryPart.AlignPosition.Enabled = false
    monster.PrimaryPart.AlignOrientation.Enabled = false
    monster.PrimaryPart:ApplyImpulse(Vector3.new(-1, -1, 0) * 10)

    Debris:AddItem(monster, 2)

    platformData.model.Base.Sounds.HitSound:Play()
end

function GameService:OnMonsterPassed(levelData : LevelData, monster : Model)
    local id = monster:GetAttribute("MonsterId")

    if not levelData.monsters[id] then
        return
    end

    print("Monster passed", id)

    levelData.monsters[id] = nil

    monster.PrimaryPart.AlignOrientation.Enabled = false
    monster.PrimaryPart:ApplyAngularImpulse(Vector3.new(0, -1, 0) * 1)

    levelData.monsters[id] = nil
    Debris:AddItem(monster, 8)

    levelData.monstersPassed += 1

    SoundsDir.MonsterLaugh:Play()
end

function GameService:RestartGame(difficulty : number)
    task.delay(5, function()
        self:StartGame(difficulty or 1)
    end)
end

function GameService:OnGameFailed(levelData : LevelData)
    SoundsDir.GameFail:Play()
    self:RestartGame(levelData.difficulty)
end

function GameService:OnGameWin(levelData : LevelData)
    SoundsDir.GameWin:Play()
    self:RestartGame(levelData.difficulty + 1)
end

return GameService
