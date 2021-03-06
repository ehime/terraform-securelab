resource "template_file" "bucket_policy" {
  template = "${file("${path.module}/_files/policy.tmpl.json")}"

  vars {
    vpc_id      = "${aws_vpc.main.id}"
    bucket_name = "${var.name}-lab-bucket"
  }
}

resource "aws_vpc_endpoint" "bucket" {
  vpc_id          = "${aws_vpc.main.id}"
  service_name    = "com.amazonaws.${aws_s3_bucket.lab.region}.s3"
  route_table_ids = ["${aws_route_table.public.id}"]
}

resource "aws_s3_bucket" "lab" {
  bucket        = "${var.name}-lab-bucket"
  force_destroy = true
  acl           = "private"
  policy        = "${template_file.bucket_policy.rendered}"

  tags {
    Environment = "${var.name}"
  }
}
