data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "vpn" {
  name   = "${var.name}-vpn-sg"
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Environment = "${var.name}-vpn"
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # IPSec
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "template_file" "bootstrap" {
  template = "${file("${path.module}/_files/bootstrap.tmpl.sh")}"

  vars {
    vpc_cidr     = "${var.vpc_cidr}"
    vpc_dns      = "${cidrhost(cidrsubnet(var.vpc_cidr, 8, 0),2)}"
    vpc_domain   = "${var.name}"
    vpn_hostname = "vpn0"
    vpn_rightip  = "${cidrsubnet(var.vpc_cidr, 8, 250)}"

    vpn_psk            = "${coalesce(var.vpn_psk, replace(uuid(), "-", ""))}"
    vpn_xauth_user     = "${coalesce(var.vpn_user, var.name)}"
    vpn_xauth_password = "${coalesce(var.vpn_password, replace(uuid(), "-", ""))}"
  }

  ## These vars, these tiny vars... if left default will shift on each run...
  ## Nicht so viel Spaß...
  lifecycle {
    ignore_changes = ["vars.vpn_psk", "vars.vpn_xauth_password"]
  }
}

resource "aws_instance" "vpn" {
  ami                         = "${data.aws_ami.ubuntu.id}"
  instance_type               = "${var.vpn_instance_type}"
  subnet_id                   = "${aws_subnet.public.id}"
  vpc_security_group_ids      = ["${aws_security_group.vpn.id}"]
  associate_public_ip_address = true
  key_name                    = "${var.key_name}"
  user_data                   = "${template_file.bootstrap.rendered}"

  ## A few of these fields are due to...
  ## https://github.com/hashicorp/terraform/issues/5956
  lifecycle {
    ignore_changes = ["user_data", "associate_public_ip_address", "source_dest_check"]
  }

  tags {
    Name        = "vpn0-${var.name}"
    Environment = "${var.name}"
  }
}

resource "aws_route53_record" "vpn0" {
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "vpn0.${var.name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_instance.vpn.private_ip}"]

  lifecycle {
    ignore_changes = ["records.#"]
  }
}

resource "template_file" "test_user_data" {
  count    = 1
  template = "${file("bootstrap.tmpl.sh")}"

  vars {
    hostname   = "test${count.index}"
    bucket_url = "${module.vpc_lab.bucket_url}"
  }
}