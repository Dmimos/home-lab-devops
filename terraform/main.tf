terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "hyperv" {}

# 1. Create the internal virtual switch
resource "hyperv_network_switch" "lab_switch" {
  name = "lab-switch"
  type = "Internal"
}

# 2. Execute network setup script
resource "null_resource" "network_setup" {
  depends_on = [hyperv_network_switch.lab_switch]

  triggers = {
    script_hash = filemd5("${path.module}/network.ps1")
    host1_ip    = var.host_1_ip
  }

  provisioner "local-exec" {
    command = "powershell -ExecutionPolicy Bypass -File ${path.module}/network.ps1 -Host1IP '${var.host_1_ip}'"
  }
}

# 3. Render user-data.yaml with actual variables
resource "local_file" "user_data_rendered" {
  content = templatefile("${path.module}/cloud-init/user-data.yaml", {
    ssh_public_key = var.ssh_public_key
    vm_ip_address  = var.vm_ip_address
    gateway_ip     = var.gateway_ip
    dns_servers    = var.dns_servers
  })
  filename = "${path.module}/cloud-init/rendered-user-data.yaml"
}

# 4. Build the Cloud-Init ISO via WSL
resource "null_resource" "build_cidata_iso" {
  depends_on = [local_file.user_data_rendered]

  triggers = {
    # Rebuild ISO if the rendered user-data changes
    user_data_hash = local_file.user_data_rendered.content_md5
  }

  provisioner "local-exec" {
    # We pass the output path as an argument to the script
    command = "wsl bash ${path.module}/scripts/build-cidata-iso.sh '${var.cloud_init_iso_path}'"
  }
}

# 5. Create the VM
resource "hyperv_machine_instance" "mgmt" {
  # The VM must wait for the ISO to be ready
  depends_on = [null_resource.build_cidata_iso, null_resource.network_setup]

  name                 = var.vm_name
  generation           = 2
  memory_startup_bytes = var.vm_memory_mb * 1024 * 1024
  processor_count      = var.vm_cpu_count
  
  dynamic_memory {
    enabled = false
  }

  automatic_checkpoints_enabled = false
  
  vm_firmware {
    enable_secure_boot = true
    secure_boot_template = "MicrosoftUEFICertificateAuthority"
  }

  network_adaptors {
    name        = "${var.vm_name}-nic"
    switch_name = hyperv_network_switch.lab_switch.name
  }

  hard_disk_drives {
    path             = var.vm_disk_path
    create_diff_disk = false
  }

  # Ubuntu Installation ISO
  virtual_dvd_drives {
    controller_number = 0
    controller_location = 1
    path = var.ubuntu_iso_path
  }

  # Cloud-Init Seed ISO
  virtual_dvd_drives {
    controller_number = 1
    controller_location = 1
    path = var.cloud_init_iso_path
  }

  vm_processor {
    expose_virtualization_extensions = false
  }
}