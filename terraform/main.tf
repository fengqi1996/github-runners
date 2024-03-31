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
  image_name = "Huawei Cloud EulerOS 2.0 Standard 64 bit"
  flavor_id = "s3.xlarge.2"
  admin_pass = var.password
  system_disk_type = "SAS"
  system_disk_size = 40
  network {
    uuid = huaweicloud_vpc_subnet.jenkins-subnet.id
  }
}

resource "huaweicloud_vpc" "likecard-vpc" {
  name                  = "likecard-vpc"
  cidr                  = "192.168.0.0/16"
  enterprise_project_id = var.project_ID
}

resource "huaweicloud_vpc_subnet" "jenkins-subnet" {
  name       = "jenkins-subnet"
  cidr       = "192.168.0.0/16"
  gateway_ip = "192.168.0.1"

  primary_dns   = "100.125.1.250"
  secondary_dns = "100.125.21.250"
  vpc_id        = huaweicloud_vpc.likecard-vpc.id
}

resource "huaweicloud_vpc_eip" "likecard-eip" {
  name = "likecard-eip"
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

resource "huaweicloud_compute_eip_associate" "likecard-associated" {
  public_ip   = huaweicloud_vpc_eip.likecard-eip.address
  instance_id = huaweicloud_compute_instance.likecard-ecs.id
}

output "likecard-IP" {
  value = huaweicloud_vpc_eip.likecard-eip.publicip
}