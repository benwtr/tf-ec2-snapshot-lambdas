# tf-ec2-snapshot-lambdas

Terraform modules for @xombiemp's EC2 snapshot lambdas


## Lambda functions

For documentation, refer to:

 * https://github.com/xombiemp/ec2-take-snapshots-lambda
 * https://github.com/xombiemp/ec2-purge-snapshots-lambda

The lambda functions and IAM roles embedded in these Terraform modules were copied entirely from @xombiemp's repos.


## Terraform Usage

### ec2-take-snapshots-lambda

#### Input Variables

 * `name` - (Optional) Override the default name of the lambda and associated resources to avoid duplicate resource names and provide meaningful labels
 * `volumes` - List of volume-ids, eg `\"vol-12345678\", \"vol-87654321\"` or `\"all\"` for all volumes. Populate this or volume_tags but not both.
 * `volume_tags` - Dictionary of tags to use to filter the volumes. eg `'key': 'value'` or `'key1': 'value1', 'key2': 'value2', ...`
 * `snapshot_tags` - Dictionary of tags to apply to the created snapshots. eg `'key': 'value'` or `'key1': 'value1', 'key2': 'value2', ...`
 * `region` - AWS region in which the volumes exist
 * `schedule_description` - eg _Fires at 07:40 UTC Tuesday-Saturday_
 * `schedule_expression` - eg `cron(40 9 ? * TUE-SAT *)`

#### Examples

Snapshot all volumes in the account that have a `do_backup` tag with the value `true`:
```
module "ec2-take-snapshots-lambda" {
  source = "github.com/benwtr/tf-ec2-snapshot-lambdas//ec2-take-snapshots-lambda"
  volume_tags = "'do_backup':'true"
  snapshot_tags = "'is_backup':'true'"
  region = "us-west-2"
}
```

Or for example, if you wanted to backup a Jenkins instance:
```
module "snapshot_jenkins_master_lambda" {
  source = "github.com/benwtr/tf-ec2-snapshot-lambdas//ec2-take-snapshots-lambda"
  name = "snapshot_jenkins_master"
  volumes = "\"vol-133a9bc1\""
  snapshot_tags = "'Name':'jenkins_master_snapshot'"
}
```

### ec2-purge-snapshots-lambda

#### Input Variables

 * `name` - (Optional) Override the default name of the lambda and associated resources to avoid duplicate resource names and provide meaningful labels
 * `volumes` - List of volume-ids, eg `\"vol-12345678\", \"vol-87654321\"` or `\"all\"` for all volumes. Populate this or tags but not both."
 * `tags` - Dictionary of tags to use to filter the snapshots. May specify multiple. eg `'key': 'value'` or `'key1': 'value1', 'key2': 'value2', ...`
 * `hours` - (Required) The number of hours to keep ALL snapshots
 * `days` - (Required) The number of days to keep ONE snapshot per day
 * `weeks` - (Required) The number of weeks to keep ONE snapshot per week
 * `months` - (Required) The number of months to keep ONE snapshot per month
 * `region` - AWS region in which snapshots exist eg "us-east-1"
 * `timezone` - The timezone in which daily snapshots will be kept at midnight eg "America/Denver", default is "UTC"
 * `schedule_description` - eg _Run script hourly_
 * `schedule_expression` - eg `cron(0 * * * ? *)`

#### Examples

In `us-west-2`, for snapshots with tag `is_backup` set to `true`, keep all snapshots for 48 hours, one every 24 hours for 30 days, one per week for 10 weeks, and one per month for 2 years:
```
module "ec2-purge-snapshots-lambda" {
  source = "github.com/benwtr/tf-ec2-snapshot-lambdas//ec2-purge-snapshots-lambda"
  tags = "'is_backup':'true'"
  region = "us-west-2"
  hours = "48"
  days = "30"
  weeks = "10"
  months = "24"
}
```
