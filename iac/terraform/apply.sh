#!/bin/bash
ls -la
echo "************* execute terraform apply"
## execute terrafotm build and sendout to packer-build-output
export ARM_CLIENT_ID=$1
export ARM_CLIENT_SECRET=$2
export ARM_SUBSCRIPTION_ID=$3
export ARM_TENANT_ID=$4
export ARM_ACCESS_KEY=$5

terraform apply -auto-approve 

export vmss_ip=$(terraform output vm_ip)
echo "host1 ansible_ssh_port=50000 ansible_ssh_host=$vmss_ip" > inventory
echo "host2 ansible_port=50001 ansible_ssh_host=$vmss_ip" >> inventory

cat inventory
