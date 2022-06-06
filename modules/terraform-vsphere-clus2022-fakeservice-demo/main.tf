# data block to fetch the datacenter id
data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

# data block to fetch target datastore id
data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

# data block to fetch target compute cluster root resource pool id
data "vsphere_resource_pool" "compute_cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

# data block to fetch target deployment network details
data "vsphere_network" "deployment_network" {
  name          = var.template_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# data block to fetch the deployment vm template
data "vsphere_virtual_machine" "deployment_template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "cloudinit_config" "config" {
  count         = var.demo_vms.quantity
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/cloud-init-templates/consul-agent.sh.tpl", {
      "name"             = "${var.demo_vms.name}0${count.index + 1}"
      "service_name"     = var.demo_vms.name
      "service_tag"      = var.demo_vms.service_tag
      "service_port"     = var.demo_vms.service_port
      "service_message"  = var.demo_vms.service_message
      "upstream_service" = var.demo_vms.upstream_service
    })
  }
}


resource "vsphere_virtual_machine" "demo-vms" {
  count            = var.demo_vms.quantity
  name             = "${var.demo_vms.name}0${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.compute_cluster.id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.folder_path
  firmware         = data.vsphere_virtual_machine.deployment_template.firmware
  num_cpus         = 2    # Hardcoding for Demo
  memory           = 4096 # Hardcoding for Demo
  guest_id         = data.vsphere_virtual_machine.deployment_template.guest_id
  scsi_type        = data.vsphere_virtual_machine.deployment_template.scsi_type

  network_interface {
    network_id   = data.vsphere_network.deployment_network.id
    adapter_type = data.vsphere_virtual_machine.deployment_template.network_interface_types[0]
  }

  disk {
    label            = "os"
    size             = 50
    eagerly_scrub    = false
    thin_provisioned = true # Hardcoding for demo
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.deployment_template.id
  }

  extra_config = {
    "guestinfo.metadata" = base64encode(templatefile("${path.module}/cloud-init-templates/metadata.yaml.tpl", {
      name = "${var.demo_vms.name}0${count.index + 1}"
      dhcp = true
    }))
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.config[count.index].rendered
    "guestinfo.userdata.encoding" = "gzip+base64"
  }
  lifecycle {
    ignore_changes = [
      annotation,
      clone[0].template_uuid,
      extra_config,
    ]
  }
}
