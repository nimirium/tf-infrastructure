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
