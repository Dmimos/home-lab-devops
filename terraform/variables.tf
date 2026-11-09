variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "mgmt"
}

variable "vm_memory_mb" {
  description = "Startup memory in MB"
  type        = number
  default     = 2048
}

variable "vm_cpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 2
}

variable "vm_disk_path" {
  description = "Path to the VHDX file on Host 2"
  type        = string
  default     = "C:\\HyperV\\Disks\\mgmt.vhdx"
}

variable "ubuntu_iso_path" {
  description = "Path to the Ubuntu Server installation ISO"
  type        = string
  default     = "C:\\HyperV\\ISO\\ubuntu-24.04-live-server-amd64.iso"
}

variable "cloud_init_iso_path" {
  description = "Path to the generated Cloud-Init (cidata) ISO"
  type        = string
  default     = "C:\\HyperV\\ISO\\cidata-mgmt.iso"
}

variable "vm_ip_address" {
  description = "Static IP address for the VM"
  type        = string
  default     = "192.168.50.20"
}

variable "gateway_ip" {
  description = "Gateway IP address (Host 2)"
  type        = string
  default     = "192.168.50.1"
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "SSH public key for the default user"
  type        = string
  # Provide via terraform.tfvars or environment variables
}

variable "host_1_ip" {
  description = "IP address of Host 1 to restrict SSH access"
  type        = string
  # Example: "192.168.1.100"
}