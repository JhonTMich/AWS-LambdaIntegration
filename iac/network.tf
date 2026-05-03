resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "vpc-${terraform.workspace}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = { Name = "igw-${terraform.workspace}" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true # Automáticamente asigna IPs públicas
  tags = { Name = "public-a-${terraform.workspace}" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
  tags = { Name = "public-b-${terraform.workspace}" }
}

resource "aws_eip" "nat_a" { domain = "vpc" }
resource "aws_eip" "nat_b" { domain = "vpc" }

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { Name = "nat-a-${terraform.workspace}" }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { Name = "nat-b-${terraform.workspace}" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-2a"
  tags = { Name = "private-a-${terraform.workspace}" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-2b"
  tags = { Name = "private-b-${terraform.workspace}" }
}

resource "aws_route_table" "private_rt_a" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
}
resource "aws_route_table_association" "private_a_assoc" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_rt_a.id
}

resource "aws_route_table" "private_rt_b" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
}
resource "aws_route_table_association" "private_b_assoc" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_rt_b.id
}

resource "aws_security_group" "sg_upload_lambda" {
  name        = "upload-lambda-sg-${terraform.workspace}" 
  description = "Security Group para Upload Lambda"
  vpc_id      = aws_vpc.main_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_crop_lambda" {
  name        = "crop-lambda-sg-${terraform.workspace}" 
  description = "Security Group para Crop Lambda"
  vpc_id      = aws_vpc.main_vpc.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_vpce_sqs" {
  name        = "vpce-sqs-sg-${terraform.workspace}" 
  description = "Security Group para SQS VPC Endpoint"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [
      aws_security_group.sg_upload_lambda.id, 
      aws_security_group.sg_crop_lambda.id
    ]
  }
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.main_vpc.id
  service_name      = "com.amazonaws.us-east-2.s3" 
  vpc_endpoint_type = "Gateway"

  route_table_ids   = [aws_route_table.private_rt_a.id, aws_route_table.private_rt_b.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = [
          aws_s3_bucket.images_bucket.arn,
          "${aws_s3_bucket.images_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_vpc_endpoint" "sqs_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  service_name        = "com.amazonaws.us-east-2.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids  = [aws_security_group.sg_vpce_sqs.id]
}