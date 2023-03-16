resource "aws_vpc" "my_vpc" {
  cidr_block = var.cidr
  tags = {
    "Name" : "My VPC"
  }
}

resource "aws_security_group" "application_security_group" {
  name        = "application_security_group"
  description = "allow on port 8080"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port        = 3000
    to_port          = 3000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

data "aws_ami" "app_ami" {
  most_recent = true
  name_regex  = "webApp-*"
  owners      = [var.owners]
}

resource "aws_subnet" "public_subnet" {
  count                   = var.subnet_count
  cidr_block              = cidrsubnet(var.cidr, 8, count.index)
  vpc_id                  = aws_vpc.my_vpc.id
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  map_public_ip_on_launch = "true"
  tags = {
    "Name" : "Subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = var.subnet_count
  cidr_block        = cidrsubnet(var.cidr, 8, var.subnet_count + count.index)
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  tags = {
    "Name" : "Subnet-${var.subnet_count + count.index}"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    "Name" : "Internet Gateway"
  }
}

resource "aws_route" "routes" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = var.destination_cidr_block
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    "Name" : "Public Route Table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    "Name" : "Private Route Table"
  }
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = var.subnet_count
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet[0].id, aws_subnet.private_subnet[1].id]

  tags = {
    Name = "RDS Subnet Group"
  }
}

resource "aws_security_group" "database" {
  name   = "database_security_group"
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application_security_group.id]
  }

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application_security_group.id]
  }

  tags = {
    Name = "Database Security Group"
  }
}

resource "aws_db_parameter_group" "rds_parameter_group" {
  name   = "rds-parameter-group"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_instance" "csye6225" {
  identifier             = "csye6225"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "14.1"
  username               = "csye6225"
  db_name                = "csye6225"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.rds_parameter_group.name
  publicly_accessible    = false
  skip_final_snapshot    = true
}

// This will output the database endpoint
output "database_endpoint" {
  description = "The endpoint of the database"
  value       = aws_db_instance.csye6225.endpoint
}

resource "random_id" "bucket_name" {
  byte_length = 8
}

resource "aws_s3_bucket" "s3BucketConfig" {
  bucket        = "shreyas-${var.profile}-${random_id.bucket_name.hex}"
  // acl           = "private"
  force_destroy = true

  lifecycle_rule {
    id      = "long-term"
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.s3BucketConfig.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [
    aws_s3_bucket.s3BucketConfig
  ]
}

resource "aws_s3_bucket_acl" "my_bucket_acl" {
  bucket = aws_s3_bucket.s3BucketConfig.id
  acl    = "private"
}

resource "aws_iam_role" "ec2AccessRole" {
  name = "EC2-CSYE6225"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "WebApp-S3" {
  name        = "WebApp-S3"
  description = "Connect Ec2 to S3 bucket"
  policy      = <<-EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "sts:AssumeRole",
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.s3BucketConfig.bucket}",
                "arn:aws:s3:::${aws_s3_bucket.s3BucketConfig.bucket}/*"
            ]
        }
    ]
    }
    EOF

}

resource "aws_iam_role_policy_attachment" "S3PolicyAttach" {
  role       = aws_iam_role.ec2AccessRole.name
  policy_arn = aws_iam_policy.WebApp-S3.arn
}

resource "aws_iam_instance_profile" "s3Profile" {
  name = "s3Profile"
  role = aws_iam_role.ec2AccessRole.name
}

resource "aws_instance" "web_app" {
  instance_type           = "t2.micro"
  ami                     = data.aws_ami.app_ami.id
  vpc_security_group_ids  = [aws_security_group.application_security_group.id]
  subnet_id               = aws_subnet.public_subnet[0].id
  disable_api_termination = false
  iam_instance_profile    = aws_iam_instance_profile.s3Profile.name
  user_data               = <<-EOF
    #! /bin/bash
    echo "whatsup"
    /bin/echo "{\"host\":\"${aws_db_instance.csye6225.endpoint}\",\"username\":\"${aws_db_instance.csye6225.username}\",\"password\":\"${var.db_password}\",\"s3\":\"${aws_s3_bucket.s3BucketConfig.bucket}\",\"database\":\"${aws_db_instance.csye6225.db_name}\",\"port\":5432}" >> /home/ec2-user/config.json
  EOF
  # root disk
  root_block_device {
    volume_size           = "20"
    volume_type           = "gp2"
    encrypted             = true
    delete_on_termination = true
  }
  # data disk
  ebs_block_device {
    device_name           = "/dev/xvda"
    volume_size           = "50"
    volume_type           = "gp2"
    encrypted             = true
    delete_on_termination = true
  }
}

resource "aws_route53_record" "recordName" {
  zone_id = var.hostedzoneid
  name    = var.hostzonename
  type    = "A"
  ttl     = "60"
  records = ["${chomp(aws_instance.web_app.public_ip)}"]
}