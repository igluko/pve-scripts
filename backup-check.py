#!/usr/bin/python3
#Как пользоватся:
#-t <часы> - за какое время проверять наличие бекапов
#-skip_id_from <vmid> - начиная с какого VM id пропускать проверку бекапов
#-silent - ничего не выводить в консоль
#-no_tg - не слать сообщение в Telegram (chat id и token бота берутся из системных переменных TG_TOKEN и TG_CHAT)
#-add_cron - добавит скрипт в cron на ежедневное выполнение в 8:00 с параметрами -t 8 -silent -skip_id_from 800

import sys, time, socket, os, subprocess

try:
    import paramiko
except ModuleNotFoundError:
    os.system('apt install -y python3-paramiko > /dev/null 2>&1') 
    import paramiko
try:
    import requests
except ModuleNotFoundError:
    os.system('apt install -y python3-requests > /dev/null 2>&1') 
    import requests
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
            print(p_yellow('Task already has been added to crontab: ') + str(job))
            sys.exit(0)
    job = cron.new(command=sys.path[0]+'/'+fname+' -t 8 -silent -skip_id_from 800')
    job.hour.on(8)
    job.minute.on(0)
    cron.write()
    print(p_green('Task has been added to crontab: ') + str(job))
    sys.exit(0)

# Проверка входных аргументов
def check_args():
    delta_time = 86400
    silent = False
    skip_id_from = 9999
    tg = True
    args = sys.argv
    args.append('poof')
    if len(args) > 2:
        for arg, next_arg in zip(args[1::], args[2::]):
            if arg == "-t":
                try:
                    delta_time = 3600 * int(next_arg)
                except ValueError:
                    sys.exit('Use proxmox-backup-check.py -t <difference in hours>')
            if arg == "-silent":
                silent = True
            if arg == "-no_tg":
                tg = False
            if arg == "-skip_id_from":
                try:
                    skip_id_from = int(next_arg)
                except ValueError:
                    sys.exit('Use int for VM id')
            if arg == '-add_cron':
                add_cron()
    return(delta_time, silent, skip_id_from, tg)

#Получаем сторадж PBS
def get_pbs_stor(proxmox):
    # Получаем список стораджей
    for i in range(5):
        try:
            storages = proxmox.storage.get()
            break
        except Exception:
            time.sleep(30)
    # Оставляем сторадж с type = pbs
    storage = ''
    PBSSum = 0
    for stor in storages:
        if (stor['type'] == 'pbs') and ( not ('disable' in stor)):
            if 'nodes' in stor:
                if (socket.gethostname() in stor['nodes']):
                    PBSSum += 1
                    storage = stor
                    continue
                else:
                    continue
            PBSSum += 1
            storage = stor
    if PBSSum != 1: 
        msg = 'PBS backup check script: On node '+ socket.gethostname() + ' has ' + str(PBSSum) + ' enabled PBS storage. 1 is expected.'
        if tg:
            send_tg(msg)
        sys.exit(msg)
    return(storage)


#Получаем список бекапов
def get_backup_list(storage, delta_time):
    # Запрашиваем список бекапов
    for i in range(1000):
        try:
            backups = proxmox.nodes(socket.gethostname()).storage(storage['storage']).content.get()
            break
        except Exception:
            time.sleep(5)
    # Отсеиваем лишнее
    backups_short = []
    for i in range(len(backups)):
        if (time.time() - backups[i]['ctime']) < delta_time:
            backups_short.append(backups[i])
    return(backups_short)

# Запрашиваем только нужный диапазон VM id
def get_vm_ids(proxmox, skip_id_from):
    vms = []
    for vm in proxmox.nodes(socket.gethostname()).qemu.get(): 
        if vm['vmid'] < skip_id_from :
            vms.append(vm['vmid'])
    return(vms)

# Проверка актуальности бекапов:
def check_vm_backups(vms, backups_short):
    vms_status =[]
    bad_vm = []
    good_vm =[]
    for vm in vms:
        if vm not in bad_vm :
            bad_vm.append(vm)
        for backup in backups_short:
            if backup['vmid'] == vm:
                bad_vm.remove(vm)
                good_vm.append(vm)
                break
    vms_status.append({'name': socket.gethostname(), 'bad_vm': bad_vm, 'good_vm': good_vm})
    return(vms_status)

# Проверка, есть ли запущенный процесс бекапа
def check_runing_jobs():
    cmd ='cat /var/log/pve/tasks/active'
    cmd2 = ['awk', '-v', 'st=0', '$2==st']
    cat = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE)
    grep = subprocess.Popen(('grep', 'vzdump'), stdout=subprocess.PIPE, stdin=cat.stdout)
    output = subprocess.check_output(cmd2, stdin=grep.stdout)
    return(output.decode('utf-8')[:-2])

def stop_runing_jobs(UPID):
    cmd = 'pvesh delete /nodes/' + socket.gethostname() + '/tasks/' + UPID
    status = subprocess.call(cmd.split())
    if status != 0:
                Msg = 'pvesh delete /nodes/' + socket.gethostname() + '/tasks ' + UPID + '\n exit status: ' + str(Status)
                sys.exit(Msg)


# Вывод результатов
def print_status(vms_status, silent, bad_msg = ""):
    for mv_status in vms_status:
        if not silent:
            print(p_yellow(mv_status['name']+':'))
        if bad_msg == '':
            bad_msg = '<b>'+mv_status['name']+':'+'</b>'+'\n'
        else:
            if not silent:
                 print(p_red('\nStopped running backup job:\n'+bad_msg))
            bad_msg = '<b>'+mv_status['name']+':'+'</b>'+'\nRunning backup job:\n'+bad_msg+'\n'
        for vmid in mv_status['good_vm']:
            if not silent:
                print(str(vmid) + ' | ' + p_green('backup OK'))
        for vmid in mv_status['bad_vm']:
            if not silent:
                print(p_red(str(vmid)) + ' | ' + p_red('NO backup'))
            bad_msg = bad_msg + str(vmid) + ' | ' + 'NO backup' + '\n'
    if bad_msg == '<b>'+mv_status['name']+':'+'</b>'+'\n' :
        bad_msg = ''
    return(bad_msg)

# Оповещаем в телеграм
def send_tg(msg):
    if len(msg) > 0:
        response = requests.post(url='https://api.telegram.org/bot' + os.environ['TG_TOKEN'] + '/sendMessage?parse_mode=html&chat_id=' + os.environ['TG_CHAT'] + '&text=' + msg)
        if  not response.ok :
            sys.exit(response.text + msg)

# Параметры подключения
proxmox = ProxmoxAPI(socket.gethostname(), user="root", backend='ssh_paramiko', service='pve')

delta_time, silent, skip_id_from, tg = check_args()

storage = get_pbs_stor(proxmox)
if storage == '' :
    msg = 'Not found PBS storages'
    if not silent:
        print(p_yellow(msg))
    if tg:
        send_tg('<b>' + socket.gethostname() +':</b>\n' + msg)
    sys.exit(0)
backups_short = get_backup_list(storage, delta_time)
vms = get_vm_ids(proxmox, skip_id_from)
vms_status = check_vm_backups(vms, backups_short)
job_upid = check_runing_jobs()
if job_upid != '':
    stop_runing_jobs(job_upid)
msg = print_status(vms_status, silent, job_upid)
if tg:
    send_tg(msg)
