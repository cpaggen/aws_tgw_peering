##############################################
# PROVIDERS
##############################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.4"
    }
  }
}

provider "aws" {
  region     = "eu-central-1"
  alias      = "eu-central-1"
  access_key = ""
  secret_key = ""
}

provider "aws" {
  region     = "eu-west-1"
  alias      = "eu-west-1"
  access_key = ""
  secret_key = ""
}

##############################################
# Local variables
##############################################

locals {
  tgwname = "tgw-cpaggen"
  rulesmap = {
    "HTTP" = {
      port        = 80,
      cidr_blocks = ["0.0.0.0/0"],
    }
    "SSH" = {
      port        = 22,
      cidr_blocks = ["0.0.0.0/0"],
    }
  }
  vpcs = [
    {
      name = "hub",
      cidr_block = "10.10.10.0/24"
    },
    {
      name = "east",
      cidr_block = "10.30.10.0/24"
    },
    {
      name = "west",
      cidr_block = "10.20.10.0/24"
    },
  ]
  subnets = [
    {
      az = "eu-central-1a",
      cidr = "10.10.10.0/28",
      parent = "hub"
    },
    {
      az = "eu-central-1b",
      cidr = "10.30.10.0/28",
      parent = "east"
    },
    {
      az = "eu-central-1c",
      cidr = "10.20.10.0/28",
      parent = "west"
    },
  ]
  routes = [
    {
      dest = "10.20.10.0/24" 
      gw = aws_vpc_peering_connection.westToHub.id
      rt = 0
    },
    {
      dest = "10.30.10.0/24" 
      gw = aws_vpc_peering_connection.eastToHub.id
      rt = 0
    },
    {
      dest = "10.10.10.0/24" 
      gw = aws_vpc_peering_connection.eastToHub.id
      rt = 1
    },
    {
      dest = "10.10.10.0/24" 
      gw = aws_vpc_peering_connection.westToHub.id
      rt = 2
    },
    {
      dest = "10.20.10.0/24" 
      gw = aws_vpc_peering_connection.eastToWest.id
      rt = 1
    },
    {
      dest = "10.30.10.0/24" 
      gw = aws_vpc_peering_connection.eastToWest.id
      rt = 2
    },
    {
      dest = "10.99.99.0/24"
      gw = aws_vpc_peering_connection.westToHub.id
      rt = 2
    },
    {
      dest = "10.99.99.0/24"
      gw = aws_vpc_peering_connection.eastToHub.id
      rt = 1
    }
  ]
  tags = {
    owner    = "cpaggen"
    automated = "true"
  }
  remoteCidrBlock = "10.99.99.0/24"
  remoteSubnet    = "10.99.99.0/28"
  remoteAz        = "eu-west-1a"
}

##############################################
# DATA sources
##############################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ami" "amazon_linux_remote" {
  provider = aws.eu-west-1
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}

##############################################
# VPCs
##############################################

resource "aws_vpc" "remotevpc" {
  provider   = aws.eu-west-1
  cidr_block = local.remoteCidrBlock
  instance_tenancy = "default"
  tags = {
    Name = "remote VPC for TGW testing",
    Owner = "cpaggen"
  }
}

resource "aws_vpc" "myvpc" {
  for_each = {
    for index, vpc in local.vpcs: index => vpc
  }
  cidr_block = each.value.cidr_block
  instance_tenancy     = "default"
  tags = {
    Name = each.value.name,
    Owner = "cpaggen"
  }
}

##############################################
# Security Groups
##############################################

resource "aws_security_group" "sg" {
  for_each = aws_vpc.myvpc
  vpc_id = each.value.id

  dynamic "ingress" {
    for_each = local.rulesmap
    content {
      description = ingress.key # HTTP or SSH
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  ingress {
    from_port   = 8 # the ICMP type number for 'Echo'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0 # the ICMP type number for 'Echo Reply'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cpaggen-sg"
  }
}

resource "aws_security_group" "remotesg" {
  provider   = aws.eu-west-1
  vpc_id = aws_vpc.remotevpc.id
  ingress {
    description      = "SSH from anywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 8 # the ICMP type number for 'Echo'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0 # the ICMP type number for 'Echo Reply'
    to_port     = 0 # the ICMP code
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
 
  tags = {
    Name = "remote-sg"
  }
}


##############################################
# VPC subnets
##############################################

resource "aws_subnet" "subnet" {
  for_each = {
    for index, subnet in local.subnets: index => subnet
  }
  cidr_block = each.value.cidr
  availability_zone = each.value.az
  vpc_id                  = aws_vpc.myvpc[each.key].id
  map_public_ip_on_launch = false
  tags = {
    Name = "subnet-${each.value.az}-${each.value.parent}"
  }
}

resource "aws_subnet" "remotesubnet" {
  provider = aws.eu-west-1
  cidr_block = local.remoteSubnet
  availability_zone = local.remoteAz
  vpc_id = aws_vpc.remotevpc.id
  tags = {
    Owner = "cpaggen"
    Name = "subnet-remotesubnet-${local.remoteSubnet}"
  }
}


##############################################
# VPC peering
##############################################

resource "aws_vpc_peering_connection" "eastToHub" {
  tags = {
    Name = "east-to-hub"
  }
  peer_vpc_id   = aws_vpc.myvpc[1].id
  vpc_id        = aws_vpc.myvpc[0].id
  auto_accept   = true
}

resource "aws_vpc_peering_connection" "westToHub" {
  tags = {
    Name = "west-to-hub"
  }
  peer_vpc_id   = aws_vpc.myvpc[2].id
  vpc_id        = aws_vpc.myvpc[0].id
  auto_accept   = true
}

resource "aws_vpc_peering_connection" "eastToWest" {
  tags = {
    Name = "east-to-west"
  }
  peer_vpc_id   = aws_vpc.myvpc[1].id
  vpc_id        = aws_vpc.myvpc[2].id
  auto_accept   = true
}


##############################################
# Internet Gateways
##############################################

resource "aws_internet_gateway" "igw" {
  for_each = aws_vpc.myvpc
  vpc_id = each.value.id 
  tags = {
    Name = "igw-${each.value.tags_all.Name}"
  }
}

resource "aws_internet_gateway" "remoteigw" {
  provider = aws.eu-west-1
  vpc_id = aws_vpc.remotevpc.id
  tags = {
    Name = "igw-remote"
  }
}


##############################################
# Route tables and entries (non-TGW)
##############################################

resource "aws_route_table" "rt" {
  for_each = aws_vpc.myvpc
  vpc_id = each.value.id
  tags   = {
    Name = "rt-${each.value.tags_all.Name}"
  }
}

resource "aws_route_table" "remotert" {
  vpc_id = aws_vpc.remotevpc.id
  provider = aws.eu-west-1
  tags = {
    Name = "rt-remote"
    Owner = "cpaggen"
  }
}

resource "aws_main_route_table_association" "remotertassoc" {
  #subnet_id = aws_subnet.remotesubnet.id
  vpc_id = aws_vpc.remotevpc.id
  provider = aws.eu-west-1
  route_table_id = aws_route_table.remotert.id
}

resource "aws_main_route_table_association" "rtassoc" {
  count = length(local.subnets) 
  #subnet_id      = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.rt[count.index].id
  vpc_id = aws_vpc.myvpc[count.index].id
}

resource "aws_route" "remoteRoutes" {
  destination_cidr_block = "10.0.0.0/8"
  provider = aws.eu-west-1
  transit_gateway_id = aws_ec2_transit_gateway.west-tgw.id
  route_table_id = aws_route_table.remotert.id
  depends_on = [aws_ec2_transit_gateway.west-tgw]
}

resource "aws_route" "defaultRoutes" {
  count = length(aws_route_table.rt)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[count.index].id
  route_table_id         = aws_route_table.rt[count.index].id
}

resource "aws_route" "remoteDefaultRoute" {
  provider = aws.eu-west-1
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.remoteigw.id
  route_table_id = aws_route_table.remotert.id
}

resource "aws_route" "vpcRoutes" {
  for_each = {
    for index, route in local.routes: index => route
  }
  destination_cidr_block    = each.value.dest
  vpc_peering_connection_id = each.value.gw
  route_table_id            = aws_route_table.rt[each.value.rt].id
}

resource "aws_route" "hubToRemote" {
  destination_cidr_block = "10.99.99.0/24"
  route_table_id = aws_route_table.rt[0].id
  transit_gateway_id = aws_ec2_transit_gateway.central-tgw.id
  depends_on = [aws_ec2_transit_gateway.central-tgw]
}

##############################################
# EC2 instances
##############################################

resource "aws_instance" "ec2remote" {
  provider = aws.eu-west-1
  ami = data.aws_ami.amazon_linux_remote.id
  instance_type = "t3.micro"
  key_name = "terraform-key"
  vpc_security_group_ids = [aws_security_group.remotesg.id]
  subnet_id = aws_subnet.remotesubnet.id
  associate_public_ip_address = true
  provisioner "file" {
    source      = "./frankfurt-keypair-one.pem"
    destination = "~/terraform-key"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("frankfurt-keypair-one.pem")
      host        = self.public_ip
    }
   }
}
 
resource "aws_instance" "ec2" {
  count = length(local.vpcs)
  associate_public_ip_address = true
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = "terraform-key"
  vpc_security_group_ids      = [aws_security_group.sg[count.index].id]
  subnet_id                   = aws_subnet.subnet[count.index].id
  provisioner "file" {
    source      = "./frankfurt-keypair-one.pem"
    destination = "~/terraform-key"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("frankfurt-keypair-one.pem")
      host        = self.public_ip
    }
   }

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "cpaggen-terraform-${count.index}"
  }
}


##############################################
# Transit Gateways
##############################################

resource "aws_ec2_transit_gateway" "central-tgw" {
  description                     = "Transit Gateway EU-central"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags = {
    Name = "TGW Central - cpaggen"
  }
  auto_accept_shared_attachments = "enable"
}

resource "aws_ec2_transit_gateway" "west-tgw" {
  provider = aws.eu-west-1
  description                     = "Transit Gateway EU-west"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags = {
    Name = "TGW Remote - cpaggen"
  }
  auto_accept_shared_attachments = "enable"
}


##############################################
# Transit Gateway Peering
##############################################

data "aws_region" "peer" {
  provider = aws.eu-west-1
} 

# initiator is Frankfurt (eu-central-1)
resource "aws_ec2_transit_gateway_peering_attachment" "central-west" {
  peer_region             = data.aws_region.peer.name
  peer_transit_gateway_id = aws_ec2_transit_gateway.west-tgw.id
  transit_gateway_id      = aws_ec2_transit_gateway.central-tgw.id

  tags = {
    Name = "TGW Peering - terraformed"
  }
}

# acceptor is Ireland (eu-west-1)
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "west" {
  provider = aws.eu-west-1
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.central-west.id
}

##############################################
# Transit Gateway VPC attachments
##############################################

resource "aws_ec2_transit_gateway_vpc_attachment" "central-hub" {
  subnet_ids         = [aws_subnet.subnet[0].id]
  transit_gateway_id = aws_ec2_transit_gateway.central-tgw.id
  vpc_id             = aws_vpc.myvpc[0].id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags               = {
    Name             = "hub-vpc-to-tgw"
  }
  depends_on = [aws_ec2_transit_gateway.central-tgw]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "west-remote" {
  provider = aws.eu-west-1
  subnet_ids         = [aws_subnet.remotesubnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.west-tgw.id
  vpc_id             = aws_vpc.remotevpc.id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags               = {
    Name             = "remote-vpc-to-tgw"
  }
  depends_on = [aws_ec2_transit_gateway.west-tgw]
}

##############################################
# Transit Gateway Routes
##############################################


resource "aws_ec2_transit_gateway_route_table" "central-rt" {
  transit_gateway_id = aws_ec2_transit_gateway.central-tgw.id
  depends_on = [aws_ec2_transit_gateway.central-tgw]
}
  
resource "aws_ec2_transit_gateway_route_table" "west-rt" {
  provider = aws.eu-west-1
  transit_gateway_id = aws_ec2_transit_gateway.west-tgw.id
  depends_on = [aws_ec2_transit_gateway.west-tgw]
}

resource "aws_ec2_transit_gateway_route_table_association" "central-rtassoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.central-hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.central-rt.id
}

resource "aws_ec2_transit_gateway_route_table_association" "west-rtassoc" {
  provider = aws.eu-west-1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.west-remote.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.west-rt.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "central-propag" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.central-hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.central-rt.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "west-propag" {
  provider = aws.eu-west-1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.west-remote.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.west-rt.id
}

##############################################
# OUTPUTS
##############################################

output "instance_ip_addresses" {
  description = "EC2 instances (East/West/Hub) private IPs"
  value = {
    for instance in aws_instance.ec2:
      instance.id => instance.private_ip
  }
}

output "instance_pubip_addresses" {
  description = "EC2 instances (East/West/Hub) public IPs"
  value = {
    for instance in aws_instance.ec2:
      instance.id => instance.public_ip
  }
}

output "remoteInstance_ip_address" {
  description = "EC2 instance (remote) private IP"
  value = aws_instance.ec2remote.private_ip
}

output "remoteInstance_pubip_address" {
  description = "EC2 instance (remote) public IP"
  value = aws_instance.ec2remote.public_ip
}


