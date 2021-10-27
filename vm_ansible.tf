resource "azurerm_public_ip" "ip-aula-fs-ansible" {
  name                = "ip-aula-fs-ansible"
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  location            = azurerm_resource_group.rg-aula-fs.location
  allocation_method   = "Static"
}

data "azurerm_public_ip" "data-ip-aula-fs-ansible" {
    resource_group_name = azurerm_resource_group.rg-aula-fs.name
    name = azurerm_public_ip.ip-aula-fs-ansible.name
}

resource "azurerm_network_interface" "ni-aula-fs-ansible" {
  name                = "ni-aula-fs-ansible"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-aula-fs.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-aula-fs-ansible.id
  }
}

resource "azurerm_network_interface_security_group_association" "nisga-aula-fs-ansible" {
    network_interface_id      = azurerm_network_interface.ni-aula-fs-ansible.id
    network_security_group_id = azurerm_network_security_group.nsg-aula-fs.id
}

resource "azurerm_virtual_machine" "vm-aula-fs-ansible" {
  name                  = "vm-aula-fs-ansible"
  location              = azurerm_resource_group.rg-aula-fs.location
  resource_group_name   = azurerm_resource_group.rg-aula-fs.name
  network_interface_ids = [azurerm_network_interface.ni-aula-fs-ansible.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "dsk-aula-fs-ansible"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "vm-aula-fs-ansible"
    admin_username = var.user
    admin_password = var.password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}

output "publicip-vm-aula-fs-ansible" {
    value = azurerm_public_ip.ip-aula-fs-ansible.ip_address
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [azurerm_virtual_machine.vm-aula-fs-ansible]
  create_duration = "30s"
}

resource "local_file" "inventario" {
  filename = "./ansible/hosts"
  content = <<EOF

[mysql]
${azurerm_network_interface.ni-aula-fs.private_ip_address}

[mysql:vars]
ansible_user=${var.user}
ansible_ssh_pass=${var.password}
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    depends_on = [ time_sleep.wait_30_seconds ]
}

resource "null_resource" "upload" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.data-ip-aula-fs-ansible.ip_address
        }
        source = "ansible"
        destination = "/home/${var.user}"
    }

    depends_on = [ local_file.inventario ]
}

resource "null_resource" "deploy" {
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.data-ip-aula-fs-ansible.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y software-properties-common",
            "sudo apt-add-repository --yes --update ppa:ansible/ansible",
            "sudo apt-get -y install python3 ansible",
            "ansible-playbook -i /home/${var.user}/ansible/hosts /home/${var.user}/ansible/main.yml"
        ]
    }
    
    depends_on = [ null_resource.upload ]
}