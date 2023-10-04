
resource "aws_security_group" "secgrp-rds" {

  name        = "secgrp-rds"
  description = "Allow MySQL Port"
  vpc_id = module.vpc.vpc_id
 
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS"
  }
}

resource "random_string" "username" {
  length           = 16
  special          = false
  override_special = "/@£$"
}


resource "random_string" "password" {
  length           = 16
  special          = false
  override_special = "/@£$"
}


resource "aws_db_subnet_group" "rds" {
    name = "rds"
    subnet_ids = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
}


resource "aws_db_instance" "rds" {
 
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  allocated_storage    = 10
  storage_type         = "gp2"
  db_name              = "wordpress"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql5.7"
  publicly_accessible = true
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.secgrp-rds.id]
  db_subnet_group_name = aws_db_subnet_group.rds.name
}


output "rds_address" {
  value = aws_db_instance.rds.address
}

output "rds_endpoint" {
  value = aws_db_instance.rds.endpoint
}

output "rds_username" {
  value = aws_db_instance.rds.username
}

output "rds_password" {
  sensitive = true
  value = aws_db_instance.rds.password
}

