terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "grouplts02" {
    name     = "grouplts02"
    location = "eastus"

    tags     = {
        "Environment" = "aula teste"
    }
}

resource "azurerm_virtual_network" "vnmysqlteste" {
    name                = "vnmysqlteste"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.grouplts02.name
}

resource "azurerm_subnet" "subnetmysqlteste" {
    name                 = "subnetmysqlteste"
    resource_group_name  = azurerm_resource_group.grouplts02.name
    virtual_network_name = azurerm_virtual_network.grouplts02.name
    address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "publicipmysqlteste" {
    name                         = "publicipmysqlteste"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.grouplts02.name
    allocation_method            = "Static"
}

resource "azurerm_network_security_group" "nsgmysqlteste" {
    name                = "nsgmysqlteste"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.grouplts02.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "nicmysqlteste" {
    name                      = "nicmysqlteste"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.grouplts02.name

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.subnetmysqlteste.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.publicipmysqlteste.id
    }
}

resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.nicmysqlteste.id
    network_security_group_id = azurerm_network_security_group.nsgmysqlteste.id
}

resource "azurerm_storage_account" "samsqlteste" {
    name                        = "storageaccountmyvm"
    resource_group_name         = azurerm_resource_group.grouplts02.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_linux_virtual_machine" "vmlts" {
    name                  = "vmlts"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.grouplts02.name
    network_interface_ids = [azurerm_network_interface.nicmysqlteste.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDiskMySQL"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "vmlts"
    admin_username = "azureuser"
    admin_password = "Senha123456@"
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.samsqlteste.primary_blob_endpoint
    }

    depends_on = [azurerm_resource_group.grouplts02]
}

output "public_ip_address_mysql" {
  value = azurerm_public_ip.publicipmysqlteste.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vmlts]
  create_duration = "30s"
}

resource "null_resource" "upload_dbcfgfiles" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = azurerm_linux_virtual_machine.vmlts.admin_username
            password = azurerm_linux_virtual_machine.vmlts.admin_password
            host = data.azurerm_public_ip.ip_aula_data_db.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = azurerm_linux_virtual_machine.vmlts.admin_password
            host = data.azurerm_public_ip.ip_aula_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}