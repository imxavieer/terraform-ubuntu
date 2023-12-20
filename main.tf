provider "aws" {
  region = "ap-southeast-1"
}

# Create a VPC
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "gw" {

  # Attach the internet gateway to the VPC
  vpc_id = aws_vpc.prod-vpc.id
}

# Create a custom route table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  # Set all IPV4 traffic to be sent to the internet gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  # Set all IPV6 traffic to be sent to the internet gateway
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prod"
  }
}

# Create a subnet
resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "prod-subnet"
  }
}

# Associate the subnet with the route table  
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# Create a variable of type list(number) containing the port numbers
variable "ports" {
  type = list(number)
  description = "List of ports"
  default = [ 22, 80, 443 ]
}

# Create a security group
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.prod-vpc.id

  dynamic "ingress" {
    # loop through the list containing the port numbers for inbound rules
    for_each = var.ports 
    content {
      from_port = ingress.value
      to_port = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }
  dynamic "egress" {
    # loop through the list containing the port numbers for outbound rules
    for_each = var.ports 
    content {
      from_port = egress.value
      to_port = egress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "Allow Web"
  }
}

# Create a network interface
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# Assign an elastic IP to the network interface
resource "aws_eip" "one" {
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  # An internet gateway needs to be deployed first before an elastic IP gets deployed
  # Use depends_on to set an explicit dependency on the IGW
  depends_on = [ aws_internet_gateway.gw ]
}

# Create an Ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
  ami = "ami-0fa377108253bf620"
  instance_type = "t2.micro"
  # must be the same availability zone as subnet, as it will lead to connection issues
  availability_zone = "ap-southeast-1a"
  key_name = "main-key"

  # Associate the network interface to the instance
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  # A bootstrap script to configure the instance at the FIRST launch
  # This means launching commands when the machine starts
  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo your very first web server > /var/www/html/index.html'
                EOF
  tags = {
    Name = "web-server"
  }
}
