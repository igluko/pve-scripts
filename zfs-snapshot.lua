-- Example usage:  zfs program rpool zfs-snapshot.lua $(date +"%Y-%m-%d_%H:%M:%S") rpool/data/vm-116-disk-1

-- Initialization of tables to store information about the created snapshots and any errors that occurred
succeeded = {}
failed = {}

function create_snapshot(fs, timearg)
    -- Attempt to create a snapshot for the given filesystem with the desired name format
    local snap_name = fs .. '@autosnap_' .. timearg .. '_frequently'
    local err = zfs.sync.snapshot(snap_name)
    if (err ~= 0) then
        failed[snap_name] = err
    else
        succeeded[snap_name] = err
    end
end

function table_is_empty(t)
    for _, _ in pairs(t) do
        return false
    end
    return true
end

-- Retrieve the arguments
args = ...
argv = args["argv"]

-- The first argument is the date
timearg = argv[1]

-- Create a snapshot for each provided filesystem
for i=2, #argv do
    create_snapshot(argv[i], timearg)
end

-- Return the results
results = {}
results["succeeded"] = succeeded
if not table_is_empty(failed) then
    results["failed"] = failed
end
return results

