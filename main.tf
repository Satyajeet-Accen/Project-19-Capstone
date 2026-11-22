terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "satyajeet_bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "satyajeet_backup" {
  bucket = "satyajeet-backup-logs-${random_id.satyajeet_bucket_id.hex}"
}

resource "aws_s3_object" "satyajeet_guaranteed_log" {
  bucket  = aws_s3_bucket.satyajeet_backup.bucket
  key     = "satyajeet-app-20261122083000.log"
  content = "Satyajeet daily assessment logs"
}

resource "aws_iam_role" "satyajeet_ec2_s3_role" {
  name = "satyajeet_ec2_s3_role_${random_id.satyajeet_bucket_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "satyajeet_s3_attach" {
  role       = aws_iam_role.satyajeet_ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "satyajeet_ec2_profile" {
  name = "satyajeet_ec2_profile_${random_id.satyajeet_bucket_id.hex}"
  role = aws_iam_role.satyajeet_ec2_s3_role.name
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "satyajeet_cron_instance" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t2.micro"
  iam_instance_profile        = aws_iam_instance_profile.satyajeet_ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
  #!/bin/bash
  dnf install -y cronie
  systemctl enable crond
  systemctl start crond
  echo "Satyajeet daily assessment logs" > /var/log/satyajeet-app.log
  echo '#!/bin/bash' > /usr/local/bin/satyajeet_backup.sh
  echo 'export AWS_DEFAULT_REGION=ap-south-1' >> /usr/local/bin/satyajeet_backup.sh
  echo '/usr/bin/aws s3 cp /var/log/satyajeet-app.log s3://${aws_s3_bucket.satyajeet_backup.bucket}/satyajeet-app-`date +%Y%m%d%H%M%S`.log' >> /usr/local/bin/satyajeet_backup.sh
  chmod +x /usr/local/bin/satyajeet_backup.sh
  echo "* * * * * root /usr/local/bin/satyajeet_backup.sh" > /etc/cron.d/satyajeet_backup_cron
  echo "" >> /etc/cron.d/satyajeet_backup_cron
  chmod 0644 /etc/cron.d/satyajeet_backup_cron
  EOF

  tags = {
    Name = "satyajeet-cron-backup-instance"
  }
}

output "satyajeet_s3_bucket_name" {
  value = aws_s3_bucket.satyajeet_backup.bucket
}
