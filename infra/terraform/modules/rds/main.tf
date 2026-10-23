variable "project" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}
variable "db_password" {
  type      = string
  sensitive = true
}

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS storage and Performance Insights encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project}-${var.environment}-rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IV-10 Resolved — Placed in private subnets
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids
}

# IV-02 Resolved — Port 5432 restricted to internal VPC CIDR only
resource "aws_security_group" "db" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "Allow PostgreSQL inbound traffic from internal VPC only"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL access from internal VPC subnets"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow internal VPC outbound responses"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }
}

resource "aws_db_instance" "auth" {
  identifier                          = "${var.project}-${var.environment}-authdb"
  engine                              = "postgres"
  engine_version                      = "14.12"
  instance_class                      = "db.t3.micro"
  allocated_storage                   = 20
  db_name                             = "authdb"
  username                            = "authuser"
  password                            = var.db_password
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  publicly_accessible                 = false
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.rds.arn
  multi_az                            = true
  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  backup_retention_period             = 7
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.project}-${var.environment}-authdb-final"
  deletion_protection                 = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.rds.arn
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
}

resource "aws_db_instance" "transactions" {
  identifier                          = "${var.project}-${var.environment}-txdb"
  engine                              = "postgres"
  engine_version                      = "14.12"
  instance_class                      = "db.t3.micro"
  allocated_storage                   = 20
  db_name                             = "transactiondb"
  username                            = "txuser"
  password                            = var.db_password
  db_subnet_group_name                = aws_db_subnet_group.main.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  publicly_accessible                 = false
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.rds.arn
  multi_az                            = true
  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  backup_retention_period             = 7
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.project}-${var.environment}-txdb-final"
  deletion_protection                 = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.rds.arn
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
}