terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.46.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg-aula-fs" {
  name     = "rg-aula-fs"
  location = "East US"
}

resource "azurerm_virtual_network" "vn-aula-fs" {
  name                = "vn-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sub-aula-fs" {
  name                 = "sub-aula-fs"
  resource_group_name  = azurerm_resource_group.rg-aula-fs.name
  virtual_network_name = azurerm_virtual_network.vn-aula-fs.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-aula-fs" {
  name                = "ip-aula-fs"
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  location            = azurerm_resource_group.rg-aula-fs.location
  allocation_method   = "Static"
}

data "azurerm_public_ip" "data-ip-aula-fs" {
    resource_group_name = azurerm_resource_group.rg-aula-fs.name
    name = azurerm_public_ip.ip-aula-fs.name
}

resource "azurerm_network_security_group" "nsg-aula-fs" {
  name                = "nsg-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

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
    name                       = "mysql"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "ni-aula-fs" {
  name                = "ni-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-aula-fs.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-aula-fs.id
    private_ip_address            = "10.0.1.4"
  }
}

resource "azurerm_network_interface_security_group_association" "nisga-aula-fs" {
    network_interface_id      = azurerm_network_interface.ni-aula-fs.id
    network_security_group_id = azurerm_network_security_group.nsg-aula-fs.id
}

resource "azurerm_virtual_machine" "vm-aula-fs" {
  name                  = "vm-aula-fs"
  location              = azurerm_resource_group.rg-aula-fs.location
  resource_group_name   = azurerm_resource_group.rg-aula-fs.name
  network_interface_ids = [azurerm_network_interface.ni-aula-fs.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "dsk-aula-fs"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "vm-aula-fs"
    admin_username = var.user
    admin_password = var.password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}

output "publicip-vm-aula-fs" {
    value = azurerm_public_ip.ip-aula-fs.ip_address
}

resource "null_resource" "upload-db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.data-ip-aula-fs.ip_address
        }
        source = "files"
        destination = "/home/${var.user}"
    }

    depends_on = [ null_resource.deploy ]
}

resource "null_resource" "deploy-db" {
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.data-ip-aula-fs.ip_address
        }
        inline = [
            "sudo cp -f /home/${var.user}/files/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo mysql < /home/${var.user}/files/root.sql",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
    
    depends_on = [ null_resource.upload-db ]
}