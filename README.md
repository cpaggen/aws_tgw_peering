# VPC Peering + TGW Peering Project

Terraform code that creates a reasonably complex topology intermixing VPC peering, TGW routing, TGW peering, internet access.
!! This plan deploys items on AWS that are *not* free of charge

## Description

This TF plan creates 3 VPCs in eu-central-1 (VPC east, west, hub) each with one CIDR block and one subnet all in unique AZs.
* VPC east is 10.30.10.0/24 (subnet is /28)
* VPC west is 10.20.10.0/24 (subnet is /28)     
* VPC hub  is 10.10.10.0/24 (subnet is /28)     

The plan also creates a fourth VPC in eu-west-1 (VPC remote) again with one CIDR block and one subnet.
* VPC remote is 10.99.99.0/24

The code creates a full mesh between east-west-hub using VPC peering with routing configured correctly.
Each VPC is attached to an IGW, and each subnet uses that IGW for internet access.

The code spins up one EC2 instance in each VPC with a public and private IP provided in output of this plan.
The share keypair (see below) is copied by Terraform to each instance to ensure any-to-any SSH access between instances.

The plan then creates one TGW per region, and sets up TGW peering. 
One route table is created per TGW with propagation enabled. 
* the remote VPC points to the local (west) TGW for 10.0.0.0/8
* the 'hub' VPC points to the local (central) TGW for 10.99.99.0/24

## Diagram
![AWS topology diagram](http://github.com/cpaggen/blob/master/aws_tgw_peering/diagram.png?raw=true)

## Getting Started

### Dependencies

You need one AWS account with full access to eu-central-1 and eu-west-1.

* The plan assumes a keypair exists across regions eu-central-1 and eu-west-1
* Create a keypair first, and use this code to copy it to all regions
```
## Import keypair in all regions (requires AWS CLI)
ssh-keygen -y -f frankfurt-keypair-one.pem > ./frankfurt-keypair-one.pub
AWS_REGIONS="$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
for each_region in ${AWS_REGIONS} ; do aws ec2 import-key-pair --key-name terraform-key --public-key-material file://./frankfurt-keypair-one.pub --region $each_region ; done
```

You can of course copy the keypair manually to both regions.

### Variables

None! The code uses locals only.

