local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')

local player = Players.LocalPlayer
local mouse

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild('Humanoid')

task.wait(0.5)
mouse = player:GetMouse()

local tool = Instance.new('Tool')
tool.Name = 'Ghost Selector'
tool.RequiresHandle = true
tool.CanBeDropped = false
tool.TextureId = 'rbxassetid://10708916105'

local handle = Instance.new('MeshPart')
handle.Name = 'Handle'
handle.MeshId = 'rbxassetid://441564090'
handle.TextureID = 'rbxassetid://441564112'
handle.Size = Vector3.new(0.02, 0.015, 0.02)
handle.CanCollide = false
handle.Parent = tool

tool.Grip = CFrame.Angles(0, math.rad(180), 0)

local backpack = player:WaitForChild('Backpack')
tool.Parent = backpack

local selectedModels = {}
local ghostedModels = {}
local isSelecting = false
local toolEquipped = false

local function findPlot(playerName)
    if not workspace:FindFirstChild('BuildingAreas') then
        return nil
    end

    for _, area in pairs(workspace.BuildingAreas:GetChildren()) do
        if
            area:FindFirstChild('Player')
            and area.Player.Value == playerName
        then
            return area:FindFirstChild('PlayerArea')
        end
    end
    return nil
end

local function isInPlayerArea(model)
    local playerArea = findPlot(player.Name)
    if not playerArea then
        return false
    end

    local areaCFrame, areaSize = playerArea:GetBoundingBox()
    local areaPos = areaCFrame.Position

    local modelPos = model:GetPivot().Position

    return math.abs(modelPos.X - areaPos.X) <= areaSize.X / 2
        and math.abs(modelPos.Y - areaPos.Y) <= areaSize.Y / 2
        and math.abs(modelPos.Z - areaPos.Z) <= areaSize.Z / 2
end

local function getModelUnderMouse()
    if not mouse then
        return nil
    end

    local target = mouse.Target
    if not target then
        return nil
    end

    if target.Name == 'BasePlate' then
        return nil
    end

    local model = target:FindFirstAncestorOfClass('Model')

    if not model then
        return nil
    end

    if
        model
        and model:IsA('Model')
        and model ~= player.Character
        and model.Name ~= 'BasePlate'
        and isInPlayerArea(model)
    then
        return model
    end

    return nil
end

local function highlightModel(model, selected)
    if not model or not model.Parent then
        return
    end

    if selected then
        if not model:FindFirstChild('SelectionHighlight') then
            local highlight = Instance.new('Highlight')
            highlight.Name = 'SelectionHighlight'
            highlight.FillColor = Color3.fromRGB(0, 170, 255)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.Parent = model
        end
    else
        if model:FindFirstChild('SelectionHighlight') then
            model.SelectionHighlight:Destroy()
        end
    end
end

local function selectModel(model)
    if not model then
        return
    end
    if not table.find(selectedModels, model) then
        table.insert(selectedModels, model)
        highlightModel(model, true)
    end
end

local function deselectModel(model)
    if not model then
        return
    end
    local index = table.find(selectedModels, model)
    if index then
        table.remove(selectedModels, index)
        highlightModel(model, false)
    end
end

local function clearSelection()
    for _, model in pairs(selectedModels) do
        if model and model.Parent then
            if model:FindFirstChild('SelectionHighlight') then
                model.SelectionHighlight:Destroy()
            end
        end
    end
    selectedModels = {}
end

local function ghostModels()
    if #selectedModels == 0 then
        return
    end

    local ghostBatch = {}

    for _, model in pairs(selectedModels) do
        if not model or not model.Parent then
            continue
        end

        local modelData = {
            model = model,
            originalProperties = {},
        }

        for _, descendant in pairs(model:GetDescendants()) do
            if descendant:IsA('BasePart') then
                modelData.originalProperties[descendant] = {
                    Transparency = descendant.Transparency,
                    CanCollide = descendant.CanCollide,
                    CanTouch = descendant.CanTouch,
                    CanQuery = descendant.CanQuery,
                }

                if descendant.Name ~= 'Primary' then
                    descendant.Transparency = 0.9
                end
                descendant.CanCollide = false
                descendant.CanTouch = false
                descendant.CanQuery = false
            end
        end

        table.insert(ghostBatch, modelData)
    end

    if #ghostBatch > 0 then
        table.insert(ghostedModels, ghostBatch)
    end

    clearSelection()
end

local function undoGhost()
    if #ghostedModels == 0 then
        return
    end

    local lastBatch = table.remove(ghostedModels)

    for _, modelData in pairs(lastBatch) do
        for part, properties in pairs(modelData.originalProperties) do
            if part and part.Parent then
                part.Transparency = properties.Transparency
                part.CanCollide = properties.CanCollide
                part.CanTouch = properties.CanTouch
                part.CanQuery = properties.CanQuery
            end
        end
    end
end

local screenGui = nil
local selectionFrame = nil

local function createSelectionGUI()
    if not screenGui then
        screenGui = Instance.new('ScreenGui')
        screenGui.Name = 'SelectionGui'
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = player.PlayerGui
    end

    if selectionFrame then
        selectionFrame:Destroy()
    end

    selectionFrame = Instance.new('Frame')
    selectionFrame.Name = 'SelectionBox'
    selectionFrame.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    selectionFrame.BackgroundTransparency = 0.7
    selectionFrame.BorderColor3 = Color3.fromRGB(255, 255, 255)
    selectionFrame.BorderSizePixel = 2
    selectionFrame.Parent = screenGui
end

local function updateSelectionGUI(startX, startY, endX, endY)
    if not selectionFrame then
        return
    end

    local minX = math.min(startX, endX)
    local minY = math.min(startY, endY)
    local maxX = math.max(startX, endX)
    local maxY = math.max(startY, endY)

    selectionFrame.Position = UDim2.fromOffset(minX, minY)
    selectionFrame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
end

local function getModelsInScreenBox(startX, startY, endX, endY)
    local camera = workspace.CurrentCamera
    local playerArea = findPlot(player.Name)
    if not playerArea then
        return
    end

    local minX = math.min(startX, endX)
    local minY = math.min(startY, endY)
    local maxX = math.max(startX, endX)
    local maxY = math.max(startY, endY)

    local points = {}
    local step = 20

    for x = minX, maxX, step do
        for y = minY, maxY, step do
            local unitRay = camera:ScreenPointToRay(x, y)
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.FilterDescendantsInstances = { player.Character }

            local result = workspace:Raycast(
                unitRay.Origin,
                unitRay.Direction * 1000,
                raycastParams
            )

            if result and result.Instance then
                if result.Instance.Name == 'BasePlate' then
                    continue
                end

                local model = result.Instance:FindFirstAncestorOfClass('Model')
                if
                    model
                    and model:IsA('Model')
                    and model ~= player.Character
                    and model.Name ~= 'BasePlate'
                    and isInPlayerArea(model)
                then
                    selectModel(model)
                end
            end
        end
    end
end

tool.Equipped:Connect(function()
    toolEquipped = true
end)

tool.Unequipped:Connect(function()
    toolEquipped = false
    clearSelection()
    if selectionFrame then
        selectionFrame:Destroy()
        selectionFrame = nil
    end
    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end
    isSelecting = false
    isDragging = false
end)

local mouseDown = false
local clickStartX = nil
local clickStartY = nil
local isDragging = false

mouse.Button1Down:Connect(function()
    if not toolEquipped then
        return
    end

    mouseDown = true
    clickStartX = mouse.X
    clickStartY = mouse.Y
    isDragging = false

    local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if not ctrlHeld then
    end
end)

mouse.Button1Up:Connect(function()
    if not toolEquipped then
        return
    end

    mouseDown = false

    local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if isDragging then
        if clickStartX and clickStartY then
            getModelsInScreenBox(clickStartX, clickStartY, mouse.X, mouse.Y)
        end

        isDragging = false
        isSelecting = false
        if selectionFrame then
            selectionFrame:Destroy()
            selectionFrame = nil
        end
    else
        if ctrlHeld then
            local model = getModelUnderMouse()
            if model then
                if table.find(selectedModels, model) then
                    deselectModel(model)
                else
                    selectModel(model)
                end
            end
        else
            clearSelection()
            local model = getModelUnderMouse()
            if model then
                selectModel(model)
            end
        end
    end

    clickStartX = nil
    clickStartY = nil
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not toolEquipped or gameProcessed then
        return
    end

    local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if input.KeyCode == Enum.KeyCode.Backspace then
        ghostModels()
    end

    if input.KeyCode == Enum.KeyCode.Z and ctrlHeld then
        undoGhost()
    end
end)

RunService.RenderStepped:Connect(function()
    if
        not toolEquipped
        or not mouseDown
        or not clickStartX
        or not clickStartY
    then
        return
    end

    local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if not ctrlHeld then
        return
    end

    local deltaX = math.abs(mouse.X - clickStartX)
    local deltaY = math.abs(mouse.Y - clickStartY)
    local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

    if distance > 10 then
        if not isDragging then
            isDragging = true
            isSelecting = true
            createSelectionGUI()
        end

        updateSelectionGUI(clickStartX, clickStartY, mouse.X, mouse.Y)
    end
end)
