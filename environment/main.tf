variable "access_key" {
  type = string # From Environment Variable
}

variable "secret_key" {
  type = string # From Environment Variable
}

variable "project_ID" {
  type = string
  default = "0"
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "addon_name" {
  type = string
  default = "cie-collector"
}

variable "addon_version" {
  type = string
  default = "3.10.1"
}

variable "enable_nodeAffinity" {
  type = bool
}

variable "shards" {
  type = number
}

variable "retention" {
  type = string
}

variable "high_availability" {
  type = bool
}

variable "storage_class" {
  type = string
}

variable "storage_size" {
  type = string
}

variable "storage_type" {
  type = string
}

variable "supportServerModeSharding" {
  type = bool
}

variable "scrapeInterval" {
  type = string
}

provider "huaweicloud" {
  region     = var.region
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

data "huaweicloud_cce_addon_template" "cie-collector" {
  cluster_id = var.cluster_id
  name       = var.addon_name
  version    = var.addon_version
}

resource "huaweicloud_cce_addon" "cie-collector" {
  cluster_id    = var.cluster_id
  template_name = var.addon_name
  # version       = var.addon_version
  values {
    basic_json  = jsonencode(jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).basic)
    custom_json = jsonencode(merge(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.custom,
      {
        cluster_id = var.cluster_id
        tenant_id  = var.project_ID
        retention  = var.retention
        enable_nodeAffinity=var.enable_nodeAffinity
        shards = var.shards
        storage_class=var.storage_class
        storage_size=var.storage_size
        storage_type=var.storage_type
        supportServerModeSharding=var.supportServerModeSharding
        highAvailability=var.high_availability # Two Replicas data
        scrapeInterval=var.scrapeInterval # 5 seconds interval, 15s, 20s, 25s, 30s...
      }
    ))
    flavor_json = jsonencode(
      jsondecode(data.huaweicloud_cce_addon_template.cie-collector.spec).parameters.flavor5,
    )
  }
}

resource "huaweicloud_cce_addon" "grafana" {
  cluster_id    = var.cluster_id
  template_name = "grafana"
}
