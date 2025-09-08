#how to install:
set env variable for the installation session

export AWX_ADMIN_PASS='myawxPassword'<br>
export MYSQL_ROOT_PASSWORD='myMysqlRootPW'<br>
export MYSQL_PASS='myMysqlAppPW'<br>

#next step is the installation:
        curl -sSL https://github.com/airani051346/Ubution/blob/main/install.sh | bash



#how to access AWX:
       open http://<your-host-ip>:30080, login with the admin credentials shown.

#how to access gitlab:
        http://localhost:8080 (first login sets root password).

#how to access phpMyAdmin: 
        http://localhost:8081 (use MySQL creds from the output).

#how to access Demo web app: 
        http://localhost:8082 → click Init once, then browse data.


If you want HTTPS and domains, you can later put Nginx/Traefik in front and add TLS, or switch AWX to ingress_type: ingress and supply a TLS secret (the operator supports both patterns). 
ansible.readthedocs.io
