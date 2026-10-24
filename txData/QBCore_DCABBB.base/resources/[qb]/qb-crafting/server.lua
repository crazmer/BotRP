local QBCore = exports['qb-core']:GetCoreObject({ 'Functions' })
local sharedItems = exports['qb-core']:GetShared('Items')
local placedBenches = {}

local function validBenchType(benchType)
    return type(benchType) == 'string' and type(Config[benchType]) == 'table' and Config[benchType].recipes ~= nil and sharedItems[benchType] ~= nil
end

local function validAmount(value, maximum)
    local amount = tonumber(value)
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then return nil end
    if amount ~= math.floor(amount) or amount < 1 or amount > maximum then return nil end
    return amount
end

-- Functions

local function IncreasePlayerXP(source, xpGain, xpType)
    local Player = exports['qb-core']:GetPlayer(source)
    if Player then
        local currentXP = Player.GetRep(xpType)
        local newXP = currentXP + xpGain
        Player.AddRep(xpType, newXP)
        TriggerClientEvent('QBCore:Notify', source, string.format(Lang:t('notifications.xpGain'), xpGain, xpType), 'success')
    end
end

-- Callbacks

QBCore.Functions.CreateCallback('crafting:getPlayerInventory', function(source, cb)
    local player = exports['qb-core']:GetPlayer(source)
    if player then
        cb(player.PlayerData.items)
    else
        cb({})
    end
end)

-- Events
RegisterServerEvent('qb-crafting:server:removeMaterials', function(itemName, amount)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    amount = validAmount(amount, 1000)
    if not Player or type(itemName) ~= 'string' or not sharedItems[itemName] or not amount then return end
    if exports['qb-inventory']:RemoveItem(src, itemName, amount, false, 'qb-crafting:server:removeMaterials') then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems[itemName], 'remove')
    end
end)

RegisterNetEvent('qb-crafting:server:removeCraftingTable', function(benchType)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player or not validBenchType(benchType) then return end
    if not exports['qb-inventory']:RemoveItem(src, benchType, 1, false, 'qb-crafting:server:removeCraftingTable') then return end
    placedBenches[src] = placedBenches[src] or {}
    placedBenches[src][benchType] = (placedBenches[src][benchType] or 0) + 1
    TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems[benchType], 'remove')
    TriggerClientEvent('QBCore:Notify', src, Lang:t('notifications.tablePlace'), 'success')
end)

RegisterNetEvent('qb-crafting:server:addCraftingTable', function(benchType)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player or not validBenchType(benchType) then return end
    local count = placedBenches[src] and placedBenches[src][benchType] or 0
    if count < 1 then return end
    if not exports['qb-inventory']:AddItem(src, benchType, 1, false, false, 'qb-crafting:server:addCraftingTable') then return end
    placedBenches[src][benchType] = count - 1
    TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems[benchType], 'add')
end)

AddEventHandler('playerDropped', function()
    placedBenches[source] = nil
end)

RegisterNetEvent('qb-crafting:server:receiveItem', function(benchType, craftedItem, amountToCraft)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player or not validBenchType(benchType) or type(craftedItem) ~= 'string' then return end

    amountToCraft = validAmount(amountToCraft, 100)
    if not amountToCraft then return end

    local benchConfig = Config[benchType]
    local recipe
    for _, configuredRecipe in pairs(benchConfig.recipes) do
        if configuredRecipe.item == craftedItem then
            recipe = configuredRecipe
            break
        end
    end
    if not recipe or not sharedItems[craftedItem] then return end

    local xpType = benchConfig.xpType or 'craftingrep'
    local currentXP = Player.PlayerData and Player.PlayerData.metadata and Player.PlayerData.metadata[xpType] or 0
    if (recipe.xpRequired or 0) > currentXP then return end

    -- Check every ingredient before removing any of them to prevent partial ingredient loss.
    local inventory = Player.PlayerData.items or {}
    for _, requiredItem in ipairs(recipe.requiredItems or {}) do
        local needed = tonumber(requiredItem.amount) * amountToCraft
        local available = 0
        for _, inventoryItem in pairs(inventory) do
            if inventoryItem.name == requiredItem.item then
                available = inventoryItem.amount or 0
                break
            end
        end
        if not sharedItems[requiredItem.item] or not needed or needed < 1 or available < needed then
            TriggerClientEvent('QBCore:Notify', src, Lang:t('notifications.notenoughMaterials'), 'error')
            return
        end
    end

    local removed = {}
    for _, requiredItem in ipairs(recipe.requiredItems or {}) do
        local needed = tonumber(requiredItem.amount) * amountToCraft
        if not exports['qb-inventory']:RemoveItem(src, requiredItem.item, needed, false, 'qb-crafting:server:receiveItem') then
            for _, previous in ipairs(removed) do
                exports['qb-inventory']:AddItem(src, previous.item, previous.amount, false, false, 'qb-crafting:server:rollback')
            end
            return
        end
        removed[#removed + 1] = { item = requiredItem.item, amount = needed }
        TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems[requiredItem.item], 'remove')
    end

    if not exports['qb-inventory']:AddItem(src, craftedItem, amountToCraft, false, false, 'qb-crafting:server:receiveItem') then
        for _, previous in ipairs(removed) do
            exports['qb-inventory']:AddItem(src, previous.item, previous.amount, false, false, 'qb-crafting:server:rollback')
        end
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.inventory_full'), 'error')
        return
    end

    TriggerClientEvent('qb-inventory:client:ItemBox', src, sharedItems[craftedItem], 'add')
    TriggerClientEvent('QBCore:Notify', src, string.format(Lang:t('notifications.craftMessage'), sharedItems[craftedItem].label), 'success')
    IncreasePlayerXP(src, (recipe.xpGain or 0) * amountToCraft, xpType)
end)

-- Items

for benchType, v in pairs(Config) do
    if type(v) == 'table' then
        QBCore.Functions.CreateUseableItem(benchType, function(source)
            TriggerClientEvent('qb-crafting:client:useCraftingTable', source, benchType)
        end)
    end
end
