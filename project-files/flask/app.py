from flask import Flask, render_template, request, redirect, url_for, flash
import subprocess
import os

app = Flask(__name__)
app.secret_key = "supersecret"  # change in production

# Path to your Ansible playbooks
ANSIBLE_DIR = "/home/cpadmin/ubution"

@app.route("/")
def index():
    return render_template("index.html")

# ---- Flow 1: Single Gateway ----
@app.route("/gateway", methods=["GET", "POST"])
def gateway():
    if request.method == "POST":
        gw_name = request.form["gw_name"]
        gw_ip = request.form["gw_ip"]
        gw_type = request.form["gw_type"]  # spark or full

        playbook = os.path.join(ANSIBLE_DIR, "create_gateway.yml")
        cmd = [
            "ansible-playbook",
            playbook,
            "-i", f"{ANSIBLE_DIR}/Inventory.yml",
            "-e", f"inventory_hostname={gw_name} ansible_host={gw_ip} gaia_mode={gw_type}"
        ]

        try:
            subprocess.run(cmd, check=True)
            flash(f"Gateway {gw_name} ({gw_type}) created successfully!", "success")
        except subprocess.CalledProcessError as e:
            flash(f"Error creating gateway: {e}", "danger")

        return redirect(url_for("index"))
    return render_template("gateway.html")


# ---- Flow 2: Cluster ----
@app.route("/cluster", methods=["GET", "POST"])
def cluster():
    if request.method == "POST":
        cluster_name = request.form["cluster_name"]
        member1 = request.form["member1"]
        member1_type = request.form["member1_type"]
        member2 = request.form["member2"]
        member2_type = request.form["member2_type"]

        playbook = os.path.join(ANSIBLE_DIR, "create_cluster.yml")
        cmd = [
            "ansible-playbook",
            playbook,
            "-i", f"{ANSIBLE_DIR}/Inventory.yml",
            "-e", f"cluster_name={cluster_name} member1={member1} member1_type={member1_type} member2={member2} member2_type={member2_type}"
        ]

        try:
            subprocess.run(cmd, check=True)
            flash(f"Cluster {cluster_name} created with members {member1}, {member2}", "success")
        except subprocess.CalledProcessError as e:
            flash(f"Error creating cluster: {e}", "danger")

        return redirect(url_for("index"))
    return render_template("cluster.html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
