local QBCore = exports['qb-core']:GetCoreObject({ 'Functions' })
local sharedItems = exports['qb-core']:GetShared('Items')
local pendingMelts = {}

local function isAtPawnshop(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    for _, location in pairs(Config.PawnLocation) do
        if #(coords - location.coords) <= 5.0 then return true end
    end
    return false
end

local function validAmount(value, maximum)
    local amount = tonumber(value)
    return amount and amount == math.floor(amount) and amount > 0 and amount <= (maximum or 1000) and amount
end

local function getPawnItem(itemName)
    for _, item in pairs(Config.PawnItems) do
        if item.item == itemName then return item end
    end
end

local function getMeltingItem(itemName)
    for _, item in pairs(Config.MeltingItems) do
        if item.item == itemName then return item end
    end
end

RegisterNetEvent('qb-pawnshop:server:sellPawnItems', function(itemName, itemAmount)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player or type(itemName) ~= 'string' or not isAtPawnshop(src) then return end

    local amount = validAmount(itemAmount, 1000)
    local pawnItem = getPawnItem(itemName)
    local itemInfo = sharedItems[itemName]
    if not amount or not pawnItem or not itemInfo then return end

    local totalPrice = amount * tonumber(pawnItem.price)
    if not totalPrice or totalPrice <= 0 then return end
    if exports['qb-inventory']:RemoveItem(src, itemName, amount, false, 'qb-pawnshop:server:sellPawnItems') then
        Player.AddMoney(Config.BankMoney and 'bank' or 'cash', totalPrice, 'qb-pawnshop:server:sellPawnItems')
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.sold', { value = amount, value2 = itemInfo.label, value3 = totalPrice }), 'success')
        TriggerClientEvent('qb-inventory:client:ItemBox', src, itemInfo, 'remove')
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.no_items'), 'error')
    end
    TriggerClientEvent('qb-pawnshop:client:openMenu', src)
end)

RegisterNetEvent('qb-pawnshop:server:meltItemRemove', function(itemName, itemAmount)
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player or type(itemName) ~= 'string' or not isAtPawnshop(src) or pendingMelts[src] then return end

    local amount = validAmount(itemAmount, 100)
    local meltingItem = getMeltingItem(itemName)
    local itemInfo = sharedItems[itemName]
    if not amount or not meltingItem or not itemInfo then return end

    if not exports['qb-inventory']:RemoveItem(src, itemName, amount, false, 'qb-pawnshop:server:meltItemRemove') then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.no_items'), 'error')
        return
    end

    local duration = tonumber(meltingItem.meltTime) * amount * 60
    pendingMelts[src] = {
        itemName = itemName,
        amount = amount,
        rewards = meltingItem.rewards,
        readyAt = os.time() + duration,
        claimed = false
    }
    local clientItem = {
        label = itemInfo.label,
        reward = meltingItem.rewards,
        name = itemName,
        amount = amount,
        time = meltingItem.meltTime
    }
    TriggerClientEvent('qb-inventory:client:ItemBox', src, itemInfo, 'remove')
    TriggerClientEvent('qb-pawnshop:client:startMelting', src, clientItem, amount, duration)
    TriggerClientEvent('QBCore:Notify', src, Lang:t('info.melt_wait', { value = tonumber(meltingItem.meltTime) * amount }), 'primary')
end)

RegisterNetEvent('qb-pawnshop:server:pickupMelted', function()
    local src = source
    local Player = exports['qb-core']:GetPlayer(src)
    local job = pendingMelts[src]
    if not Player or not job or job.claimed or not isAtPawnshop(src) then return end
    if os.time() < job.readyAt then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.no_melt'), 'error')
        return
    end

    -- Consume the server-side job before awarding anything so repeated client events cannot duplicate rewards.
    job.claimed = true
    pendingMelts[src] = nil
    for _, reward in pairs(job.rewards) do
        local itemInfo = sharedItems[reward.item]
        local amount = tonumber(reward.amount) * job.amount
        if itemInfo and amount > 0 then
            if exports['qb-inventory']:AddItem(src, reward.item, amount, false, false, 'qb-pawnshop:server:pickupMelted') then
                TriggerClientEvent('qb-inventory:client:ItemBox', src, itemInfo, 'add')
                TriggerClientEvent('QBCore:Notify', src, Lang:t('success.items_received', { value = amount, value2 = itemInfo.label }), 'success')
            else
                TriggerClientEvent('QBCore:Notify', src, Lang:t('error.inventory_full', { value = itemInfo.label }), 'warning', 7500)
            end
        end
    end
    TriggerClientEvent('qb-pawnshop:client:resetPickup', src)
    TriggerClientEvent('qb-pawnshop:client:openMenu', src)
end)

AddEventHandler('playerDropped', function()
    pendingMelts[source] = nil
end)

QBCore.Functions.CreateCallback('qb-pawnshop:server:getInv', function(source, cb)
    local Player = exports['qb-core']:GetPlayer(source)
    cb(Player and Player.PlayerData.items or {})
end)
