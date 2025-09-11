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
  URL:  https://<server-ip>:4443
  SSH:  ssh -p 2222 git@<server-ip>
  Initial root password: (will be shown after installlation)

# how to access phpMyAdmin:<br> 
  URL:  https://<server-ip>:4444
  MySQL root login is enabled remotely (root / zubur1RootPW)

# Data Viewer:
  URL:  https://<server-ip>:4445
  Visit /init once to create a demo table.

# how to access AWX:<br>
  URL:  https://<server-ip>:4446
  User: admin
  Pass: (what you set) or fetch with:
        kubectl get secret -n awx awx-admin-password -o jsonpath="{.data.password}" | base64 --decode; echo

Files live under:
  /opt/stack/compose
  /opt/stack/k8s

Note: Browser will warn about the self-signed certificate (expected).
If you were just added to the 'docker' group, open a new terminal or run 'newgrp docker' to use Docker without sudo.




# ###############################################################
Download git-rep.
Go to https://github.com/airani051346/Ubution

extract zip to your local storage
Open the folder Ubution-main\git-project


Login to gitlab
https://<server-ip>:4443//users/sign_in
 
Create a blank project (pub-deploy-cp)
https://<server-ip>:4443/projects/new#blank_project 

 
 
Upload the git files
The easiest way to do this is over the web-editor ide

 

Now you can drag the folders into your new project
 
Commit change is necessary to close anychange in your repository
    

Create ssh key for awx and gitlab integration
sudo ssh-keygen -N '' -f awx_ssh_key
sudo cat awx_ssh_key.pub
copy the pub key here in gitlab
	 
	
	cat awx_ssh_key
	copy the private key on awx
 

Create a project
 
	
Source controlURL is from your git-repository
 



 

Wait for the project to synchronize: AWX will automatically synchronize the project with the Git repository. You can monitor the progress in the “Projects” tab.
Creating a new inventory:
o	Navigate to the “Inventories” tab and click “Add”.
o	Name your inventory and define it as needed.
o	In the inventory, you can add groups and hosts that will be the target of your Ansible playbooks.
Creating a job template:
o	Navigate to the “Templates” tab and click “Add” → “Job Template”.
o	Name the template, select the project you created earlier, and the playbook you want to run.
o	Select the inventory you will use.
o	In the “Credentials” section, add the credentials necessary to connect to your servers (e.g., SSH keys).
o	Save the template.




---
- name: Update all systems and restart if needed only if updates are available
  hosts: all
  become: yes
  tasks:
    # Preliminary checks for available updates
    - name: Check for available updates (apt)
      apt:
        update_cache: yes
        upgrade: 'no' # Just check for updates without installing
        cache_valid_time: 3600 # Avoid unnecessary cache updates
      register: apt_updates
      changed_when: apt_updates.changed
      when: ansible_facts['os_family'] == "Debian"

    # Update systems based on the checks
    # Debian-based systems update and restart
    - name: Update apt systems if updates are available
      ansible.builtin.apt:
        update_cache: yes
        upgrade: dist
      when: ansible_facts['os_family'] == "Debian" and apt_updates.changed

    - name: Check if restart is needed on Debian based systems
      stat:
        path: /var/run/reboot-required
      register: reboot_required_file
      when: ansible_facts['os_family'] == "Debian" and apt_updates.changed

    - name: Restart Debian based system if required
      ansible.builtin.reboot:
      when: ansible_facts['os_family'] == "Debian" and apt_updates.changed and reboot_required_file.stat.exists





•	hosts: all: Specifies that the playbook will be run on all hosts defined in your inventory.
•	become: yes: Elevates privileges to root (similar to sudo), which is required for package management.
•	tasks: The section of tasks, where each task updates systems with different package managers depending on the operating system family.
•	when: A condition that checks the type of operating system of the host to execute the appropriate update command.
•	ansible.builtin.<module>: The Ansible module responsible for managing packages on different operating systems.
•	stat module: Used to check for the presence of the /var/run/reboot-required file in Debian-based systems, which is created when an update requires a restart.
•	reboot module: Triggers a system restart if needed. You can customize this module by adding parameters such as msg for the restart message, pre_reboot_delay for a delay before restarting, etc.
•	register: Stores the result of the command or check in a variable that can later be used in conditions (when).

