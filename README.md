# terraform-hoss-aws
Repo containing terraform for deploying the resources required by a Hoss server when deployed in AWS

Note, currently this just deploys all the required resources. You must still manually configure the server.

## Example Usage
Terraform will recognize unprefixed github.com URLs and interpret them automatically as Git repository sources. You can use this repo directly as shown below:


```
# Get the latest ubuntu AMI ID
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Add the hoss server module
module "hoss-server" {
  source = "github.com/gigantum/terraform-hoss-aws"
  server_ami_id = data.aws_ami.ubuntu.id

  vpc_id = "vpc-1234"
  subnet_id = "subnet-1234"

  buckets = [{
      "hos-default-bucket" = {name = "hos-default-bucket", versioning = false}
      
  }]

  server_domain_name = "hoss.my-domain.com"
  server_instance_type = "m5.large"
  server_key_name = "prod-key"
  ssh_cidr_block = "123.123.123.123/32"
  region = "us-east-1"

}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| vpc_id | ID of the VPC in which the server instance should be deployed | `string` | `null` | yes |
| subnet_id | ID of the subnet in which the server instance should be deployed | `string` | `null` | yes |
| buckets | A set of buckets to create to use for Namespaces in the Hoss server. At least 1 bucket is required. <br>The field `name` is the desired name of the bucket to create and use. The field `versioning` is a boolean indicating if bucket versioning should be turned on| `map(object)` | `null` | yes |
| server_domain_name | The FQDN that will be used to resolve the server | `string` | `null` | yes |
| server_ami_id | AMI ID to use when creating the server instance| `string` | `null` | yes |
| server_key_name | Name of the keypair to use when creating the server instance| `string` | `null` | yes |
| server_instance_type | The desired instance type to use for the server | `string` | `t3.large` | no |
| server_iam_instance_profile | IAM instance profile to assign to the server. Note, the Hoss does not use this profile directly yet, but loads credentials from configuration. This is primarily used for instance management.| `string` | `null` | no |
| server_private_ip | Private IP to assign to the server instead of an automatically assigned IP. | `string` | `null` | no |
| server_volume_size_gb | Size of server root volume in GBs | `string` | `48` | no |
| ssh_cidr_block | CIDR block from which ssh will be allowed | `string` | `null` | yes |
| region | Region into which non-global resources will be deployed | `string` | `us-east-1` | no |
| tags | Additional tags to apply to created resources | `map(string)` | `{}` | no |
| tags_instance | Additional tags to add to created instance | `map(string)` | `{}` | no |



## Outputs

| Name | Description |
|------|-------------|
| api_notification_queue_name | Name of the API notification FIFO queue. Set the `settings.queue_name` field in a `core.queues` entry to this value|
| buckets | List of buckets to be used for Namespaces|
| bucket_event_queue_arns | ARNs for bucket event queues (one created for each bucket created). Set the `notification_arn` field in a `core.object_stores` entry to this value|
| sts_role_arn | ARNs for the STS credential role. Set the `role_arn` field in a `core.object_stores` entry to this value|
| server_ip_public | Public IP of the server.|
| server_ip_private | Private IP of the server.  |
| server_id | ID of the server |
| server_security_group_id | ID of the security group used with the deployed server. Useful if running behind an ALB and need to allow traffic to the instance.|


## Using Versioned Buckets
It is generally recommended to enable versioning on your buckets to protect against accidental deletion. Currently the Hoss and `hoss-client` library do not directly
expose object versions, but this could be easily done if interacting manually with S3.

If bucket versioning is enabled, you'll likely want to set up lifecycle polices to prevent versions from stacking up and deleted objects from sticking around.

A recommended configuration is to have two policies. The first removes all non-current versions except for the latest one. This prevents versions from collecting
and increasing storage cost. The second removes all non-current versions and expired delete markers. If a delete marker has no non-current versions it is expired and
will be removed with the policy is evaluated again. More details on how to configure these policies can be found in the [Hoss admin docs](https://hybrid-object-store.readthedocs.io/en/latest/installation/prepare.html#prepare-required-infrastructure)
