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
  default = "ap-southeast-2"
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
    bucket   = "ais-test-terraform"
    key      = "terraform.tfstate"
    region   = "ap-southeast-2"
    endpoint = "https://obs.ap-southeast-2.myhuaweicloud.com"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

resource "huaweicloud_vpc" "cce-vpc" {
  name                  = "cce-vpc-${var.environment}-${random_string.random_suffix.result}"
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
    name        = "cce-control-plane-eip-${var.environment}-${random_string.random_suffix.result}"
    size        = 10
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "random_string" "random_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "huaweicloud_cce_cluster" "huawei-cce" {
  name                   = "huawei-ais-${var.environment}-${random_string.random_suffix.result}"
  flavor_id              = "cce.s2.small" # HA, 50 Nodes -- cce.s2.xlarge, HA, 2000 Nodes
  vpc_id                 = huaweicloud_vpc.cce-vpc.id
  subnet_id              = huaweicloud_vpc_subnet.cce-subnet.id
  container_network_type = "overlay_l2"
  eip                    = huaweicloud_vpc_eip.cce-control-plane-eip.address
  cluster_version        = "v1.29"
  enterprise_project_id  = var.project_ID
  masters {
    availability_zone = "ap-southeast-2a"
  }
  masters {
    availability_zone = "ap-southeast-2b"
  }
  masters {
    availability_zone = "ap-southeast-2c"
  }
}


data "huaweicloud_availability_zones" "cce-az" {
  region = "ap-southeast-2"
}

resource "huaweicloud_cce_node" "cce-node" {
  cluster_id        = huaweicloud_cce_cluster.huawei-cce.id
  name              = "cce-node-${var.environment}-${random_string.random_suffix.result}"
  flavor_id         = "c7n.xlarge.2"
  availability_zone = data.huaweicloud_availability_zones.cce-az.names[0]
  password          = var.password
  runtime           = "docker"
  os                = "EulerOS 2.9"
  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
}

resource "huaweicloud_cce_node_pool" "node_pool" {
  cluster_id               = huaweicloud_cce_cluster.huawei-cce.id
  name                     = "cce-node-pool-${var.environment}-${random_string.random_suffix.result}"
  os                       = "EulerOS 2.9"
  initial_node_count       = 2
  flavor_id                = "c7n.xlarge.2"
  password                 = var.password
  scall_enable             = true
  min_node_count           = 3
  max_node_count           = 10
  scale_down_cooldown_time = 100
  priority                 = 1
  type                     = "vm"
  # runtime                  = "containerd"

  labels = {
    "cce-node-pool" = "cce-node-pool-${var.environment}-${random_string.random_suffix.result}"
  }
  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
}

variable "cluster_id" {
  type = string
  default = "33e24729-1dc9-11ef-abd5-0255ac100039"
}

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
        retention  = "1d"
        enable_nodeAffinity=false
        shards = 2
        storage_class="csi-disk-topology"
        storage_size="15Gi"
        storage_type="SAS"
        supportServerModeSharding=true
        highAvailability=true
        scrapeInterval="20s" # 5 seconds interval
        enable_grafana=false
        
      }
    ))
    flavor_json = jsonencode(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.flavor7,
    )
  }
}

resource "huaweicloud_vpc_eip" "cce-nat-eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "cce-nat-eip-${var.environment}-${random_string.random_suffix.result}"
    size        = 10
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_nat_gateway" "cce-nat" {
  name        = "cce-nat-${var.environment}-${random_string.random_suffix.result}"
  description = "test for terraform"
  spec        = "2"
  vpc_id      = huaweicloud_vpc.cce-vpc.id
  subnet_id   = huaweicloud_vpc_subnet.cce-subnet.id
}

resource "huaweicloud_nat_snat_rule" "cce-snat-rule" {
  nat_gateway_id = huaweicloud_nat_gateway.cce-nat.id
  floating_ip_id = huaweicloud_vpc_eip.cce-nat-eip.id
  subnet_id      = huaweicloud_vpc_subnet.cce-subnet.id
}
