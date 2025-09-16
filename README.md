# how to install:
set env variable for the installation session
eg:
```bash
   export AWX_ADMIN_PASS='myawxPassword'<br>
   export MYSQL_ROOT_PASSWORD='myMysqlRootPW'<br>
   export MYSQL_PASS='myMysqlAppPW'<br>
   curl -sSL https://raw.githubusercontent.com/airani051346/Ubution/refs/heads/main/install.sh | bash
```

# how to access GitLab::<br>
  URL:  https://< server-ip >:4443
  SSH:  ssh -p 2222 git@<server-ip>
  Initial root password: (will be shown after installlation)

# how to access phpMyAdmin:<br> 
  URL:  https://< server-ip >:4444
  MySQL root login is enabled remotely (root / zubur1RootPW)
# Import Database and Sampple Data
  import netvars.sql file in SQL-DB folder <br>
  additional priviligaes for the ansible user<br>

```sql
CREATE USER IF NOT EXISTS 'ansible'@'%' IDENTIFIED BY 'ChangeMe';
CREATE USER IF NOT EXISTS 'ansible'@'127.0.0.1' IDENTIFIED BY 'ChangeMe';
GRANT SELECT ON netvars.* TO 'ansible'@'%';
GRANT SELECT ON netvars.* TO 'ansible'@'127.0.0.1';
FLUSH PRIVILEGES;
```

# Data Viewer:
  URL:  https://< server-ip >:4445
  Visit /init once to create a demo table.

# how to access AWX:<br>
  URL:  https://< server-ip >:4446
  User: admin
  Pass: (what you set) or fetch with:
        kubectl get secret -n awx awx-admin-password -o jsonpath="{.data.password}" | base64 --decode; echo

Files live under:
  /opt/stack/compose
  /opt/stack/k8s

Note: Browser will warn about the self-signed certificate (expected).
If you were just added to the 'docker' group, open a new terminal or run 'newgrp docker' to use Docker without sudo.


# Download git-rep.
Go to https://github.com/airani051346/Ubution
<img width="975" height="451" alt="image" src="https://github.com/user-attachments/assets/2626e3f3-3c2f-4e45-a3a4-9948eb1b600d" />

- extract zip to your local storage
  <img width="664" height="435" alt="image" src="https://github.com/user-attachments/assets/ce7c9de2-66f5-4fc4-a575-1d3c31622977" />

- Open the folder Ubution-main\git-project
  <img width="763" height="184" alt="image" src="https://github.com/user-attachments/assets/c452f7a9-0ea6-47a5-b885-8938814dfc77" />


# Login to gitlab
https://<server-ip>:4443//users/sign_in
<img width="663" height="522" alt="image" src="https://github.com/user-attachments/assets/e9545ca1-f3bd-4c36-94d3-fb7608f12b9b" />

 
- Create a blank project (pub-deploy-cp)
https://<server-ip>:4443/projects/new#blank_project 
<img width="732" height="328" alt="image" src="https://github.com/user-attachments/assets/990852a0-445d-4305-bb1a-7a387ac1e3f2" />
<img width="494" height="208" alt="image" src="https://github.com/user-attachments/assets/0a8557a7-2eba-41bb-9b08-12c3e7f81b17" />
<img width="975" height="802" alt="image" src="https://github.com/user-attachments/assets/259d9a0a-6e57-4e2b-b1ef-e249ebd1bd9c" />

 
# Upload the git files
The easiest way to do this is over the web-editor ide
<img width="672" height="619" alt="image" src="https://github.com/user-attachments/assets/6e1f9202-833e-4714-b5f7-8e6a34fa1fbe" />

Now you can drag the folders into your new project
<img width="820" height="359" alt="image" src="https://github.com/user-attachments/assets/9fd4e042-a5e3-4637-904b-01396eea8727" />
 
Commit change is necessary to close anychange in your repository
<img width="433" height="297" alt="image" src="https://github.com/user-attachments/assets/398ccd75-d974-422a-868d-ad55d96343d6" />
<img width="419" height="288" alt="image" src="https://github.com/user-attachments/assets/2335b2a4-765c-4963-946c-4dbb624f623d" />


Create ssh key for awx and gitlab integration
```bash
sudo ssh-keygen -N '' -f awx_ssh_key
sudo cat awx_ssh_key.pub
copy the pub key here in gitlab
<img width="975" height="355" alt="image" src="https://github.com/user-attachments/assets/27acc4ec-a2a2-4142-9a3b-7398017eb806" />
	 
cat awx_ssh_key
```
copy the private key on awx
<img width="975" height="414" alt="image" src="https://github.com/user-attachments/assets/8722cc8b-09b1-4b7f-a067-cdf6678dd9fa" />

# Create a project
 <img width="975" height="491" alt="image" src="https://github.com/user-attachments/assets/fe1caf39-7137-45c7-9335-0e35d9c7d72a" />

- Source controlURL is from your git-repository
<img width="975" height="416" alt="image" src="https://github.com/user-attachments/assets/bd49a921-b0c8-4aed-ba5e-a248c7354d41" />


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
mkdir ~/custim-ee && cd custim-ee
vi execution-environment.yml
```

put following content in the execution-environment.yml file
```text
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
    # base tools
    - git
    - sshpass
    - docker
    - subversion
    # build deps to avoid source build failures (safe to include)
    - gcc
    - make
    - python3-devel
    - openssl-devel
    - libffi-devel
    - libxml2-devel
    - libxslt-devel

additional_build_steps:
  # This runs in the *builder* stage, before /output/scripts/assemble
  prepend_builder:
    - RUN /usr/bin/python3 -m pip install --upgrade pip setuptools wheel
    - RUN pip config set global.index-url https://pypi.org/simple
    - RUN pip config set global.timeout 600
    - RUN pip config set global.retries 5
    - ENV PIP_DEFAULT_TIMEOUT=600
    - ENV PIP_NO_CACHE_DIR=1

```

now run following command to create your run-time environment
```bash
ansible-builder build -t awx-ee:cp-gaia-mgmt   --container-runtime=docker  --build-arg PIP_DEFAULT_TIMEOUT=600
```



