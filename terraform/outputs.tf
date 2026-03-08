output "cluster_name" {
  description = "EKS Cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS Cluster endpoint URL"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_data" {
  description = "EKS Cluster certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend image"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_url" {
  description = "ECR repository URL for backend image"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_pull_role_arn_frontend" {
  description = "IAM Role ARN for frontend IRSA ECR pull"
  value       = aws_iam_role.frontend_ecr_pull.arn
}

output "ecr_pull_role_arn_backend" {
  description = "IAM Role ARN for backend IRSA ECR pull"
  value       = aws_iam_role.backend_ecr_pull.arn
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller IRSA"
  value       = aws_iam_role.alb_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM Role ARN for Cluster Autoscaler IRSA"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "jenkins_public_ip" {
  description = "Jenkins EC2 public IP"
  value       = aws_instance.jenkins.public_ip
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}
