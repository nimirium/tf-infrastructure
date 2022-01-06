provider "aws" {
  region = "us-east-1"
  profile = "personal"  # The name of the key in ~/.aws/credentials
}

variable "project_name" {
  type = string
}

variable "basic_ami" {
  type = string
  default = "ami-09d95fab7fff3776c"
}

resource "aws_vpc" "main_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = var.project_name
  }
}

resource "aws_internet_gateway" "main_gw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = var.project_name
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = var.project_name
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "172.16.0.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = var.project_name
  }
}

resource "aws_eip" "private_elastic_ip" {
  vpc      = true
}

resource "aws_nat_gateway" "main_nat_gw" {
  allocation_id = aws_eip.private_elastic_ip.id
  subnet_id     = aws_subnet.private_subnet.id

  tags = {
    Name = var.project_name
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.main_gw]
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  # allow public subnet access to private subnet
  route {
    cidr_block = aws_subnet.public_subnet.cidr_block
    gateway_id = "local"
  }

  # allow private subnet outbound only access to the internet
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.main_nat_gw.id
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  # allow internet access - outbound and inbound
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_gw.id
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_network_acl" "public_acl" {
  vpc_id = aws_vpc.main_vpc.id
  subnet_ids = [aws_subnet.public_subnet.id]

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80  # http
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443  # https
    to_port    = 443
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22  # ssh
    to_port    = 22
  }

  # Allows inbound return traffic from hosts on the internet that are responding to requests originating in the subnet.
  ingress {
    protocol   = "tcp"
    rule_no    = 400
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {  # deny all other inbound traffic
    protocol   = "tcp"
    rule_no    = 500
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80  # http
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443  # https
    to_port    = 443
  }

  egress {  # Allows outbound MongoDB access to DB in private subnet
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = aws_subnet.private_subnet.cidr_block
    from_port  = 27017  # mongo
    to_port    = 27017
  }

  egress {  # Allows outbound responses to clients on the internet
    protocol   = "tcp"
    rule_no    = 400
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  egress {  # Allows outbound SSH access to instances in your private subnet
    protocol   = "tcp"
    rule_no    = 500
    action     = "allow"
    cidr_block = aws_subnet.private_subnet.cidr_block
    from_port  = 22  # ssh
    to_port    = 22
  }

  egress {  # Denies all outbound IPv4 traffic not already handled by a preceding
    protocol   = "all"
    rule_no    = 9999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0  # ssh
    to_port    = 65535
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_network_acl" "private_acl" {
  vpc_id = aws_vpc.main_vpc.id
  subnet_ids = [aws_subnet.private_subnet.id]

  ingress {  # allow mongo access from public subnet
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_subnet.public_subnet.cidr_block
    from_port  = 27017  # mongodb
    to_port    = 27017
  }

  ingress {  # deny mongo access any other place
    protocol   = "tcp"
    rule_no    = 150
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 27017  # mongodb
    to_port    = 27017
  }

  ingress {  # allow ssh access from public subnet
    protocol   = "200"
    rule_no    = 200
    action     = "allow"
    cidr_block = aws_subnet.public_subnet.cidr_block
    from_port  = 22  # ssh
    to_port    = 22
  }

  # Allows inbound return traffic from the NAT device in the public subnet for requests originating in the private subnet
  ingress {
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {  # don't allow other inbound traffic
    protocol   = "all"
    rule_no    = 9999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {  # Allows outbound responses to the public subnet
    protocol   = "tcp"
    rule_no    = 300
    action     = "allow"
    cidr_block = aws_subnet.public_subnet.cidr_block
    from_port  = 32768
    to_port    = 65535
  }

  egress {
    protocol   = "all"
    rule_no    = 9999
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  tags = {
    Name = var.project_name
  }
}

resource "aws_instance" "web_server" {
  ami = var.basic_ami
  subnet_id = aws_subnet.public_subnet.id
  instance_type = "t2.micro"
  tags = {
    Name: var.project_name
  }
}

resource "aws_instance" "db_server" {
  ami = var.basic_ami
  subnet_id = aws_subnet.private_subnet.id
  instance_type = "t2.micro"
  tags = {
    Name: var.project_name
  }
}
