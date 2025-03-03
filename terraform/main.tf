variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

variable "password" {
  type = string
}

variable "availability_zone" {
  type = string
  default = "ap-southeast-3"
}

variable "environment" {
  type = string
  default = "test"
}

variable "obs-bucket" {
  type = string
  default = "lts-ais-test"
}

variable "lts-group" {
  type = string
  default = "lts-group-ais"
}

variable "vpc-cidr" {
  type = string
  default = "10.144.134.0/24"
}

variable "vpc-subnet-cidr" {
  type = string
  default = "10.144.134.0/24"
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

# resource "huaweicloud_enterprise_project" "itcp-microservice-staging" {
#   name        = "itcp-microservice-staging"
#   description = "Terraform ITCP Microservice Staging "
#   type        = "poc"
# }

resource "huaweicloud_vpc" "cce-vpc" {
  name                  = "cce-vpc-${var.environment}-${random_string.random_suffix.result}"
  cidr                  = var.vpc-cidr
  enterprise_project_id = "861dea44-2f5c-4b2a-82da-9fcd1919afbf"
}

resource "huaweicloud_vpc_subnet" "cce-subnet" {
  name       = "cce-subnet"
  cidr       = var.vpc-subnet-cidr
  gateway_ip = "10.144.134.1"
  vpc_id        = huaweicloud_vpc.cce-vpc.id
}

# resource "huaweicloud_vpc_eip" "cce-control-plane-eip" {
#   publicip {
#     type = "5_bgp"
#   }
#   bandwidth {
#     name        = "cce-control-plane-eip-${var.environment}-${random_string.random_suffix.result}"
#     size        = 10
#     share_type  = "PER"
#     charge_mode = "traffic"
#   }
# }

resource "random_string" "random_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "huaweicloud_cce_cluster" "huawei-cce" {
  name                   = "huawei-ais-${var.environment}"
  flavor_id              = "cce.s2.small" # HA, 50 Nodes -- cce.s2.xlarge, HA, 2000 Nodes
  vpc_id                 = huaweicloud_vpc.cce-vpc.id
  subnet_id              = huaweicloud_vpc_subnet.cce-subnet.id
  container_network_type = "overlay_l2"
  tags  = {
    project = "cce-poccce-hwc-bkk-dev-003"
  }
  # eip                    = huaweicloud_vpc_eip.cce-control-plane-eip.address
  cluster_version        = "v1.28"
  enterprise_project_id  = "861dea44-2f5c-4b2a-82da-9fcd1919afbf"
  masters {
    availability_zone = "ap-southeast-3a"
  }
  masters {
    availability_zone = "ap-southeast-3b"
  }
  masters {
    availability_zone = "ap-southeast-3c"
  }
}


data "huaweicloud_availability_zones" "cce-az" {
  region = "ap-southeast-3"
}

resource "huaweicloud_cce_node" "cce-node" {
  cluster_id        = huaweicloud_cce_cluster.huawei-cce.id
  name              = "cce-node-${var.environment}"
  flavor_id         = "c7n.xlarge.2"
  availability_zone = data.huaweicloud_availability_zones.cce-az.names[0]
  password          = var.password
  runtime           = "containerd"
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
  name                     = "cce-node-pool-${var.environment}"
  os                       = "EulerOS 2.9"
  initial_node_count       = 4
  flavor_id                = "c7n.xlarge.2"
  password                 = var.password
  scall_enable             = true
  min_node_count           = 4
  max_node_count           = 10
  scale_down_cooldown_time = 100
  priority                 = 1
  type                     = "vm"
  # runtime                  = "containerd"

  labels = {
    "cce-node-pool" = "cce-node-pool-${var.environment}"
  }
  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
  # depends_on = [ huaweicloud_vpc_route_table.route_table_er ]
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
        tenant_id  = "861dea44-2f5c-4b2a-82da-9fcd1919afbf"
        retention  = "1d"
        enable_nodeAffinity=true
        shards = 2
        storage_class="csi-disk-topology"
        storage_size="20Gi"
        storage_type="SAS"
        supportServerModeSharding=true
        highAvailability=true # Two Replicas data
        scrapeInterval="20s" # 5 seconds interval, 15s, 20s, 25s, 30s...
        enable_grafana=true 
      }
    ))
    flavor_json = jsonencode(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.flavor7,
    )
  }
  depends_on = [ huaweicloud_cce_node_pool.node_pool, huaweicloud_cce_node.cce-node ]
}

resource "huaweicloud_vpc_eip" "dedicated" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    share_type  = "PER"
    name        = "cce-elb-ingress-${var.environment}-bandwidth"
    size        = 5
    charge_mode = "traffic"
  }
}

resource "huaweicloud_elb_loadbalancer" "cce-elb-ingress" {
  name              = "cce-elb-ingress" 
  description       = "Nginx Ingress Controller"
  cross_vpc_backend = true

  vpc_id         = huaweicloud_vpc.cce-vpc.id
  ipv4_eip_id    = huaweicloud_vpc_eip.dedicated.id

  availability_zone = [
    "ap-southeast-3a",
    "ap-southeast-3b",
  ]

  enterprise_project_id = "861dea44-2f5c-4b2a-82da-9fcd1919afbf"
}
data "huaweicloud_cce_addon_template" "nginx-ingress" {
  cluster_id = huaweicloud_cce_cluster.huawei-cce.id
  name       = "nginx-ingress"
  version    = "2.6.5"
}

resource "huaweicloud_cce_addon" "nginx-ingress" {
  cluster_id    = huaweicloud_cce_cluster.huawei-cce.id
  template_name = "nginx-ingress"
  # version       = var.addon_version
  values {
    basic_json  = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.nginx-ingress.spec).basic)
    custom_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.nginx-ingress.spec).parameters.custom,
      {
        "service": {
          "annotations": {
            "kubernetes.io/elb.class": "performance",
            "kubernetes.io/elb.pass-through": "true"
            "kubernetes.io/elb.id": huaweicloud_elb_loadbalancer.cce-elb-ingress.id
            
          }
        }
      }
    ))
    flavor_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.nginx-ingress.spec).parameters.flavor1,
      {
        "resources": [
          {
            "limitsCpu": "8000m",
            "limitsMem": "4000Mi",
            "name": "nginx-ingress",
            "requestsCpu": "100m",
            "requestsMem": "100Mi"
          }
        ]
      })
    )
  }
  depends_on = [ huaweicloud_cce_node_pool.node_pool, huaweicloud_cce_node.cce-node ]
}

resource "huaweicloud_cce_addon" "grafana" {
  cluster_id    = huaweicloud_cce_cluster.huawei-cce.id
  template_name = "grafana"
  depends_on = [ huaweicloud_cce_node_pool.node_pool, huaweicloud_cce_node.cce-node ]
}

resource "huaweicloud_lts_group" "lts-logs-group" {
  group_name  = var.lts-group
  ttl_in_days = 20
  region      = var.availability_zone
}

resource "huaweicloud_lts_stream" "lts-event-stream" {
  group_id    = huaweicloud_lts_group.lts-logs-group.id
  stream_name = "lts-logs-group_stream"
}

resource "huaweicloud_lts_stream" "lts-stdout-stream" {
  group_id    = huaweicloud_lts_group.lts-logs-group.id
  stream_name = "lts-stdout-group_stream"
}

data "huaweicloud_cce_addon_template" "log-agent" {
  cluster_id = huaweicloud_cce_cluster.huawei-cce.id
  name       = "log-agent"
  version    = "1.3.2"
}

resource "huaweicloud_cce_addon" "log-agent" {
  cluster_id    = huaweicloud_cce_cluster.huawei-cce.id
  template_name = "log-agent"
  values {
    basic_json  = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.log-agent.spec).basic)
    custom_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.log-agent.spec).parameters.custom,
      {
        "ltsEventStreamID": huaweicloud_lts_stream.lts-event-stream.id,
        "ltsStdoutStreamID": huaweicloud_lts_stream.lts-stdout-stream.id,
        "ltsGroupID": huaweicloud_lts_group.lts-logs-group.id,
        "multiAZEnabled": true,
      },
    ))
    flavor_json = jsonencode(
      jsondecode(data.huaweicloud_cce_addon_template.log-agent.spec).parameters.flavor2,
    )
  }
  depends_on = [ huaweicloud_cce_node_pool.node_pool, huaweicloud_cce_node.cce-node ]
}

resource "huaweicloud_obs_bucket" "bucket" {
  bucket     = var.obs-bucket
  acl        = "private"

  lifecycle_rule {
    name    = "log_lifecycle"
    enabled = true

    transition {
      days          = 1
      storage_class = "COLD"
    }
  }
}

resource "huaweicloud_lts_transfer" "lts-obs-transfer" {
  region = var.availability_zone
  log_group_id = huaweicloud_lts_group.lts-logs-group.id

  log_streams {
    log_stream_id  = huaweicloud_lts_stream.lts-event-stream.id
    log_stream_name = "lts-logs-group_stream"
  }

  log_streams {
    log_stream_id  = huaweicloud_lts_stream.lts-stdout-stream.id
    log_stream_name = "lts-stdout-group_stream"
  }

  log_transfer_info {
    log_transfer_type   = "OBS"
    log_transfer_mode   = "cycle"
    log_storage_format  = "RAW"
    log_transfer_status = "ENABLE"

    log_transfer_detail {
      obs_period          = 3
      obs_period_unit     = "hour"
      obs_bucket_name     = var.obs-bucket
      obs_dir_prefix_name = "cce-hw-poc_"
      obs_prefix_name     = "hw_"
      obs_time_zone       = "UTC"
      obs_time_zone_id    = "Etc/GMT"
    }
  }
  depends_on = [ huaweicloud_obs_bucket.bucket ]
}

# resource "huaweicloud_vpc_route_table" "route_table_er" {
#   name    = "route_table_er"
#   vpc_id  = huaweicloud_vpc.cce-vpc.id
#   subnets = [huaweicloud_vpc_subnet.cce-subnet.id]

#   route {
#     destination = "172.16.0.0/12"
#     type        = "er"
#     nexthop     = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
#   }
#   route {
#     destination = "10.0.0.0/8"
#     type        = "er"
#     nexthop     = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
#   }
#   route {
#     destination = "192.168.0.0/16"
#     type        = "er"
#     nexthop     = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
#   }
#   route {
#     destination = "0.0.0.0/0"
#     type        = "er"
#     nexthop     = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
#   }
# }

resource "huaweicloud_vpc_route" "vpc_route_er_1" {
  vpc_id         = huaweicloud_vpc.cce-vpc.id
  # route_table_id = huaweicloud_vpc_route_table.route_table_er.id
  destination    = "172.16.0.0/12"
  type           = "er"
  nexthop        = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
  depends_on     = [ huaweicloud_vpc.cce-vpc, huaweicloud_vpc_subnet.cce-subnet, huaweicloud_vpc_route.vpc_route_er_2,  huaweicloud_er_vpc_attachment.test  ]
}
resource "huaweicloud_vpc_route" "vpc_route_er_2" {
  vpc_id         = huaweicloud_vpc.cce-vpc.id
  # route_table_id = huaweicloud_vpc_route_table.route_table_er.id
  destination    = "10.0.0.0/8"
  type           = "er"
  nexthop        = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
  depends_on     = [ huaweicloud_vpc.cce-vpc, huaweicloud_vpc_subnet.cce-subnet, huaweicloud_vpc_route.vpc_route_er_3, huaweicloud_er_vpc_attachment.test  ]
}
resource "huaweicloud_vpc_route" "vpc_route_er_3" {
  vpc_id         = huaweicloud_vpc.cce-vpc.id
  # route_table_id = huaweicloud_vpc_route_table.route_table_er.id
  destination    = "192.168.0.0/16"
  type           = "er"
  nexthop        = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
  depends_on     = [ huaweicloud_vpc.cce-vpc, huaweicloud_vpc_subnet.cce-subnet, huaweicloud_vpc_route.vpc_route_er_4, huaweicloud_er_vpc_attachment.test  ]
}
resource "huaweicloud_vpc_route" "vpc_route_er_4" {
  vpc_id         = huaweicloud_vpc.cce-vpc.id
  # route_table_id = huaweicloud_vpc_route_table.route_table_er.id
  destination    = "0.0.0.0/0"
  type           = "er"
  nexthop        = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
  depends_on     = [ huaweicloud_vpc.cce-vpc, huaweicloud_vpc_subnet.cce-subnet, huaweicloud_er_vpc_attachment.test  ]
}

# resource "huaweicloud_vpc_eip" "cce-nat-eip" {
#   publicip {
#     type = "5_bgp"
#   }
#   bandwidth {
#     name        = "cce-nat-eip-${var.environment}"
#     size        = 10
#     share_type  = "PER"
#     charge_mode = "traffic"
#   }
# }

# resource "huaweicloud_nat_gateway" "cce-nat" {
#   name        = "cce-nat-${var.environment}"
#   description = "test for terraform"
#   spec        = "1"
#   # Reference Spec: https://registry.terraform.io/providers/huaweicloud/huaweicloud/latest/docs/resources/nat_gateway
#   # spec - (Required, String) Specifies the specification of the NAT gateway. The valid values are as follows:

#   # 1: Small type, which supports up to 10,000 SNAT connections.
#   # 2: Medium type, which supports up to 50,000 SNAT connections.
#   # 3: Large type, which supports up to 200,000 SNAT connections.
#   # 4: Extra-large type, which supports up to 1,000,000 SNAT connections.
#   vpc_id      = huaweicloud_vpc.cce-vpc.id
#   subnet_id   = huaweicloud_vpc_subnet.cce-subnet.id
# }

# resource "huaweicloud_nat_snat_rule" "cce-snat-rule" {
#   nat_gateway_id = huaweicloud_nat_gateway.cce-nat.id
#   floating_ip_id = huaweicloud_vpc_eip.cce-nat-eip.id
#   subnet_id      = huaweicloud_vpc_subnet.cce-subnet.id
# }


resource "huaweicloud_er_vpc_attachment" "test" {
  instance_id = "fb79b1e5-937e-45c0-a548-cd48ee1c6f23"
  vpc_id      = huaweicloud_vpc.cce-vpc.id
  subnet_id   = huaweicloud_vpc_subnet.cce-subnet.id
  name        = "hw-cce-bbk-attachment"
}

output "kube-config" {
  value = huaweicloud_cce_cluster.huawei-cce.kube_config_raw
}

output "lts-logs-group" {
  value = huaweicloud_lts_group.lts-logs-group.id
}

output "obs-bucket" {
  value = var.obs-bucket
}
