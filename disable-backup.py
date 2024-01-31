#!/usr/bin/python3

#Как пользоватся:
#Нужно указать начиная с какого vmid нужно отключить бекап у дисков -disable_id_from <vmid>

import sys, time, socket, os

try:
    import paramiko
except ModuleNotFoundError:
    os.system('apt install -y python3-paramiko > /dev/null 2>&1') 
    import paramiko
try:
    from proxmoxer import ProxmoxAPI
except ModuleNotFoundError:
    os.system('apt install -y python3-proxmoxer > /dev/null 2>&1')
    from proxmoxer import ProxmoxAPI

def p_red(text):
    return("\033[31m"+text+"\033[0m")
def p_yellow(text):
    return("\033[33m"+text+"\033[0m")
def p_green(text):
    return("\033[32m"+text+"\033[0m")

# Добавляем задание в крон
def add_cron():
    try:
        from crontab import CronTab
    except ModuleNotFoundError:
        os.system('apt install -y python3-crontab > /dev/null 2>&1') 
        from crontab import CronTab

    cron = CronTab(user='root')
    fname = os.path.basename(sys.argv[0])
    for job in cron:
        if fname in str(job):
            sys.exit(p_yellow('Task already has been added to crontab: ') + str(job))
    job = cron.new(command=sys.path[0]+'/'+fname + ' -disable_id_from 700')
    job.minute.on(30)
    cron.write()
    sys.exit(p_green('Task has been added to crontab: ') + str(job))

# Проверка входных аргументов
def check_args():
    args = sys.argv
    args.append('poof')
    if len(args) > 2:
        for arg, next_arg in zip(args[1::], args[2::]):
            if arg == "-disable_id_from":
                try:
                    disable_id_from = int(next_arg)
                except ValueError:
                    sys.exit('Use disable-backup.py -disable_id_from <vmid>')
            if arg == '-add_cron':
                add_cron()
    else:
        sys.exit('Use disable-backup.py -disable_id_from <vmid>')
    return(disable_id_from)

# Запрашиваем только нужный диапазон VM id
def get_vm_ids(proxmox, disable_id_from):
    vmsid = []
    for vm in proxmox.nodes(socket.gethostname()).qemu.get(): 
        if vm['vmid'] >= disable_id_from :
            vmsid.append(vm['vmid'])        
    return(vmsid)

# Получаем список стораджей
def get_pbs_stor(proxmox):
    for i in range(5):
        try:
            storages = proxmox.storage.get()
            break
        except Exception:
            time.sleep(5)

    # Оставляем сторадж с content = images
    res=[]
    for stor in storages:
        if 'images' in stor['content']:
            res.append(stor['storage'])
    return(res)

# Получаем список дисков для VM
def get_vm_disks(proxmox, vms, storages):
    exclude = 'description, efidisk, tpmstate, efidisk, tpmstate, unused'
    res={}
    for vm in vms:
        res[vm] = {}
        for k, v in proxmox.nodes(socket.gethostname()).qemu(vm).config.get().items():
            if (k[:-1] not in exclude) and (type(v) == str):
                for storage in storages:
                    if ('backup=0' not in v) and (storage in v):
                        res[vm][k] = v
    return(res)

#Отключение бекапа дисков
def set_backup_0(proxmox, vm_disks):
    for vm, disks in vm_disks.items():
        for k, v in disks.items():
            #временное решение, пока не разберусь с api
            cmd =  'pvesh set /nodes/' + socket.gethostname() + '/qemu/' + str(vm) + '/config/ -' + k + '=' + v + ',backup=0'
            os.system(cmd + ' > /dev/null')
            #Через api не получается передать "k", нужно указывать именно значение параметра.
            #proxmox.nodes(socket.gethostname()).qemu(vm).config.set(k=v+',backup=0')

# Параметры подключения

disable_id_from = check_args()

proxmox = ProxmoxAPI(socket.gethostname(), user="root", backend='ssh_paramiko', service='pve')

vms = get_vm_ids(proxmox, disable_id_from)
storages = get_pbs_stor(proxmox)
vm_disks = get_vm_disks(proxmox, vms, storages)
set_backup_0(proxmox, vm_disks)