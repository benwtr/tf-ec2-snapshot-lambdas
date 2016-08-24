variable "name" {
  default = "ec2-take-snapshots"
  description = "Override the default name of the lambda and associated resources to avoid duplicate resource names and provide meaningful labels"
}

variable "volumes" {
  default = ""
  description = "List of volume-ids, eg [\"vol-12345678\", \"vol-87654321\"] or \"all\" for all volumes. Populate this or volume_tags but not both."
}

variable "volume_tags" {
  default = ""
  description = "Dictionary of tags to use to filter the volumes. eg {'key': 'value'} or {'key1': 'value1', 'key2': 'value2', ...}"
}

variable "snapshot_tags" {
  default = ""
  description = "Dictionary of tags to apply to the created snapshots. eg {'key': 'value'} or {'key1': 'value1', 'key2': 'value2', ...}"
}

variable "region" {
  default = "us-east-1"
  description = "AWS region in which the volumes exist"
}

variable "schedule_description" {
  default = "Fires at 07:40 UTC Tuesday-Saturday"
}

variable "schedule_expression" {
  default = "cron(40 9 ? * 3-7 *)"
}

data "template_file" "ec2-take-snapshots-lambda-script" {
  template = "${file("${path.module}/ec2-take-snapshots-lambda.py.tpl")}"
  vars {
    volumes = "${var.volumes}"
    volume_tags = "${var.volume_tags}"
    snapshot_tags = "${var.snapshot_tags}"
    region = "${var.region}"
  }
}

resource "random_id" "random_zip_filename" {
  byte_length = 16
}

resource "archive_file" "ec2-take-snapshots-lambda-script-zip" {
  type = "zip"
  source_content = "${data.template_file.ec2-take-snapshots-lambda-script.rendered}"
  source_content_filename = "ec2-take-snapshots-lambda.py"
  output_path = "/tmp/${random_id.random_zip_filename.b64}.zip"
}

resource "aws_iam_role" "ec2-take-snapshots-role" {
  name = "${var.name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVolumeStatus",
        "ec2:DescribeVolumes",
        "ec2:DescribeSnapshots",
        "ec2:CreateSnapshot",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_lambda_function" "ec2-take-snapshots" {
  filename = "/tmp/${random_id.random_zip_filename.b64}.zip"
  function_name = "${var.name}"
  role = "${aws_iam_role.ec2-take-snapshots-role.arn}"
  handler = "${var.name}.main"
  source_code_hash = "${base64sha256(file("/tmp/${random_id.random_zip_filename.b64}.zip"))}"
  runtime = "python2.7"
  memory_size = "128"
  timeout = "10"

  # delete temp zip file
  provisioner "local-exec" {
    command = "rm /tmp/${random_id.random_zip_filename.b64}.zip"
  }
}

resource "aws_cloudwatch_event_rule" "ec2-take-snapshots-schedule" {
  name = "${var.name}-schedule"
  description = "${var.schedule_expression}"
  schedule_expression = "${var.schedule_description}"
}

resource "aws_cloudwatch_event_target" "ec2-take-snapshots-schedule-target" {
  rule = "${aws_cloudwatch_event_rule.ec2-take-snapshots-schedule.name}"
  target_id = "${var.name}"
  arn = "${aws_lambda_function.ec2-take-snapshots.arn}"
}

resource "aws_lambda_permission" "allow-cloudwatch-to-call-ec2-take-snapshots" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.ec2-take-snapshots.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.ec2-take-snapshots-schedule.arn}"
}
