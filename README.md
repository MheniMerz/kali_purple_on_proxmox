# Kali Purple on Proxmox

Deploy a two-VM security operations lab on one Proxmox node. Terraform clones and networks the VMs. Ansible configures Elasticsearch, Kibana, and Filebeat. A verification playbook sends two benign client messages and checks that Elastic Security raises exactly one alert.

The two roles come from the Kali Purple SOC-In-A-Box design. This release uses Debian 12 AMD64 cloud guests with the three Elastic packages pinned to 9.5.6. [Upstream Kali Purple wiki](https://gitlab.com/kalilinux/kali-purple/documentation/-/wikis/home), [project architecture](doc/soc-architecture.png), [Elastic support matrix](https://www.elastic.co/support/matrix)

| VM | Components | Network access |
| --- | --- | --- |
| `kali-purple` | Elasticsearch, Kibana, and the lab detection | Management SSH and Kibana. Receives Filebeat events on the lab link. |
| `kali-heliotrope` | Filebeat, shipping journal messages tagged `kali-purple-lab` | Management SSH and package access. Sends events over the lab link. |

## Prerequisites

- A Proxmox node with a trusted API certificate, a VM datastore, and a dedicated lab pool. The default guests need a combined 5 vCPUs, 9 GiB RAM, and 96 GiB of virtual disks. Leave headroom for the host and storage.
- A Debian 12 AMD64 Cloud-Init template on the target node and datastore, with Python 3, an SSH server, and the QEMU guest agent installed. Use SeaBIOS, a `serial0` console, a `scsi0` root disk, and an `ide2` Cloud-Init drive. The template root disk must fit the smaller VM disk size. Verify the base image signature and checksum and record the digest and template name. [Debian cloud images](https://cloud.debian.org/images/cloud/bookworm/latest/), [Proxmox Cloud-Init guide](https://github.com/proxmox/pve-docs/blob/master/qm-cloud-init.adoc)
- A management bridge reachable from the controller and an isolated lab bridge with no physical uplink or gateway. Reserve the VM IDs and static addresses. Both lab addresses belong to the same subnet, separate from management. The guests need management-side DNS and package access to Debian mirrors and `artifacts.elastic.co`.
- Management access from the controller to both guests on TCP 22 and from the workstation to Kibana on the SOC management address at TCP 5601. Allow client access to Elasticsearch on the SOC lab address at TCP 9200. Both VM NICs use Proxmox firewall hooks. Enable and configure the relevant Proxmox rules and keep management services private.
- A controller with Terraform 1.7 or later in the 1.x series, Python 3.12 or later, and an SSH key. Trust the Proxmox host CA on the controller and confirm new SSH host keys through the Proxmox console before connecting.

Create a privilege-separated API token. Scope the underlying Proxmox account and the token to the source template, lab pool, datastore, node, and bridges needed for cloning, VM configuration, and power operations. Check the exact privileges against your Proxmox version. The global provider precheck is disabled so Proxmox enforces the scoped ACLs at each API operation. [Telmate token guidance](https://github.com/Telmate/terraform-provider-proxmox/blob/v3.0.2-rc10/docs/index.md#creating-the-proxmox-user-and-role-for-terraform), [Proxmox permissions](https://pve.proxmox.com/pve-docs/chapter-pveum.html)

## Deploy

Run these commands from the repository root in Bash. Edit the copied variables file for your HTTPS Proxmox API URL, node, pool, template, storage, bridges, VM IDs, addresses, and public key.

```bash
umask 077
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
export PM_API_TOKEN_ID='terraform@pve!kali-purple'
read -r -s -p 'Proxmox API token secret: ' PM_API_TOKEN_SECRET
export PM_API_TOKEN_SECRET
printf '\n'
```

Review the saved plan before applying it. It should create two lab VMs with the expected names, IDs, and networks. Keep the plan and state private.

```bash
terraform -chdir=terraform init -lockfile=readonly
terraform -chdir=terraform plan -out=lab.tfplan
terraform -chdir=terraform apply lab.tfplan
mkdir -p ansible/.local
terraform -chdir=terraform output -json ansible_inventory > ansible/.local/inventory.json
```

Connect to each guest over SSH once. Verify the host key fingerprint against the Proxmox console before accepting it into your controller's `known_hosts`. The Cloud-Init user needs SSH key login and sudo. Use `--private-key` for Ansible if the public key configured in Terraform does not match a key loaded in your SSH agent.

```bash
python3.12 -m venv ansible/.local/venv
source ansible/.local/venv/bin/activate
python -m pip install -r ansible/requirements.txt
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/.local/inventory.json ansible/site.yml
```

Ansible creates a private lab CA and service credentials under `ansible/.local`. Trust `ansible/.local/pki/ca.crt` in your lab browser and open `https://<soc-management-ip>:5601`. For initial administration, sign in as `elastic` with the generated password from `ansible/.local/secrets/elastic`. Filebeat writes with a separate Elasticsearch user scoped to lab events. `lab_log_retention_days` defaults to seven days for raw events. The Elastic Security alert indices follow Elastic's own policies.

## Verify the deployment

The verification playbook writes a control message and a positive message with a unique run ID. It waits for both events to be indexed and confirms that the rule produces one alert for the positive message and zero for the control.

```bash
ansible-playbook -i ansible/.local/inventory.json ansible/verify.yml
```

In Kibana, look for the run ID in **Discover → Kali Purple lab logs** and for the positive alert in **Security → Alerts**. To check repeatability, run `terraform plan` again and rerun `ansible/site.yml`. Expect a no-op plan and no Ansible configuration changes on unchanged guests.

| Symptom | Check |
| --- | --- |
| Clone or readback fails | Check the Proxmox task log, reserved IDs and names, template drive, datastore, and token ACLs. |
| SSH or package installation fails | Check Cloud-Init completion, NIC assignments, management routing and DNS, SSH host key, and package access. |
| Client events are missing | On Heliotrope, check `journalctl -t kali-purple-lab`, `systemctl status filebeat`, and `sudo filebeat test output`. Confirm reachability to the SOC lab address. |
| Events arrive but the alert is missing | Check the `Kali Purple lab fixture` rule and its execution history in Kibana. Confirm both guests have synchronized clocks. |

## Recover or remove the lab

Back up the Terraform state and `ansible/.local` credentials and PKI to protected storage. For an interrupted deployment, run `terraform plan` to reconcile existing resources, export the inventory again, then rerun the Ansible playbook. Use Elasticsearch snapshots if you need to preserve indexed events when replacing the SOC VM. [Elasticsearch snapshot and restore](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore)

To remove the deployed VMs, review a destroy plan. It should list only the VMs managed by this deployment. The pool, bridges, datastore, and template are pre-existing Proxmox resources.

```bash
terraform -chdir=terraform plan -destroy -out=lab-destroy.tfplan
terraform -chdir=terraform apply lab-destroy.tfplan
```

## Remaining milestones

First validate the VM lifecycle and alert flow on the intended Proxmox host. Record the host version, template digest, and measured resource use.

1. Add Byzantium as an OPNsense gateway. Use an isolated HTTP fixture to verify routed firewall events and Suricata alert ingestion.
2. Add Kali Eminence with Malcolm. Validate a benign capture fixture, then prove live traffic delivery from the selected mirror or tap and set a retention policy.
3. Add OpenCTI and Greenbone as independently deployable Kali Violet services with their own capacity and version checks.

