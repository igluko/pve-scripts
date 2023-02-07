#!/usr/bin/python3

import sys, os, subprocess, json

# Проверка входных аргументов
def check_args():
    args = sys.argv
    args.append('poof')
    if len(args) > 2:
        for arg in args:
            if arg == '-add_cron':
                add_cron()

    # Добавляем задание в крон
def p_red(text):
    return("\033[31m"+text+"\033[0m")
def p_yellow(text):
    return("\033[33m"+text+"\033[0m")
def p_green(text):
    return("\033[32m"+text+"\033[0m")
def add_cron():
    try:
        from crontab import CronTab
    except ModuleNotFoundError:
        os.system('python3 -m pip -q install python-crontab > /dev/null') 
        from crontab import CronTab

    cron = CronTab(user='root')
    fname = os.path.basename(sys.argv[0])
    for job in cron:
        if fname in str(job):
            print(p_yellow('Task already has been added to crontab: ') + str(job))
            sys.exit(0)
    job = cron.new(command=sys.path[0]+'/'+fname, comment='PBS Jobs stopper for faster restore')
    job.minute.every(1)
    cron.write()
    print(p_green('Task has been added to crontab: ') + str(job))
    sys.exit(0)

#Получаем список запущенных на PBS задач
def GetTasks():
    Cmd ='/usr/sbin/proxmox-backup-manager task list --output-format json' 
    Output = subprocess.check_output(Cmd.split())
    Tasks = json.loads(Output.decode('utf-8'))
    return(Tasks)

#Проверяем наличие задачи reader (восстановление VM из бекапа)
def CheckTask(Tasks, WorkerType):
    for Task in Tasks:
        if Task['worker_type'] == WorkerType:
            return(True)
    return(False)

#Останавливаем GC и Verify 
def StopSlowTasks(Tasks):
    for Task in Tasks:
        if Task['worker_type'] in 'garbage_collection, verificationjob':
            Cmd ='/usr/sbin/proxmox-backup-manager task stop ' +  Task['upid']
            Status = subprocess.call(Cmd.split())
            if Status != 0:
                Msg = '/usr/sbin/proxmox-backup-manager task stop ' +  Task['upid'] + '\n exit status: ' + str(Status)
                sys.exit(Msg)

#Запускаем GC, если он не запущен и нет восстановления
def StartGC():
    Cmd ='/usr/sbin/proxmox-backup-manager prune-job list --output-format json'
    Output = subprocess.check_output(Cmd.split())
    GCjobs = json.loads(Output.decode('utf-8'))
    for GCjob in GCjobs:
        Cmd ='/usr/sbin/proxmox-backup-manager garbage-collection start '+ GCjob['store'] +' --output-format json'
        subprocess.check_output(Cmd.split())

check_args()
Tasks = GetTasks()
if CheckTask(Tasks, 'reader'):
    StopSlowTasks(Tasks)
else:
    if CheckTask(Tasks, 'garbage_collection'):
        sys.exit(0)
    else:
        StartGC()
