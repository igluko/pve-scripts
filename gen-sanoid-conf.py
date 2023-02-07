#!/usr/bin/python3
#Автоматически добавляем стораджи в sanoid.conf
#-add_cron - добавит скрипт в cron на выполнение раз в час

import sys, os, subprocess, socket, json

try:
    import requests
except ModuleNotFoundError:
    os.system('python3 -m pip -q install requests > /dev/null') 
    import requests

NodeName = socket.gethostname()

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
    job = cron.new(command=sys.path[0]+'/'+fname, comment='Generate Sanoid Config')
    #job.hour.on(8)
    job.minute.on(0)
    cron.write()
    print(p_green('Task has been added to crontab: ') + str(job))
    sys.exit(0)

# Оповещаем в телеграм
def send_tg(msg, HTML = True):
    if len(msg) > 0:
        if HTML:
            response = requests.post(url='https://api.telegram.org/bot' + os.environ['TG_TOKEN'] + '/sendMessage?parse_mode=html&chat_id=' + os.environ['TG_CHAT'] + '&text=' + msg)
        else:
            response = requests.post(url='https://api.telegram.org/bot' + os.environ['TG_TOKEN'] + '/sendMessage?chat_id=' + os.environ['TG_CHAT'] + '&text=' + msg)
        if  not response.ok :
            sys.exit(response.text + msg)

# Получаем список стораджей в класетре с указанием текущей ноды или у которых ноды не казаны (all)
def GetStorages():
    Cmd ='pvesh get storage --output-format json' 
    Output = subprocess.check_output(Cmd.split())
    Storages = json.loads(Output.decode('utf-8'))
    ZfsStorages = []
    for Storage in Storages:
        if (Storage['type'] == 'zfspool') and ('images' in Storage['content']) :
            if not ('nodes' in Storage):
                ZfsStorages.append(Storage)
            else:
                if (NodeName in Storage['nodes']):
                    ZfsStorages.append(Storage)
    return(ZfsStorages)

def GetDataset(Storages):
    Datasets =[]
    
    for Storage in Storages:
        Cmd = 'pvesh get storage/' + Storage['storage'] + '/ --output-format json'
        Output = subprocess.check_output(Cmd.split())
        Dataset = json.loads(Output)['pool']
        Datasets.append(Dataset)
    return(Datasets)

def ReadSanoidConfig():
    OldConf = []
    with open ('/etc/sanoid/sanoid.conf', 'r') as f:
        OldConf = [line.rstrip() for line in f]
    return(OldConf)

def WriteSanoidConfig(Config):
    with open ('/etc/sanoid/sanoid.conf', 'w') as f:
        f.write(Config)
    

def CheckSanoidConf(OldConf, Datasets):
    OkStatus = True
    ZfsDatasets = Datasets.copy()
    for line in OldConf:
        if 'templates below this line' in line:
            break
        if ('[' in line):
            if (line[1:-1] in ZfsDatasets):
                ZfsDatasets.remove(line[1:-1])
            else:
                 OkStatus = False
    if len(ZfsDatasets) != 0: 
        OkStatus = False
    return(OkStatus)

def GenSanoidConf(OldConf, Datasets):
    NewConf = []
    for Dataset in Datasets:
        Conf = '[' + Dataset + ']\n    use_template = production\n    recursive = zfs\n\n'
        NewConf.append(Conf)
    
    TemplatesConfig = OldConf.copy()
    for i in range(len(OldConf)):
        if 'templates below this line' in OldConf[i+1]:
            break
        else:
            TemplatesConfig.remove(OldConf[i])
    if TemplatesConfig[-1] == '':
        TemplatesConfig.pop()

    NewConfStr = ''
    for l in NewConf:
        NewConfStr += l
    for l in TemplatesConfig:
        NewConfStr += l + '\n'
    return(NewConfStr)

def RestartSanoidSevice():
    Cmd ='systemctl restart sanoid.service' 
    Status = subprocess.call(Cmd.split())
    if Status != 0:
        Msg = 'systemctl restart sanoid.service\n exit status: ' + str(Status)
        send_tg('Generate Sanoid config: On node ' + '<b>' + NodeName +':</b>\n' + Msg)
        sys.exit(Msg)

    Cmd ='systemctl restart sanoid.timer' 
    Status = subprocess.call(Cmd.split())
    if Status != 0:
        Msg = 'systemctl restart sanoid.service\n exit status: ' + str(Status)
        send_tg('Generate Sanoid config: On node ' + '<b>' + NodeName +':</b>\n' + Msg)
        sys.exit(Msg)

check_args() 
Storages = GetStorages()
Datasets = GetDataset(Storages)
OldConf = ReadSanoidConfig()
if CheckSanoidConf(OldConf, Datasets):
    sys.exit(0)
else:
    Config = GenSanoidConf(OldConf, Datasets)
    WriteSanoidConfig(Config)
    RestartSanoidSevice()
    send_tg('On node ' + '<b>' + NodeName +'</b> Generated new <b>Sanoid</b> config:\n\n <code>' + Config.replace('#', '%23') +'</code>')
