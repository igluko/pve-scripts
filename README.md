Collection of scripts for PVE

# switch.sh

Here is the script for switching a virtual machine with a pass-through video card
Requires VirtIO Guest to send a hibernate command!
Requires Swap on Linux for hibernate
How it works:

- The script sends the hibernate command
- Then waits for VM to shut down
- Then starts up another VM


# zfs-autoreservation
This should protect important system datasets from a total lack of free space.

The second parameter can be a number of bytes or the number of percent to be added to the current dataset size to get the value for the reserve.

./zfs-autoreservation [dataset_name] [number]

or
 
./zfs-autoreservation [dataset_name] [number%]

Example
```
zfs get used,reservation  rpool/ROOT
NAME        PROPERTY     VALUE   SOURCE
rpool/ROOT  used         6.33G   -
rpool/ROOT  reservation   none   local

./zfs-autoreservation.sh rpool/ROOT 10%
size:   6796353536
reserv: 7475988889

zfs get used,reservation  rpool/ROOT
NAME        PROPERTY     VALUE   SOURCE
rpool/ROOT  used         6.33G   -
rpool/ROOT  reservation  6.96G   local
```
  
