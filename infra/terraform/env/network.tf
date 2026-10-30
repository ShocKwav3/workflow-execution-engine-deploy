locals {
  public_subnets = {
    public1 = { cidr = "10.0.0.0/20", az_id = "use1-az1" }
    public2 = { cidr = "10.0.16.0/20", az_id = "use1-az2" }
  }

  private_subnets = {
    private1 = { cidr = "10.0.128.0/20", az_id = "use1-az1" }
    private2 = { cidr = "10.0.144.0/20", az_id = "use1-az2" }
  }
}

resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:flow logs bill CloudWatch ingestion; cost; the environment lives only during a session

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wee-vpc"
  }
}

# Adopts the VPC's default security group and removes its rules, so a resource without a group gets no access.
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id               = aws_vpc.main.id
  cidr_block           = each.value.cidr
  availability_zone_id = each.value.az_id

  tags = {
    Name                     = "wee-subnet-${each.key}-${each.value.az_id}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id               = aws_vpc.main.id
  cidr_block           = each.value.cidr
  availability_zone_id = each.value.az_id

  tags = {
    Name = "wee-subnet-${each.key}-${each.value.az_id}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wee-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wee-rtb-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "wee-nat-eip"
  }
}

# One NAT gateway serves both AZs to save cost; AZ 2 loses egress if AZ 1 fails.
resource "aws_nat_gateway" "main" {
  availability_mode = "zonal"
  connectivity_type = "public"
  subnet_id         = aws_subnet.public["public1"].id
  allocation_id     = aws_eip.nat.id

  tags = {
    Name = "wee-nat"
  }

  # The NAT gateway needs the attached internet gateway but reads none of its attributes.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wee-rtb-private"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Image layers in ECR are stored in S3, so node pulls skip the NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "wee-vpce-s3"
  }
}
