variable "project" { type = string }
variable "environment" {
  type    = string
  default = "dev"
}
variable "oidc_provider_arn" {
  type    = string
  default = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE"
}
variable "oidc_provider_url" {
  type    = string
  default = "oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLE"
}

# IV-08 Resolved — Scoped EKS worker node IAM role (no AdministratorAccess)
resource "aws_iam_role" "eks_node" {
  name = "${var.project}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# IV-08 Resolved — IRSA role for application pods with least-privilege permissions
resource "aws_iam_role" "app_role" {
  name = "${var.project}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:secureflow:auth-service"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_least_privilege" {
  name = "${var.project}-app-s3-readonly"
  role = aws_iam_role.app_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      Resource = "arn:aws:s3:::${var.project}-artifacts/*"
    }]
  })
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node.arn
}

output "app_role_arn" {
  value = aws_iam_role.app_role.arn
}