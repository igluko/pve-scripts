# pve-scripts

Collection of scripts for PVE

## switch.sh

Here is the script for switching a virtual machine with a pass-through video card
Requires VirtIO Guest to send a hibernate command!
Requires Swap on Linux for hibernate
How it works:

- The script sends the hibernate command
- Then waits for VM to shut down
- Then starts up another VM

Here is a simple flow chart:

```mermaid
graph TD;
    A-->B;
    A-->C;
    B-->D;
    C-->D;
```

