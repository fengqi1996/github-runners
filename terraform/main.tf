variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

variable "password" {
  type = string
}

variable "project_ID" {
  type = string
}

variable "availability_zone" {
  type = string
  default = "ap-southeast-3"
}

provider "huaweicloud" {
  region     = var.availability_zone
  access_key = var.access_key
  secret_key = var.secret_key
}

resource "huaweicloud_compute_instance" "likecard-ecs" {
  name = "likecard-ecs"
  flavor_id = "s3.xlarge.2"
  admin_pass = var.password
  system_disk_type = "SAS"
  system_disk_size = 40
  network {
    uuid = "55534eaa-533a-419d-9b40-ec427ea7195a"
  }
}

resource "huaweicloud_vpc_eip" "likecard-eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "test"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_compute_eip_associate" "associated" {
  public_ip   = huaweicloud_vpc_eip.likecard-eip.address
  instance_id = huaweicloud_compute_instance.likecard-ecs.id
}