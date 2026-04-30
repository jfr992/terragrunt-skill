locals {
  # Account configuration
  aws_account_id = "987654321098"
  account_name   = "myproject-prod"
  role_arn       = "arn:aws:iam::987654321098:role/TerraformCrossAccount"

  # Environment
  environment = "production"
  env_alias   = "prod"

  # Network configuration (existing VPC)
  vpc_id             = "vpc-yyyyyyyyy"
  private_subnet_ids = ["subnet-priv1", "subnet-priv2", "subnet-priv3"]
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]

  # Shared infrastructure references
  shared_eks_cluster_name = "prod-eks"
  shared_msk_cluster_name = "prod-msk"

  # Tags for resources in this account
  tags = {
    Project     = "MyProject"
    Environment = "production"
  }
}
