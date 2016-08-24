variable "name" {
  default = "ec2-purge-snapshots"
  description = "Override the default name of the lambda and associated resources to avoid duplicate resource names and provide meaningful labels"
}

variable "volumes" {
  default = ""
  description = "List of volume-ids, eg [\"vol-12345678\", \"vol-87654321\"] or \"all\" for all volumes"
}

variable "tags" {
  default = ""
  description = "Dictionary of tags to use to filter the snapshots. May specify multiple. eg {'key': 'value'} or {'key1': 'value1', 'key2': 'value2', ...}"
}

variable "hours" {
  default = "0"
  description = "The number of hours to keep ALL snapshots"
}

variable "days" {
  default = "0"
  description = "The number of days to keep ONE snapshot per day"
}

variable "weeks" {
  default = "0"
  description = "The number of weeks to keep ONE snapshot per week"
}

variable "months" {
  default = "0"
  description = "The number of months to keep ONE snapshot per month"
}

variable "region" {
  default = "us-east-1"
  description = "AWS region in which the volumes exist"
}

variable "timezone" {
  default = "UTC"
  description = "The timezone in which daily snapshots will be kept at midnight"
}

variable "schedule_description" {
  default = "Run script hourly"
}

variable "schedule_expression" {
  default = "cron(0 * * * ? *)"
}

data "template_file" "ec2-purge-snapshots-lambda-script" {
  template = "${file("${path.module}/ec2-purge-snapshots-lambda.py.tpl")}"
  vars {
    volumes = "${var.volumes}"
    tags = "${var.tags}"
    hours = "${var.hours}"
    days = "${var.days}"
    weeks = "${var.weeks}"
    months = "${var.months}"
    region = "${var.region}"
    timezone = "${var.timezone}"
  }
}

resource "random_id" "random_zip_filename" {
  byte_length = 16
  keepers = {
    lambda-script = "${data.template_file.ec2-purge-snapshots-lambda-script.rendered}"
  }
}

resource "archive_file" "ec2-purge-snapshots-lambda-script-zip" {
  type = "zip"
  source_content = "${random_id.random_zip_filename.keepers.lambda-script}"
  source_content_filename = "ec2-purge-snapshots-lambda.py"
  output_path = "/tmp/${random_id.random_zip_filename.b64}.zip"
}

resource "aws_iam_role" "ec2-purge-snapshots-role" {
  name = "${var.name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2-purge-snapshots-policy" {
  name = "${var.name}-policy"
  role = "${aws_iam_role.ec2-purge-snapshots-role.id}"
  policy = <<EOF
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
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_lambda_function" "ec2-purge-snapshots" {
  filename = "/tmp/${random_id.random_zip_filename.b64}.zip"
  function_name = "${var.name}"
  role = "${aws_iam_role.ec2-purge-snapshots-role.arn}"
  handler = "ec2-purge-snapshots-lambda.main"
  source_code_hash = "${base64sha256(file("/tmp/${random_id.random_zip_filename.b64}.zip"))}"
  runtime = "python2.7"
  memory_size = "128"
  timeout = "10"
  depends_on = ["archive_file.ec2-purge-snapshots-lambda-script-zip"]
}

resource "aws_cloudwatch_event_rule" "ec2-purge-snapshots-schedule" {
  name = "${var.name}-schedule"
  description = "${var.schedule_description}"
  schedule_expression = "${var.schedule_expression}"
}

resource "aws_cloudwatch_event_target" "ec2-purge-snapshots-schedule-target" {
  rule = "${aws_cloudwatch_event_rule.ec2-purge-snapshots-schedule.name}"
  target_id = "${var.name}"
  arn = "${aws_lambda_function.ec2-purge-snapshots.arn}"
}

resource "aws_lambda_permission" "allow-cloudwatch-to-call-ec2-purge-snapshots" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.ec2-purge-snapshots.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.ec2-purge-snapshots-schedule.arn}"
}
