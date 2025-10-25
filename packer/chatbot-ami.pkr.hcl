packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "chatbot" {
  ami_name      = "chatbot-base-{{timestamp}}"
  instance_type = "t3.micro"
  region        = "us-east-1"
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  
  ssh_username = "ubuntu"
}

build {
  name = "chatbot-ami"
  sources = [
    "source.amazon-ebs.chatbot"
  ]

  provisioner "shell" {
    script = "install.sh"
  }
}
