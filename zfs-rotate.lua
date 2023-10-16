local args = ...
local arguments = args.argv

local yearly = 0
local monthly = 0
local daily = 0
local hourly = 0
local pool  -- Объявляем переменную p<пул>
local frequently -- Объявляем переменную f<int>
local current_time -- Объявляем переменную t<int>

-- Разбор аргументов
for i = 1, #arguments do
    local param = arguments[i]
    
    if type(param) ~= "string" then goto continue end

    if param:sub(1, 1) == "y" then
        yearly = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "m" then
        monthly = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "d" then
        daily = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "h" then
        hourly = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "f" then
        frequently = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "t" then
        current_time = tonumber(param:sub(2))
    elseif param:sub(1, 1) == "p" then
        pool = param:sub(2)
    end

    ::continue::
end


-- Проверяем, заданы ли аргументы f и t
if not frequently or not current_time or not pool then
    return "Аргументы f, t и p должны быть заданы.\n\
    Пример использования: zfs program rpool zfs-rotate.lua m12 d30 h10000 f10000 t$(date +%s) prpool"
end

-- helper
function table_is_empty(t)
    for _, _ in pairs(t) do
        return false
    end
    return true
end

-- Recursive function to find ZFS entities without children
local function findLeafDatasets(dataset)
    local leaves = {}
    local hasChildren = false

    for child in zfs.list.children(dataset) do
        hasChildren = true
        local childLeaves = findLeafDatasets(child)
        for _, leaf in ipairs(childLeaves) do
            table.insert(leaves, leaf)
        end
    end

    if not hasChildren then
        table.insert(leaves, dataset)
    end

    return leaves
end

local noChildDatasets = findLeafDatasets(pool)

local function getAllSnapshotsGroupedByType(dataset)
    local groupedSnapshots = {
        ["Yearly"] = {},
        ["Monthly"] = {},
        ["Daily"] = {},
        ["Hourly"] = {},
        ["Frequently"] = {}
    }

    for snapshot in zfs.list.snapshots(dataset) do
        if snapshot then
            if snapshot:find("yearly") then
                table.insert(groupedSnapshots["Yearly"], snapshot)
            elseif snapshot:find("monthly") then
                table.insert(groupedSnapshots["Monthly"], snapshot)
            elseif snapshot:find("daily") then
                table.insert(groupedSnapshots["Daily"], snapshot)
            elseif snapshot:find("hourly") then
                table.insert(groupedSnapshots["Hourly"], snapshot)
            elseif snapshot:find("frequently") then
                table.insert(groupedSnapshots["Frequently"], snapshot)
            end
        end
    end

    for _, snapshots in pairs(groupedSnapshots) do
        table.sort(snapshots)
    end

    return groupedSnapshots
end

local function getSnapshotTimestamp(snapshot)
    return zfs.get_prop(snapshot, "creation")
end

local function destroyOldSnapshots(snapshots, type, limit)
    while #snapshots[type] > limit do
        local oldestSnap = table.remove(snapshots[type], 1)
        local err = zfs.sync.destroy(oldestSnap)
        if (err ~= 0) then
            failed[oldestSnap] = err
        else
            table.insert(results["Destroyed Snapshots"][type], oldestSnap)
        end
    end
end

local function checkAndRenameSnapshots(snapshots, type, age)
    if not snapshots[type] or #snapshots[type] == 0 or (current_time - getSnapshotTimestamp(snapshots[type][#snapshots[type]]) > age) then
        local frequentlySnap = snapshots["Frequently"] and snapshots["Frequently"][#snapshots["Frequently"]]
        if frequentlySnap then
            local newName = frequentlySnap:gsub("_frequently", "_" .. type:lower())
            zfs.sync.rename_snapshot(frequentlySnap, newName)
            if (err ~= 0) then
                failed[oldestSnap] = err
            else
                table.insert(results["Renamed Snapshots"][type], {from = frequentlySnap, to = newName})
            end 
        end
    end
end

results = {}
results["Renamed Snapshots"] = {
    Yearly = {},
    Monthly = {},
    Daily = {},
    Hourly = {}
}
results["Destroyed Snapshots"] = {
    Yearly = {},
    Monthly = {},
    Daily = {},
    Hourly = {},
    Frequently = {}
}
failed = {}

for _, dataset in ipairs(noChildDatasets) do
    local snapshots = getAllSnapshotsGroupedByType(dataset)

    -- checkAndRenameSnapshots(snapshots, "Yearly", 365*24*3600)
    -- checkAndRenameSnapshots(snapshots, "Monthly", 30*24*3600)
    -- checkAndRenameSnapshots(snapshots, "Daily", 24*3600)
    -- checkAndRenameSnapshots(snapshots, "Hourly", 3600)
    
    destroyOldSnapshots(snapshots, "Yearly", yearly)
    destroyOldSnapshots(snapshots, "Monthly", monthly)
    destroyOldSnapshots(snapshots, "Daily", daily)
    destroyOldSnapshots(snapshots, "Hourly", hourly)
    destroyOldSnapshots(snapshots, "Frequently", frequently)
end

if not table_is_empty(failed) then
    results["failed"] = failed
end

return results
