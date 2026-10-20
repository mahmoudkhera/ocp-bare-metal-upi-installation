# OpenShift Lab: Network Configuration and firewalld 

## 0. Configure Environmental Services

**1: Boot the helper VM**

**2: Move the downloaded files to the helper node**

Move the files downloaded from the Red Hat Cluster Manager site to the helper node. Create the destination folder on the helper first. Run this on the helper:

```bash
mkdir -p ~/openshift-metal/UPI-data
```

Then, on your own computer, copy the files:

```bash
scp ~/Downloads/openshift-install-linux.tar.gz ~/Downloads/openshift-client-linux.tar.gz ~/Downloads/rhcos-metal.x86_64.raw.gz ocp@{helper_IP_address}:~/openshift-metal/UPI-data/
```

**3: SSH to the helper VM**

```bash
ssh ocp@{helper_IP_address}
```

**4: Extract the client tools and copy them to /usr/local/bin**

```bash
tar xvf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin
```

**5: Confirm the client tools are working**

```bash
kubectl version --client
oc version --client
```

**6: Extract the OpenShift installer**

```bash
tar xvf openshift-install-linux.tar.gz
```

**7: Update RHEL**

Update the system so you get the latest packages for each of the services you are about to install:

```bash
sudo dnf update -y
```

**8: Install Git**

```bash
sudo dnf install -y git
```

## 1. NIC and network zones configuration

**1: Find the NetworkManager connection profile**

```bash
nmcli connection show
```

Important: The connection profile name may differ from the interface name. For example, the profile might be `Wired connection 1` or `ens33`.

Open the network configuration editor:

```bash
nmtui-edit
```

Select the connection profile associated with ens37 that is connected to the OCP network.

**2: Configure IPv4 settings of ens37**

| Setting | Value |
|---|---|
| IPv4 Configuration | Manual |
| Address | 192.168.10.1/24 |
| Gateway | Leave empty |
| DNS server | 127.0.0.1 |
| Search domain | ocp.internal |
| Never use this network for default route | Enabled |
| Automatically connect | Enable if the NIC should connect at boot |

Address conflict: Check whether 192.168.10.1 is already in use before assigning it. Choose an unused address in the 192.168.10.0/24 subnet.

DNS field missing? Select IPv4 CONFIGURATION, choose `<Show>`, and press Enter to reveal additional fields.

**3: Activate the connection**

Saving the configuration does not necessarily activate it. Bring the connection up using its actual profile name:

```bash
nmcli connection up "PROFILE_NAME"
```

If the profile is named ens37, you can use:

```bash
nmcli connection up ens37
```

**4: Verify the configuration**

```bash
ip address show ens37
nmcli device status
nmcli connection show
```

Confirm that ens37 has the expected static IPv4 address and is connected.

**5: Enable automatic connection after reboot**

Find the connection profile associated with ens37, then enable autoconnect:

```bash
nmcli connection modify "PROFILE_NAME" connection.autoconnect yes
```

For a profile actually named ens37:

```bash
nmcli connection modify ens37 connection.autoconnect yes
```

Note: The interface must also be enabled and set to connect at power-on in VMware Workstation.

## 2. Install firewalld

Install firewalld on RHEL:

```bash
sudo dnf install firewalld -y
sudo systemctl enable --now firewalld
sudo systemctl status firewalld
```

## 3. Create Internal and External Zones

- Internal zone: for the trusted OCP internal network.
- External zone: for the network connected to the outside world.

Create both zones:

```bash
sudo firewall-cmd --permanent --new-zone=internal
sudo firewall-cmd --permanent --new-zone=external
sudo firewall-cmd --reload
```

If either zone already exists (RHEL ships with both), you do not need to create it again.

## 4. Assign Network Interfaces to Zones

Example interface assignments:

- ens37 → internal
- ens33 → external

```bash
sudo nmcli connection modify "ens37" connection.zone internal
sudo nmcli connection modify "ens33" connection.zone external
```

Replace the quoted names with the actual NetworkManager connection profile names if they differ from the interface names.

Check the active zones:

```bash
sudo firewall-cmd --get-active-zones
```

If necessary, reactivate the connection for the new zone assignment to take effect:

```bash
sudo nmcli connection up "ens33"
sudo nmcli connection up "ens37"
```

## 5. Enable Masquerading

Masquerading changes the source IP address of outgoing packets to the address of the outgoing interface. This allows internal hosts using private IP addresses to access external networks.

Enable masquerading on the external zone:

```bash
sudo firewall-cmd --zone=external --add-masquerade --permanent
```

Enable masquerading on the internal zone:

```bash
sudo firewall-cmd --zone=internal --add-masquerade --permanent
```

## 6. Reload firewalld

Apply permanent configuration changes:

```bash
sudo firewall-cmd --reload
```

## 7. Verify Zone Settings

Check each zone:

```bash
sudo firewall-cmd --list-all --zone=internal
sudo firewall-cmd --list-all --zone=external
```

Look for the following in the relevant zone output: `masquerade: yes`

Also confirm the expected interfaces are assigned to the correct zones.

## 8. Enable and Verify IP Forwarding

Masquerading and IP forwarding are different functions:

- Masquerading: translates source IP addresses.
- IP forwarding: allows the Linux host to route packets between network interfaces.

Check IPv4 forwarding:

```bash
sysctl net.ipv4.ip_forward
```

Expected output: `net.ipv4.ip_forward = 1`

Enable forwarding temporarily:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Enable forwarding persistently:

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl --system
```

Enabling masquerading does not guarantee that kernel forwarding is enabled. Verify both settings when configuring a Linux router.

## 2. DNS Configuration (BIND)

**1: Install**

```bash
sudo dnf install -y bind bind-utils
```

**2: Back up the original and write the new file**

```bash
sudo cp /etc/named.conf /etc/named.conf.orig
sudo cp ~/openshift-metal/UPI-data/dns/named.conf /etc/named.conf
```

**3: Zone files**

```bash
sudo cp ~/openshift-metal/UPI-data/dns/ocp.internal.zone /var/named/ocp.internal.zone
sudo cp ~/openshift-metal/UPI-data/dns/10.168.192.in-addr.arpa.zone /var/named/10.168.192.in-addr.arpa.zone
sudo chown -R root:named /var/named/ocp.internal.zone /var/named/10.168.192.in-addr.arpa.zone
sudo chmod 640 /var/named/ocp.internal.zone /var/named/10.168.192.in-addr.arpa.zone
sudo restorecon -Rv /var/named
```

**4: Log directory**

SELinux must allow named to write to `/var/log/named/`.

```bash
sudo mkdir -p /var/log/named
sudo chown named:named /var/log/named
sudo semanage fcontext -a -t named_log_t "/var/log/named(/.*)?"
sudo restorecon -Rv /var/log/named
```

**5: Firewall**

```bash
sudo firewall-cmd --add-port=53/udp --zone=internal --permanent
```

OpenShift (OCP) 4.9 and later can produce larger DNS responses, for example when a name has many records (several API or ingress addresses, SRV records for etcd, and so on). Those can exceed the UDP size limit, so the cluster nodes and the installer need to be able to fall back to TCP. If your firewall only allows 53/udp, those retries get blocked and you can see intermittent or confusing failures.

```bash
sudo firewall-cmd --add-port=53/tcp --zone=internal --permanent
sudo firewall-cmd --reload
```

**6: Validate**

```bash
sudo rndc reload
sudo named-checkconf
sudo named-checkzone ocp.internal /var/named/ocp.internal.zone
sudo named-checkzone 10.168.192.in-addr.arpa /var/named/10.168.192.in-addr.arpa.zone
```

**7: Start**

```bash
sudo systemctl enable named
sudo systemctl start named
sudo systemctl status named
```

The DNS will still be pointing to the LAN DNS server. You can see this with `dig ocp.lan`.

**8: Point the LAN NIC to the local DNS server**

Change the LAN NIC (ens33) to use `127.0.0.1` for DNS **and** ensure `Ignore automatically obtained DNS parameters` is ticked.

```bash
nmtui-edit ens33
```

Restart NetworkManager:

```bash
systemctl restart NetworkManager
```

Confirm dig now sees the correct DNS results by using the DNS server running locally:

```bash
dig ocp.internal
```

## 3. DHCP Server Installation

**1: Install**

```bash
sudo dnf install -y dhcp-server
```

**2: Find your interface name**

```bash
ip -br a
```

The server must already have 192.168.10.1 on that interface. If it doesn't, set it with nmtui first, or dhcpd will fail with `No subnet declaration`.

**3: Set the interface**

On RHEL, dhcpd automatically listens on the interface whose address matches the `subnet` declaration in `dhcpd.conf`. No interface file needs editing. Just confirm the interface holds 192.168.10.1 (`ip -br a`).

**4: Write your config**

Back up the original:

```bash
sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.orig
```

Edit `dhcpd.conf` from the cloned git repo to have the correct MAC address for each host, then copy the file to the location the DHCP service uses:

```bash
sudo cp ~/openshift-metal/UPI-data/dhcpd.conf /etc/dhcp/dhcpd.conf
```

**5: Configure the firewall**

```bash
sudo firewall-cmd --add-service=dhcp --zone=internal --permanent
sudo firewall-cmd --reload
```

**6: Validate, start, enable**

```bash
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
sudo systemctl restart dhcpd
sudo systemctl enable dhcpd
sudo systemctl status dhcpd
```

Before it will work for clients:

- Only one DHCP server may run on the network. If your router also hands out addresses, turn its DHCP off.
- Gateway: `option routers 192.168.10.1` only works if this RHEL machine actually routes or NATs traffic. If your real router is another device, change that line to the router's IP, or clients will have no internet.
- DNS: BIND must use the same subnet (192.168.10.0/24, DNS at 192.168.10.1). The acl, listen-on, reverse zone name (10.168.192.in-addr.arpa), and zone records all need to match. Otherwise DHCP clients will be told to use a DNS server that refuses their queries.

## 4. NFS Server for the Registry

You should use a mirror registry instead.

**1: Install**

```bash
sudo dnf install -y nfs-utils
```

**2: Create the share**

Check free space on each disk and where it is mounted:

```bash
df -h
```

Create the directory. `-p` creates /shares too if missing, and doesn't complain if it exists:

```bash
sudo mkdir -p /shares/registry
```

Make the directory owned by the unprivileged nobody user:

```bash
sudo chown -R nobody:nobody /shares/registry
```

This matters because of root_squash below: when a remote root user writes, NFS maps them to nobody. If the directory belonged to root, that mapped user couldn't write.

Give read, write, and execute to everyone:

```bash
sudo chmod -R 777 /shares/registry
```

The registry pod in OpenShift runs under a random user ID, not a known one, so open permissions are the simplest way to ensure it can write. This is acceptable in a lab, but it is loose. The real access control is the subnet limit in /etc/exports, so keep that tight.

Allow NFS to export the directory under SELinux:

```bash
sudo setsebool -P nfs_export_all_rw on
```

**3: Export the share**

```bash
echo "/shares/registry  192.168.10.0/24(rw,sync,root_squash,no_subtree_check,no_wdelay)" | sudo tee /etc/exports
```

Use this instead if you want to keep existing exports:

```bash
echo "/shares/registry  192.168.10.0/24(rw,sync,root_squash,no_subtree_check,no_wdelay)" | sudo tee -a /etc/exports
```

The line has the format `path client(options)`:

| Part | Meaning |
|---|---|
| /shares/registry | The directory to share. |
| 192.168.10.0/24 | Who may mount it: only machines on your lab network. |
| rw | Clients can read and write. |
| sync | The server confirms a write only after it reaches disk. Safer against data loss on a crash, a bit slower. Important for a registry. |
| root_squash | A client's root user is mapped to nobody. A compromised node can't act as root on the share. |
| no_subtree_check | Skips a check of whether each file is inside the exported tree. Avoids problems when files are renamed while open, and is the recommended default. |
| no_wdelay | Don't wait for more writes before committing. It improves latency, and only matters together with sync. |

Apply the exports:

```bash
sudo exportfs -rv
```

This re-reads /etc/exports and applies it without restarting. `-r` is re-export all, `-v` is verbose. Expected output: `exporting 192.168.10.0/24:/shares/registry`

Check the active exports any time with `sudo exportfs -v`.

**4: Firewall rules**

Your server uses firewalld, and the lab network is in the internal zone, so open NFS there:

```bash
sudo firewall-cmd --zone=internal --add-service=nfs --permanent
sudo firewall-cmd --zone=internal --add-service=mountd --permanent
sudo firewall-cmd --zone=internal --add-service=rpc-bind --permanent
sudo firewall-cmd --reload
```

If you use only NFSv4 (the default on modern clients, and what OpenShift uses), `nfs` alone is enough. The other two are harmless and give NFSv3 compatibility.

Verify:

```bash
sudo firewall-cmd --zone=internal --list-services
```

**5: Enable and start the services**

```bash
sudo systemctl enable --now nfs-server rpcbind
```

Check:

```bash
sudo systemctl status nfs-server
```

**6: Test the share**

On the server:

```bash
sudo exportfs -v
showmount -e localhost
```

Expected:

```
Export list for localhost:
/shares/registry 192.168.10.0/24
```

From a client on the lab network (any RHEL machine in 192.168.10.0/24, for example the bastion):

```bash
sudo dnf install -y nfs-utils
showmount -e 192.168.10.2
sudo mkdir -p /mnt/test
sudo mount -t nfs 192.168.10.2:/shares/registry /mnt/test
touch /mnt/test/hello && ls -l /mnt/test
sudo umount /mnt/test
```

If touch works, read and write are fine. The file will be owned by nobody:nobody, which shows root_squash mapping in action.

## 5. HAProxy Load Balancer

**1: Install HAProxy**

```bash
sudo dnf install -y haproxy
```

**2: Copy the HAProxy config**

Back up the original, then copy the config from the cloned git repo:

```bash
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig
sudo cp ~/openshift-metal/UPI-data/haproxy.cfg /etc/haproxy/haproxy.cfg
```

**3: Configure the firewall**

Note: Opening port 9000 in the external zone allows access to the HAProxy stats page, which is useful for monitoring and troubleshooting. The UI can be accessed at `http://{ocp-svc_IP_address}:9000/stats`

```bash
sudo firewall-cmd --add-port=6443/tcp --zone=internal --permanent
sudo firewall-cmd --add-port=6443/tcp --zone=external --permanent
sudo firewall-cmd --add-port=22623/tcp --zone=internal --permanent
sudo firewall-cmd --add-service=http --zone=internal --permanent
sudo firewall-cmd --add-service=http --zone=external --permanent
sudo firewall-cmd --add-service=https --zone=internal --permanent
sudo firewall-cmd --add-service=https --zone=external --permanent
sudo firewall-cmd --add-port=9000/tcp --zone=external --permanent
sudo firewall-cmd --reload
```

**4: Validate the configuration**

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

It should print `Configuration file is valid`. Warnings about `option httplog` or `option forwardfor` in TCP-mode sections are harmless.

**5: Enable and start the service**

Allow HAProxy to connect to the backend ports under SELinux:

```bash
sudo setsebool -P haproxy_connect_any 1
sudo systemctl enable haproxy
sudo systemctl start haproxy
```

## 6. Apache Web Server

**1: Install Apache**

```bash
sudo dnf install -y httpd
```

**2: Change the listen port to 8080**

```bash
sudo sed -i 's/^Listen 80$/Listen 0.0.0.0:8080/' /etc/httpd/conf/httpd.conf
```

Why change to 8080? In an OpenShift lab, the bastion machine often runs a load balancer (HAProxy) on ports 80 and 443 for the cluster ingress, and Apache is only there to serve files (such as ignition files) to the nodes. Moving Apache to 8080 avoids a port conflict.

Check the edit:

```bash
grep -n "^Listen" /etc/httpd/conf/httpd.conf
```

Allow Apache to use port 8080 under SELinux:

```bash
sudo semanage port -a -t http_port_t -p tcp 8080
```

**3: Open the firewall**

Your lab network is in the internal zone, so open the port there:

```bash
sudo firewall-cmd --add-port=8080/tcp --zone=internal --permanent
sudo firewall-cmd --reload
```

**4: Validate, enable, and start**

```bash
sudo apachectl configtest
```

This checks the syntax. It should print `Syntax OK`. A warning like `Could not reliably determine the server's fully qualified domain name` is harmless.

Then:

```bash
sudo systemctl enable httpd
sudo systemctl restart httpd
```

**5: Test**

```bash
curl localhost:8080
```

## 7. Create the OpenShift Install Files

**1: Create an install directory**

```bash
mkdir ~/ocp-install
```

**2: Copy install-config.yaml**

Copy the install-config.yaml included in the cloned repository to the install directory:

```bash
cp ~/openshift-metal/UPI-data/install-config.yaml ~/ocp-install
```

**3: Update install-config.yaml**

Update install-config.yaml with your own pull secret and SSH key:

- Line 23 should contain the contents of your pull-secret.txt.
- Line 24 should contain the contents of your ~/.ssh/id_rsa.pub.

```bash
vim ~/ocp-install/install-config.yaml
```

Tip: openshift-install deletes install-config.yaml when it creates the manifests. Keep a backup first: `cp ~/ocp-install/install-config.yaml ~/install-config.yaml.bak`

**4: Generate the manifests and ignition files**

Generate the Kubernetes manifest files:

```bash
~/openshift-install create manifests --dir ~/ocp-install
```

A warning is shown about making the control plane nodes schedulable. It is up to you whether to run workloads on the control plane nodes. If you don't want to, disable it with:

```bash
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' ~/ocp-install/manifests/cluster-scheduler-02-config.yml
```

Make any other custom changes you like to the core Kubernetes manifest files.

Generate the ignition config and Kubernetes auth files:

```bash
~/openshift-install create ignition-configs --dir ~/ocp-install/
```

**5: Create a hosting directory**

This directory serves the configuration files for the OpenShift boot process:

```bash
sudo mkdir /var/www/html/ocp4
```

**6: Copy the generated files to the web server directory**

```bash
sudo cp -R ~/ocp-install/* /var/www/html/ocp4
```

**7: Move the CoreOS image to the web server directory**

You will type this path several times later, so shorten the name:

```bash
sudo mv ~/rhcos-X.X.X-x86_64-metal.x86_64.raw.gz /var/www/html/ocp4/rhcos
```

**8: Change ownership and permissions**

```bash
sudo chown -R apache: /var/www/html/ocp4/
sudo chmod 755 /var/www/html/ocp4/
sudo restorecon -RFv /var/www/html/ocp4/
```

**9: Confirm the files are served by Apache**

```bash
curl localhost:8080/ocp4/
```

You should see a directory listing with bootstrap.ign, master.ign, worker.ign, rhcos and the other files.

# 7.Make the ocp-infra
Terraform creates the VMs for an OpenShift bare-metal UPI cluster on Proxmox.
The VMs are created empty with the RHCOS live ISO attached. They are not started.


These are general settings for every platform:

- **Guest OS:** Linux, "Red Hat Enterprise Linux 9 64-bit" (or "Other Linux 64-bit").
- **CD/DVD:** attach `rhcos-live-iso.x86_64.iso` and connect it at power on.
- **Network:** put every node on the same internal network as the helper's internal NIC (`ens37`).
- **No second DHCP server:** turn off any built-in DHCP on that network. The helper is the only DHCP server.
- **MAC address:** the MAC of each VM must match its reservation in `dhcpd.conf`. Set it before the first boot.
- **Boot order:** CD/DVD first for the install, hard disk first afterwards.


## Files


| File | Purpose |
|---|---|
| `main.tf` | Provider and VM definition |
| `variable.tf` | Declares the variables and their defaults |
| `terraform.tfvars` | Your values, including the list of VMs |
> overwrite the terraform code depending on the hypervisor provider that you use


## 1:Start the ocp-infrastructure

```bash
cd infra

# 1. set the token (never put it in a file)
export TF_VAR_pve_token='root@pam!terraform=<secret>'      # bash
# $env:TF_VAR_pve_token = "root@pam!terraform=<secret>"    # PowerShell

# 2. run Terraform
terraform init       # download the provider
terraform validate   # check the syntax
terraform plan       # preview, nothing changes
terraform apply      # type "yes" to create the VMs

# 3. get the MAC addresses for the DHCP server
terraform output mac_addresses
```


## 2:Remove everything

```bash
terraform plan -destroy    # preview
terraform destroy          # deletes ALL VMs and their disks created by this config
```
