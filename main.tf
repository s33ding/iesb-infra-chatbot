terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "student_count" {
  description = "Number of student instances"
  type        = number
  default     = 10
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

# DynamoDB table for credentials
resource "aws_dynamodb_table" "credentials" {
  name           = "student-credentials"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "student_name"

  attribute {
    name = "student_name"
    type = "S"
  }

  tags = {
    Name = "IESB Student Credentials"
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "student_role" {
  name = "iesb-student-role"

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

# IAM policy for Bedrock access only
resource "aws_iam_role_policy" "bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.student_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "student_profile" {
  name = "iesb-student-profile"
  role = aws_iam_role.student_role.name
}

# Security group
resource "aws_security_group" "student_sg" {
  name_prefix = "iesb-student-"
  description = "Security group for IESB student instances"
  vpc_id      = "vpc-08f71cff199dc1fc6"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8888
    to_port     = 8888
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
    Name = "IESB Student Security Group"
  }
}

# User data script
locals {
  user_data = base64encode(<<-EOF
#!/bin/bash
apt-get update
apt-get install -y python3 python3-pip git

# Install Python packages
pip3 install langchain boto3 streamlit jupyter pandas numpy matplotlib scikit-learn

# Create student user
useradd -m -s /bin/bash student
echo "student:TempPassword123!" | chpasswd

# Setup Jupyter
sudo -u student pip3 install --user jupyter
echo "c.NotebookApp.ip = '0.0.0.0'" > /home/student/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.open_browser = False" >> /home/student/.jupyter/jupyter_notebook_config.py

# Start Jupyter as service
cat > /etc/systemd/system/jupyter.service << EOL
[Unit]
Description=Jupyter Notebook
After=network.target

[Service]
Type=simple
User=student
WorkingDirectory=/home/student
ExecStart=/home/student/.local/bin/jupyter notebook
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl enable jupyter
systemctl start jupyter
EOF
  )
}

# Random passwords for students
resource "random_password" "student_passwords" {
  count   = var.student_count
  length  = 8
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Console passwords with dot prefix
resource "random_string" "console_passwords" {
  count   = var.student_count
  length  = 7
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# EC2 instances
resource "aws_instance" "student_instances" {
  count                         = 1
  ami                          = "ami-0c398cb65a93047f2" # Ubuntu 22.04 LTS
  instance_type                = "t3.large"
  key_name                     = aws_key_pair.student_key.key_name
  vpc_security_group_ids       = [aws_security_group.student_sg.id]
  subnet_id                    = "subnet-0a8fdc075bd605e6a" # Public Subnet 1
  iam_instance_profile         = aws_iam_instance_profile.student_profile.name
  associate_public_ip_address  = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip unzip
    sudo pip3 install boto3 faiss-cpu numpy pandas langgraph
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker ubuntu
  EOF
  )

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  tags = {
    Name = "chatbot"
  }
}

# Key pair
resource "aws_key_pair" "student_key" {
  key_name   = "iesb-student-key"
  public_key = file("./iesb-student-key.pub")
}

# Store credentials in DynamoDB
resource "aws_dynamodb_table_item" "credentials" {
  count      = var.student_count
  table_name = aws_dynamodb_table.credentials.name
  hash_key   = aws_dynamodb_table.credentials.hash_key

  item = jsonencode({
    student_name = {
      S = "Student-${count.index + 1}"
    }
    instance_id = {
      S = aws_instance.student_instances[0].id
    }
    username = {
      S = "student"
    }
    password = {
      S = random_password.student_passwords[count.index].result
    }
    public_ip = {
      S = aws_instance.student_instances[0].public_ip
    }
    cli_access_key = {
      S = aws_iam_access_key.student_cli_keys[count.index].id
    }
    cli_secret_key = {
      S = aws_iam_access_key.student_cli_keys[count.index].secret
    }
    console_username = {
      S = aws_iam_user.student_console_users[count.index].name
    }
    console_password = {
      S = aws_iam_user_login_profile.student_console_login[count.index].password
    }
    login_url = {
      S = "https://console.aws.amazon.com/"
    }
  })
}

# Console users for AWS Console access
resource "aws_iam_user" "student_console_users" {
  count = var.student_count
  name  = "chatbot-student-${count.index + 1}"
}

# Console login profiles
resource "aws_iam_user_login_profile" "student_console_login" {
  count                   = var.student_count
  user                    = aws_iam_user.student_console_users[count.index].name
  password_reset_required = false
}

# Attach Bedrock policy to console users
resource "aws_iam_user_policy" "student_console_bedrock" {
  count = var.student_count
  name  = "bedrock-access"
  user  = aws_iam_user.student_console_users[count.index].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach EC2 read-only policy to console users
resource "aws_iam_user_policy_attachment" "student_ec2_readonly" {
  count      = var.student_count
  user       = aws_iam_user.student_console_users[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# EC2 Instance Connect policy for chatbot instance only
resource "aws_iam_user_policy" "student_ec2_connect" {
  count = var.student_count
  name  = "ec2-instance-connect-chatbot"
  user  = aws_iam_user.student_console_users[count.index].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Name" = "chatbot"
            "ec2:osuser" = ["ubuntu", "ec2-user"]
          }
        }
      }
    ]
  })
}

# CLI access keys
resource "aws_iam_access_key" "student_cli_keys" {
  count = var.student_count
  user  = aws_iam_user.student_console_users[count.index].name
}

# Outputs
output "sns_topic_arn" {
  value = "arn:aws:sns:us-east-1:248189947068:dataiesb-chatbot"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.credentials.name
}

output "instance_ips" {
  value = aws_instance.student_instances[0].public_ip
}
