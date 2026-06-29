# ============================================
# main.tf - Root Module
# ============================================

module "network" {
  source = "./modules/network"

  project_name = var.project_name
  aws_region   = var.aws_region
}

module "security" {
  source = "./modules/security"

  project_name   = var.project_name
  vpc_id         = module.network.vpc_id
  ssh_allowed_ip = var.ssh_allowed_ip
}

module "compute" {
  source = "./modules/compute"

  project_name      = var.project_name
  instance_type     = var.instance_type
  key_name          = var.key_name
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.security.security_group_id
  # Note: vpc_id is NOT needed in compute module if you're using subnet_ids
}