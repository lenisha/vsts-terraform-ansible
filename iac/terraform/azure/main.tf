terraform {
  required_version = ">= 0.11"

  backend "azurerm" {
    storage_account_name = "storeinfraq5nlivodfwwqmm"
    container_name       = "terraform-state"
    key                  = "demo-consul.terraform.tfstate"
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "demo_resource_group" {
  name     = "fpdemo"
  location = "eastus"

  tags {
    environment = "Terraform Demo"
  }
}

# Create virtual network
resource "azurerm_virtual_network" "demo_virtual_network" {
  name                = "fpdemo"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  tags {
    environment = "Terraform Demo"
  }
}

# Create subnet
resource "azurerm_subnet" "demo_subnet" {
  name                 = "fpdemo"
  resource_group_name  = "${azurerm_resource_group.demo_resource_group.name}"
  virtual_network_name = "${azurerm_virtual_network.demo_virtual_network.name}"
  address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "demo_public_ip" {
  name                         = "fppublicip"
  location                     = "eastus"
  resource_group_name          = "${azurerm_resource_group.demo_resource_group.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "demoiac"

  tags {
    environment = "Terraform Demo"
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "demo_security_group" {
  name                = "fpsecuritygroups"
  location            = "eastus"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags {
    environment = "Terraform Demo"
  }
}

resource "azurerm_lb" "vmss_lb" {
  name                = "vmss-lb"
  location            = "${azurerm_resource_group.demo_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.demo_public_ip.id}"
  }

  tags {
    environment = "Terraform Demo"
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.vmss_lb.id}"
  name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss_probe" {
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id     = "${azurerm_lb.vmss_lb.id}"
  name                = "ssh-running-probe"
  port                = "80"
}

resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = "${azurerm_resource_group.demo_resource_group.name}"
  loadbalancer_id                = "${azurerm_lb.vmss_lb.id}"
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = "80"
  backend_port                   = "80"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.bpepool.id}"
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = "${azurerm_lb_probe.vmss_probe.id}"
}

resource "azurerm_lb_nat_pool" "lbnatpool" {
  count                          = 3
  resource_group_name            = "${azurerm_resource_group.demo_resource_group.name}"
  name                           = "ssh"
  loadbalancer_id                = "${azurerm_lb.vmss_lb.id}"
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = "${azurerm_resource_group.demo_resource_group.name}"
  }

  byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "demo_storage_account" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = "${azurerm_resource_group.demo_resource_group.name}"
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags {
    environment = "Terraform Demo"
  }
}

# Create virtual machine sclae set
resource "azurerm_virtual_machine_scale_set" "vmss" {
  name                = "vmscaleset"
  location            = "eastus"
  resource_group_name = "${azurerm_resource_group.demo_resource_group.name}"
  upgrade_policy_mode = "Manual"

  sku {
    name     = "Standard_DS1_v2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "RHEL"
    sku       = "7.3"
    version   = "latest"
  }

  os_profile {
    computer_name_prefix = "myvm"
    admin_username       = "azureuser"
    admin_password       = "Passwword1234"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/id_rsa.pub")}"
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "IPConfiguration"
      subnet_id                              = "${azurerm_subnet.demo_subnet.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.bpepool.id}"]
      load_balancer_inbound_nat_rules_ids    = ["${element(azurerm_lb_nat_pool.lbnatpool.*.id, count.index)}"]
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.demo_storage_account.primary_blob_endpoint}"
  }

  tags {
    environment = "Terraform Demo"
  }

  #   provisioner "local-exec" {
  #     command = "sleep 90; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u azureuser --private-key id_rsa -i '${azurerm_public_ip.demo_public_ip.ip_address}', master.yml"
  #    }
}

output "vm_ip" {
  value = "${azurerm_public_ip.demo_public_ip.ip_address}"
}

output "vm_dns" {
  value = "http://${azurerm_public_ip.demo_public_ip.domain_name_label}.eastus.cloudapp.azure.com"
}
