locals {
  # Account configuration
  aws_account_id = "123456789012"
  account_name   = "myproject-nonprod"
  role_arn       = "arn:aws:iam::123456789012:role/TerraformCrossAccount"

  # Environment
  environment = "non-production"
  env_alias   = "nonprod"

  # Network configuration (existing VPC)
  vpc_id             = "vpc-xxxxxxxxx"
  private_subnet_ids = ["subnet-priv1", "subnet-priv2", "subnet-priv3"]
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  # Shared infrastructure references
  shared_eks_cluster_name = "nonprod-eks"
  shared_msk_cluster_name = "nonprod-msk"

  # Tags for resources in this account
  tags = {
    Project     = "MyProject"
    Environment = "non-production"
  }
}
