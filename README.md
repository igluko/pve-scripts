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



## fio.sh
Это простой скрипт для тестирования конкретных дисков nvme0n1 nvme1n1.

Скрипт предполагает наличие тестового раздела P4 в конце диска, или свободного места для его создания.

Скрипт не предназначен для тестирования произвольных дисков или разделов.

```mermaid
flowchart TB
    INSTALL[install fio jq fdisk] --> SET_DISKS[DISKS = nvme0n1 nvme1n1]
    SET_DISKS --> IS_PART{Is partition p4 exists?}
    subgraph MAIN_LOOP [for each disk]
        IS_PART -- NO --> CREATE_PART[Create partition p4]
        CREATE_PART --> ECHO_INFO[Show disk info]
        IS_PART -- YES --> ECHO_INFO[Show disk info]
        ECHO_INFO --> ECHO_HEADERS[Show all headers]
        ECHO_HEADERS --> RUN_TESTS[Run all tests]
    end
```