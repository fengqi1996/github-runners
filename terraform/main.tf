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
  default = "0"
}

variable "availability_zone" {
  type = string
  default = "ap-southeast-3"
}

variable "environment" {
  type = string
  default = "test"
}

provider "huaweicloud" {
  region     = var.availability_zone
  access_key = var.access_key
  secret_key = var.secret_key
}

terraform {
  backend "s3" {
    # Reference: https://registry.terraform.io/providers/huaweicloud/hcso/latest/docs/guides/remote-state-backend
    bucket   = "ais-test-jy"
    key      = "terraform.tfstate"
    region   = "ap-southeast-3"
    endpoint = "https://obs.ap-southeast-3.myhuaweicloud.com"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

resource "huaweicloud_vpc" "cce-vpc" {
  name                  = "cce-vpc"
  cidr                  = "192.168.0.0/16"
  enterprise_project_id = var.project_ID
}

resource "huaweicloud_vpc_subnet" "cce-subnet" {
  name       = "cce-subnet"
  cidr       = "192.168.0.0/16"
  gateway_ip = "192.168.0.1"
  vpc_id        = huaweicloud_vpc.cce-vpc.id
}

resource "huaweicloud_vpc_eip" "cce-control-plane-eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "mybandwidth"
    size        = 10
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "random_string" "random_suffix" {
  length  = 8
  special = false
}

resource "huaweicloud_cce_cluster" "huawei-cce" {
  name                   = "huawei-cce-${var.environment}-${random_string.random_suffix.result}"
  flavor_id              = "cce.s1.small" # 50 Nodes
  vpc_id                 = huaweicloud_vpc.cce-vpc.id
  subnet_id              = huaweicloud_vpc_subnet.cce-subnet.id
  container_network_type = "overlay_l2"
  eip                    = huaweicloud_vpc_eip.cce-control-plane-eip.address
  cluster_version        = "v1.29"
  enterprise_project_id  = var.project_ID
}


data "huaweicloud_availability_zones" "cce-az" {
  region = "ap-southeast-3"
}

resource "huaweicloud_cce_node" "cce-node" {
  cluster_id        = huaweicloud_cce_cluster.huawei-cce.id
  name              = "cce-node--${var.environment}-${random_string.random_suffix.result}"
  flavor_id         = "c7n.xlarge.2"
  availability_zone = data.huaweicloud_availability_zones.cce-az.names[0]
  password          = var.password
  runtime           = "docker"
  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
}

# variable "cluster_id" {
#   type = string
#   default = "33e24729-1dc9-11ef-abd5-0255ac100039"
# }

variable "addon_name" {
  type = string
  default = "cie-collector"
}

variable "addon_version" {
  type = string
  default = "3.10.1"
}

data "huaweicloud_cce_addon_template" "cie-collector" {
  cluster_id = huaweicloud_cce_cluster.huawei-cce.id
  name       = var.addon_name
  version    = var.addon_version
}

resource "huaweicloud_cce_addon" "cie-collector" {
  cluster_id    = huaweicloud_cce_cluster.huawei-cce.id
  template_name = var.addon_name
  # version       = var.addon_version
  values {
    basic_json  = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).basic)
    custom_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.custom,
      {
        cluster_id = huaweicloud_cce_cluster.huawei-cce.id
        tenant_id  = var.project_ID
        retention  = "7d"
        enable_nodeAffinity=false
        shards = 2
        # storage_class="csi-obs"
        # storage_size="15Gi"
        # storage_type="STANDARD"
        supportServerModeSharding=true
        highAvailability=true
        scrapeInterval="16s"
        enable_grafana=false
        
      }
    ))
    flavor_json = jsonencode(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.flavor7,
    )
  }
}