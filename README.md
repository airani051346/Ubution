# how its designed to work:
<img width="3268" height="1720" alt="image" src="https://github.com/user-attachments/assets/6ccead8d-7db8-440b-9395-5c041c6a6909" />


# how to install:
set env variable for the installation session
eg:
```bash
curl -sSL https://raw.githubusercontent.com/airani051346/Ubution/refs/heads/main/installer_script.sh | sudo bash -s -- --all --domain <mydomain.com>
```

# how to access GitLab::<br>
  URL:  https://gitlab.<-mydomain.com->
  Initial root password: 

```bash
sudo docker exec -t compose-gitlab-1 bash -lc "cat /etc/gitlab/initial_root_password || true"
```

# how to access phpMyAdmin:<br> 
  URL:  https://pma.<-mydomain.com->
  MySQL root login is enabled remotely <br>
  username root <br>
  default fassword is ChangeMeStrong123 if not defined with --mysql-root-pass
  
# Import Database and Sample Data
  create a database named netvars and import netvars.sql into mysql DB. You can find this file in SQL-DB folder <br>
  additional priviligaes for the ansible user <br>

```sql
CREATE USER IF NOT EXISTS 'ansible'@'%' IDENTIFIED BY 'ChangeMe';
CREATE USER IF NOT EXISTS 'ansible'@'127.0.0.1' IDENTIFIED BY 'ChangeMe';
GRANT SELECT ON netvars.* TO 'ansible'@'%';
GRANT SELECT ON netvars.* TO 'ansible'@'127.0.0.1';
FLUSH PRIVILEGES;
```

# Data Viewer: (tbd)
  on RoadMap 2026  URL:  https://orch.example.com
  
# Download github-rep.(GITHUB)
Go to https://github.com/airani051346/Ubution <br>
<img width="975" height="451" alt="image" src="https://github.com/user-attachments/assets/2626e3f3-3c2f-4e45-a3a4-9948eb1b600d" /><br>

# extract zip to your local storage
<img width="664" height="435" alt="image" src="https://github.com/user-attachments/assets/ce7c9de2-66f5-4fc4-a575-1d3c31622977" /><br>

# Open the folder Ubution-main\git-project
<img width="763" height="184" alt="image" src="https://github.com/user-attachments/assets/c452f7a9-0ea6-47a5-b885-8938814dfc77" /><br>

# Login to gitlab (GITLAB)
https://gitlab.<-mydomain.com->//users/sign_in
<img width="663" height="522" alt="image" src="https://github.com/user-attachments/assets/e9545ca1-f3bd-4c36-94d3-fb7608f12b9b" /><br>

# Create a blank project (pub-deploy-cp)
https://gitlab.<-mydomain.com->/projects/new#blank_project 
<img width="732" height="328" alt="image" src="https://github.com/user-attachments/assets/990852a0-445d-4305-bb1a-7a387ac1e3f2" /><br>
<img width="494" height="208" alt="image" src="https://github.com/user-attachments/assets/0a8557a7-2eba-41bb-9b08-12c3e7f81b17" /><br>
<img width="975" height="802" alt="image" src="https://github.com/user-attachments/assets/259d9a0a-6e57-4e2b-b1ef-e249ebd1bd9c" /><br>

# Upload the git files
The easiest way to do this is over the web-editor ide
<img width="672" height="619" alt="image" src="https://github.com/user-attachments/assets/6e1f9202-833e-4714-b5f7-8e6a34fa1fbe" /><br>

Now you can drag the folders into your new project
<img width="820" height="359" alt="image" src="https://github.com/user-attachments/assets/9fd4e042-a5e3-4637-904b-01396eea8727" /><br>

Commit change is necessary to close anychange in your repository
<img width="433" height="297" alt="image" src="https://github.com/user-attachments/assets/398ccd75-d974-422a-868d-ad55d96343d6" /><br>
<img width="419" height="288" alt="image" src="https://github.com/user-attachments/assets/2335b2a4-765c-4963-946c-4dbb624f623d" /><br>


# Misc tests
# in our deployment because all is on the same host we are using primary IP
## and adding it to the /etc/hosts file
```bash
IP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}')
sudo bash -lc 'IP='"$IP"'; for h in registry.fritz.lan gitlab.fritz.lan awx.fritz.lan pma.fritz.lan; do
  grep -qE "^[[:space:]]*$IP[[:space:]]+$h([[:space:]]|\$)" /etc/hosts || echo "$IP $h" >> /etc/hosts
done'
```

# registry login check with default password
```bash
printf 'ChangeMeReg123' | docker login http://127.0.0.1:5000 -u awx --password-stdin
```

# ip address of mysql docker compose 
```bash
sudo docker ps
sudo docker inspect -f '{{.Name}} -> {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' compose-mysql-1
```
<img width="1757" height="236" alt="image" src="https://github.com/user-attachments/assets/f4e7d14d-d283-4565-b03e-56359706c102" />

# start executing playbooks
```bash
cd ~
[ -d "$HOME/Ubution/.git" ] && git -C "$HOME/Ubution" pull --ff-only  || git clone https://gitlab.fritz.lan/root/ubution.git "$HOME/Ubution"
```

# executoion flow
```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================
# CONFIG
# ============================
PLAYBOOK_DIR="/home/cpadmin/ubution"
LOG_DIR="$PLAYBOOK_DIR/logs"
MAIL_TO="admin@example.com"
MAIL_FROM="ansible@example.com"

# Require destHost argument
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <destHost>"
    exit 1
fi
destHost="$1"

mkdir -p "$LOG_DIR"

# ============================
# MAIL FUNCTION
# ============================
send_mail() {
    local subject="$1"
    local body="$2"
    echo "$body" | mail -s "$subject" -r "$MAIL_FROM" "$MAIL_TO"
}

# ============================
# PLAYBOOK RUN FUNCTION
# ============================
run_playbook() {
    local step="$1"
    local playbook="$2"
    local ignore_fail="$3"   # true / false

    local logfile="$LOG_DIR/${step}_$(basename "$playbook").log"

    echo ">>> Running step $step: $playbook on $destHost (ignore_fail=$ignore_fail)"

    if ansible-playbook "$PLAYBOOK_DIR/$playbook" -i "$PLAYBOOK_DIR/Inventory.yml" -e "inventory_hostname=$destHost" >"$logfile" 2>&1; then
        echo "SUCCESS: $playbook" | tee -a "$LOG_DIR/summary.log"
        send_mail "SUCCESS: $playbook" "Playbook $playbook (step $step) completed successfully. Log: $logfile"
    else
        echo "FAILED: $playbook" | tee -a "$LOG_DIR/summary.log"
        send_mail "FAILED: $playbook" "Playbook $playbook (step $step) failed. See log: $logfile"

        if [[ "$ignore_fail" == "false" ]]; then
            echo "Stopping flow at step $step due to failure."
            exit 1
        fi
    fi
}

# ============================
# FLOW DEFINITION (5 STEPS)
# ============================
# run_playbook <step> <playbook.yml> <ignore_fail>
cd ~
if not exist $PLAYBOOK_DIR then git clone https://gitlab.fritz.lan/root/ubution.git
cd $PLAYBOOK_DIR
git pull
run_playbook "step-1" "pb_render.yml"                  false
run_playbook "step-2" "pb_apply.yml"                   false
run_playbook "step-3" "reboot_fire_and_exit.yml.yml"   true    # ignore failure
run_playbook "step-4" "wait_until_reachable.yml"       false
# run_playbook "step-5" "pb_create_cluster.yml"          false

echo ">>> Flow completed for host $destHost. Logs are in $LOG_DIR"



# ############################################
# installation
# ############################################




sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt update
sudo apt install -y software-properties-common ansible pip
sudo ansible-galaxy collection install check_point.mgmt --force
sudo pip install setuptools psycopg2-binary gitpython  pymysql  mysql-connector-python requests netmiko pyats httpx beautifulsoup4 lxml python-dateutil pytz pymongo cryptography bcrypt boto3 azure-mgmt-resource azure-storage-blob pexpect paramiko-expect paramiko




# ############################################
# installation
# ############################################
ansible-playbook pb_render.yml -i Inventory.yml -e "inventory_hostname=vpn-gw-1"
ansible-playbook pb_apply.yml  -i Inventory.yml -e "inventory_hostname=vpn-gw-1"
ansible-playbook pb_apply.yml  -i Inventory.yml -e "inventory_hostname=vpn-gw-1 gaia_mode=full"
ansible-playbook reboot_fire_and_exit.yml.yml   -e "inventory_hostname=vpn-gw-1" 
ansible-playbook wait_until_reachable.yml       -e "inventory_hostname=vpn-gw-1"
ansible-playbook pb_create_cluster.yml          -e "inventory_hostname=vpn-gw-1"

```
# 
