# how to install:
set env variable for the installation session
eg:
```bash
curl -sSL https://raw.githubusercontent.com/airani051346/Ubution/refs/heads/main/installer_script.sh | sudo bash -s -- --all --domain <mydomain.com>
```

# wait for containers to start
start a new shell and wait for 
<img width="917" height="206" alt="image" src="https://github.com/user-attachments/assets/3c2fcc38-88b2-448c-8126-9c6a3b90beff" />

```bash
watch -d sudo kubectl -n awx get pods
```

# how to access GitLab::<br>
  URL:  https://gitlab.<mydomain.com>
  Initial root password: 

```bash
sudo docker exec -t compose-gitlab-1 bash -lc "cat /etc/gitlab/initial_root_password || true"
```

# how to access phpMyAdmin:<br> 
  URL:  https://pma.<mydomain.com>
  MySQL root login is enabled remotely <br>
  username root <br>
  default fassword is ChangeMe!Strong123 if not defined with --mysql-root-pass
  
# Import Database and Sampple Data
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
  
# how to access AWX:<br>
  URL:  https://awx.<mydomain.com>
  User: admin
  Pass: (what you set) or fetch with:
  
```bash
sudo kubectl -n awx get secret awx-admin-password -o jsonpath='{.data.password}' | base64 --decode; echo
```

# Download git-rep.
Go to https://github.com/airani051346/Ubution
<img width="975" height="451" alt="image" src="https://github.com/user-attachments/assets/2626e3f3-3c2f-4e45-a3a4-9948eb1b600d" />
<br>
- extract zip to your local storage
  <img width="664" height="435" alt="image" src="https://github.com/user-attachments/assets/ce7c9de2-66f5-4fc4-a575-1d3c31622977" />
<br>
- Open the folder Ubution-main\git-project
  <img width="763" height="184" alt="image" src="https://github.com/user-attachments/assets/c452f7a9-0ea6-47a5-b885-8938814dfc77" />
<br>

# Login to gitlab
https://<server-ip>:4443//users/sign_in
<img width="663" height="522" alt="image" src="https://github.com/user-attachments/assets/e9545ca1-f3bd-4c36-94d3-fb7608f12b9b" />
<br>
 
- Create a blank project (pub-deploy-cp)
https://<server-ip>:4443/projects/new#blank_project 
<img width="732" height="328" alt="image" src="https://github.com/user-attachments/assets/990852a0-445d-4305-bb1a-7a387ac1e3f2" />
<br>
<img width="494" height="208" alt="image" src="https://github.com/user-attachments/assets/0a8557a7-2eba-41bb-9b08-12c3e7f81b17" />
<br>
<img width="975" height="802" alt="image" src="https://github.com/user-attachments/assets/259d9a0a-6e57-4e2b-b1ef-e249ebd1bd9c" />
<br>
 
# Upload the git files
The easiest way to do this is over the web-editor ide
<img width="672" height="619" alt="image" src="https://github.com/user-attachments/assets/6e1f9202-833e-4714-b5f7-8e6a34fa1fbe" />
<br>
Now you can drag the folders into your new project
<img width="820" height="359" alt="image" src="https://github.com/user-attachments/assets/9fd4e042-a5e3-4637-904b-01396eea8727" />
 <br>
Commit change is necessary to close anychange in your repository
<img width="433" height="297" alt="image" src="https://github.com/user-attachments/assets/398ccd75-d974-422a-868d-ad55d96343d6" />
<br>
<img width="419" height="288" alt="image" src="https://github.com/user-attachments/assets/2335b2a4-765c-4963-946c-4dbb624f623d" />
<br>

Create ssh key for awx and gitlab integration
```bash
sudo ssh-keygen -N '' -f awx_ssh_key
sudo cat awx_ssh_key.pub
copy the pub key here in gitlab
```
<img width="975" height="355" alt="image" src="https://github.com/user-attachments/assets/27acc4ec-a2a2-4142-9a3b-7398017eb806" />
<br>
```bash 
cat awx_ssh_key
```
copy the private key on awx
<img width="975" height="414" alt="image" src="https://github.com/user-attachments/assets/8722cc8b-09b1-4b7f-a067-cdf6678dd9fa" />
<br>
# Create a project
 <img width="975" height="491" alt="image" src="https://github.com/user-attachments/assets/fe1caf39-7137-45c7-9335-0e35d9c7d72a" />
<br>

- Source controlURL is from your git-repository
<img width="975" height="416" alt="image" src="https://github.com/user-attachments/assets/bd49a921-b0c8-4aed-ba5e-a248c7354d41" />
<br>


Wait for the project to synchronize: AWX will automatically synchronize the project with the Git repository. You can monitor the progress in the “Projects” tab.

# Creating a new inventory:
o	Navigate to the “Inventories” tab and click “Add”.
o	Name your inventory and define it as needed.
o	In the inventory, you can add groups and hosts that will be the target of your Ansible playbooks.

# Creating a job template:
o	Navigate to the “Templates” tab and click “Add” → “Job Template”.
o	Name the template, select the project you created earlier, and the playbook you want to run.
o	Select the inventory you will use.
o	In the “Credentials” section, add the credentials necessary to connect to your servers (e.g., SSH keys).
o	Save the template.

# Add your own execution environment
```bash
sudo apt-get install python3-pip -y
sudo pip install ansible-builder

sudo mkdir /opt/stack/ee/awx-ee
cd /opt/stack/ee/awx-ee
```
put following content into execution-environment.yml

```YAML
---
version: 3
images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

dependencies:
  ansible_core:
    package_pip: ansible-core
  ansible_runner:
    package_pip: ansible-runner
  python:
    - setuptools
    - psycopg2-binary
    - gitpython
    - pymysql
    - mysql-connector-python
    - requests
    - netmiko
    - pyats
    - httpx
    - beautifulsoup4
    - lxml
    - python-dateutil
    - pytz
    - pymongo
    - cryptography
    - bcrypt
    - boto3
    - azure-mgmt-resource
    - azure-storage-blob
    - pexpect
    - paramiko-expect
    - paramiko
  galaxy:
    collections:
      - name: check_point.mgmt
      - name: check_point.gaia
      - name: ansible.netcommon
  system:
    - git
    - sshpass
    - docker
    - subversion
    - gcc
    - make
    - python3-devel
    - openssl-devel
    - libffi-devel
    - libxml2-devel
    - libxslt-devel

additional_build_steps:
  prepend_builder:
    - RUN /usr/bin/python3 -m pip install --upgrade pip setuptools wheel
    - RUN pip config set global.index-url https://pypi.org/simple
    - RUN pip config set global.timeout 600
    - RUN pip config set global.retries 5
    - ENV PIP_DEFAULT_TIMEOUT=600
    - ENV PIP_NO_CACHE_DIR=1
```
now run following commands after providing your domain name

```bash
REGISTRY_HOST=registry.<DOMAIN>
sudo cd /opt/stack/ee/awx-ee
sudo ansible-builder build -t ${REGISTRY_HOST}/awx-ee:cp-gaia-mgmt -f execution-environment.yml --container-runtime docker

sudo mkdir -p /etc/docker/certs.d/registry.fritz.lan
sudo cp "$(sudo mkcert -CAROOT)/rootCA.pem" /etc/docker/certs.d/registry.fritz.lan/ca.crt
sudo systemctl restart docker

# pick the primary IP of this node
IP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src"){print $(i+1); exit}}')

# add your app FQDNs (idempotent-ish)
sudo bash -lc 'IP='"$IP"'; for h in registry.fritz.lan gitlab.fritz.lan awx.fritz.lan pma.fritz.lan; do
  grep -qE "^[[:space:]]*$IP[[:space:]]+$h([[:space:]]|\$)" /etc/hosts || echo "$IP $h" >> /etc/hosts
done'


printf 'ChangeMe!Reg123' | docker login http://127.0.0.1:5000 -u awx --password-stdin
sudo docker push registry.<DOMAIN>/awx-ee:cp-gaia-mgmt
```
sanity check
```bash
curl -s --user "${REGISTRY_USER}:${REGISTRY_PASS}" https://${REGISTRY_HOST}/v2/_catalog
```
-> should list {"repositories":["awx-ee"]} 

# execution env-check: verify end-to-end
kubectl -n awx run reg-check --image=${REGISTRY_HOST}/awx-ee:cp-gaia-mgmt --restart=Never --command -- sleep 1
kubectl -n awx logs reg-check || true
kubectl -n awx delete pod reg-check

# Use it in AWX without a registry (same Docker host)
In the AWX UI:<br>
Credentials → Add → “Container Registry”<br>
Registry URL: https://${REGISTRY_HOST}<br>
Username/Password: ${REGISTRY_USER} / ${REGISTRY_PASS}<br>
Administration → Execution Environments → Add<br>
Name: “Local EE”<br>
Image: ${REGISTRY_HOST}/awx-ee:cp-gaia-mgmt<br>
Pull: Always (at least initially)<br>
Credential: the Container Registry credential from step 1<br>
Use this EE on your Job Template (or set as default).<br>
AWX will auto-create a Kubernetes imagePullSecret from the Container Registry credential and <br>
attach it to the job pod. With our CoreDNS patch and k3s trust in place, the pull succeeds fully locally.

<img width="1641" height="776" alt="image" src="https://github.com/user-attachments/assets/e8b9222b-57d3-4050-a117-199428d729f0" />


Assign it on your Organization or Job Template


# Verify in awx
Run a test job with a simple playbook:
```yaml
- hosts: localhost
  gather_facts: no
  tasks:
    - command: ansible-galaxy collection list
      register: result
    - debug: var=result.stdout
```

Troubleshooting notes

x509 / unknown authority when k3s pulls<br>
Make sure ensure_registry_trust_for_k3s ran: the mkcert root CA must be in /usr/local/share/ca-certificates/mkcert-rootCA.crt, update-ca-certificates succeeded, and systemctl restart k3s was done.<br>
Also confirm /etc/rancher/k3s/registries.yaml exists and points tls.ca_file to that cert.<br>

Name resolution failure:<br>
Re-run --dns-patch (or any flow that calls patch_coredns_hosts). Ensure ${REGISTRY_HOST} appears in CoreDNS NodeHosts and in your AWX host_aliases.<br>

Auth denied:<br>
Confirm the Container Registry credential is associated with the Execution Environment.<br>
Manually docker login https://${REGISTRY_HOST} on the host to verify creds.<br>

Already-generated cert without registry hostname:<br>
Remove $CERT_PEM and $CERT_KEY, then re-run --certs to include ${REGISTRY_HOST}.<br>

# ip address of mysql docker compose 
```bash
sudo docker ps
sudo docker inspect -f '{{.Name}} -> {{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' compose-mysql-1
```
<img width="1757" height="236" alt="image" src="https://github.com/user-attachments/assets/f4e7d14d-d283-4565-b03e-56359706c102" />

You should see check_point.mgmt and check_point.gaia in the output.
