# Make sure the account ID is available
data "aws_caller_identity" "current" {}




# ### S3 Bucket and Queue Setup
resource "aws_s3_bucket" "buckets" {
  for_each = var.buckets

  bucket = each.value.name
  #acl    = "private"

  # cors rule is needed to let the Hoss file browser directly interact
  # with files in this bucket via a user's STS credentials.
  /*
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["HEAD", "GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["https://${var.server_domain_name}", "https://${var.server_domain_name}/"]
    expose_headers = ["ETag",
      "Content-Type",
      "Content-Length",
      "x-amz-meta-custom-header",
      "x-amz-server-side-encryption",
      "x-amz-request-id",
      "x-amz-delete-marker",
      "x-amz-id-2",
    "Date"]
    max_age_seconds = 3000
  }
  */

  /*
  versioning {
    enabled = each.value.versioning
  }
  */

  lifecycle {
    ignore_changes = [
      # Ignore changes to lifecycle_rule because this is expected to be
      # managed by the admin manually based on their preference. Also,
      # the recommended configuration is not fully supported in terraform
      # yet because you cannot specify the number of noncurrent objects to retain.
      lifecycle_rule,
    ]
  }

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )

}

resource "aws_s3_bucket_cors_configuration" "bucket_cors_configuration" {
  for_each    = aws_s3_bucket.buckets
  bucket      = each.value.id

  # cors rule is needed to let the Hoss file browser directly interact
  # with files in this bucket via a user's STS credentials.
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["HEAD", "GET", "POST", "PUT", "DELETE"]
    allowed_origins = ["https://${var.server_domain_name}", "https://${var.server_domain_name}/"]
    expose_headers = ["ETag",
      "Content-Type",
      "Content-Length",
      "x-amz-meta-custom-header",
      "x-amz-server-side-encryption",
      "x-amz-request-id",
      "x-amz-delete-marker",
      "x-amz-id-2",
    "Date"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  for_each    = aws_s3_bucket.buckets
  bucket      = each.value.id
  versioning_configuration {
    status = lookup(var.buckets,each.value.name).versioning
  }
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  for_each    = aws_s3_bucket.buckets
  bucket      = each.value.id
  acl         = "private"
}

resource "aws_s3_bucket_public_access_block" "bucket_block_public" {
  for_each = aws_s3_bucket.buckets

  bucket = each.value.id

  block_public_acls   = true
  block_public_policy = true
}

resource "aws_sqs_queue" "bucket_event_queue" {
  for_each = aws_s3_bucket.buckets

  name = "hoss-bucket-notifications-${each.value.bucket}"

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}",
      "Bucket"       = each.value.bucket
    })
  )
}

resource "aws_sqs_queue_policy" "bucket_event_queue_policy" {
  for_each = aws_sqs_queue.bucket_event_queue

  queue_url = each.value.id

  policy = <<POLICY
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Sid": "S3-notifications",
   "Effect": "Allow",
   "Principal": {
    "Service": "s3.amazonaws.com"
   },
   "Action": [
    "SQS:SendMessage"
   ],
   "Resource": "arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:${each.value.name}",
   "Condition": {
      "ArnLike": { "aws:SourceArn": "arn:aws:s3:*:*:${lookup(each.value.tags, "Bucket", "no-bucket-name-found")}" },
      "StringEquals": { "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}" }
   }
  }
 ]
}
POLICY
}

# Create a single FIFO queue to handle API notification 
resource "aws_sqs_queue" "api_notification_queue" {
  name       = "hoss-api-notification.fifo"
  fifo_queue = true

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

# ### S3 Bucket and Queue Setup





# ### IAM Policy and Role for STS Credential Generation
data "aws_iam_policy_document" "sts_creds_policy_document" {
  statement {
    sid = "HOSSUserSTSRolePolicy"

    effect = "Allow"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketNotification",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]

    resources = concat([for i, v in var.buckets : "arn:aws:s3:::${v.name}"], [for i, v in var.buckets : "arn:aws:s3:::${v.name}/*"])

  }
}

resource "aws_iam_policy" "sts_creds_policy" {
  name        = "hoss_sts_creds_policy"
  description = "Policy used by the Hoss to generate temporary S3 creds for users via STS"
  path        = "/"
  policy      = data.aws_iam_policy_document.sts_creds_policy_document.json

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

resource "aws_iam_role" "hoss_user_sts_role" {
  name        = "hoss_user_sts_role"
  description = "Role assumed when the Hoss generates temporary S3 creds for users via STS"

  # Set max duration to 12 hours
  max_session_duration = 43200

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Action    = "sts:AssumeRole",
        Principal = { "AWS" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
    }]
  })

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

resource "aws_iam_policy_attachment" "hoss_user_sts_role_policy_attach" {
  name       = "hoss_user_sts_role_policy_attach"
  roles      = ["${aws_iam_role.hoss_user_sts_role.name}"]
  policy_arn = aws_iam_policy.sts_creds_policy.arn
}
# ### IAM Policy and Role for STS Credential Generation



# ### IAM Policy and Service Account User
data "aws_iam_policy_document" "service_account_policy_document" {
  statement {
    sid = "ServiceAccountCore"

    effect = "Allow"

    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "s3:DeleteObject",
      "s3:GetBucketNotification",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutBucketNotification",
      "s3:PutObject",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ListDeadLetterSourceQueues",
      "sqs:ListQueueTags",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]

    resources = concat([for i, v in var.buckets : "arn:aws:s3:::${v.name}"], [for i, v in var.buckets : "arn:aws:s3:::${v.name}/*"],
      ["arn:aws:sqs:*:${data.aws_caller_identity.current.account_id}:hoss-*"],
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/hoss-user-policy-*"])

  }

  statement {
    sid = "ServiceAccountCoreAssumeRole"

    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    resources = [aws_iam_role.hoss_user_sts_role.arn]

  }

  statement {
    sid = "ServiceAccountSyncListResources"

    effect = "Allow"

    actions = [
      "iam:ListPolicies",
      "sqs:ListQueues",
      "sts:GetCallerIdentity"
    ]

    resources = ["*"]

  }
}

resource "aws_iam_policy" "service_account_policy" {
  name        = "hoss_service_account_policy"
  description = "Policy used by the Hoss service account"
  path        = "/"
  policy      = data.aws_iam_policy_document.service_account_policy_document.json

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

resource "aws_iam_user" "hoss_service_account_user" {
  name = "hoss_service_account"

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

resource "aws_iam_user_policy_attachment" "hoss_service_account_policy_attach" {
  user       = aws_iam_user.hoss_service_account_user.name
  policy_arn = aws_iam_policy.service_account_policy.arn
}
# ### IAM Policy and Service Acount User



# ### EC2 instance to run the server
data "aws_vpc" "hoss_vpc" {
  id = var.vpc_id
}

resource "aws_security_group" "hoss_server_sg" {
  name        = "hoss_server_sg"
  description = "Allow HTTP, HTTPS, and SSH for hoss server operation"
  vpc_id      = data.aws_vpc.hoss_vpc.id

  ingress {
    description = "TLS from public internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from public internet (redirects to TLS or used for ACME Challenge)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for admin access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ssh_cidr_block}"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = (merge(var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
    })
  )
}

resource "aws_instance" "hoss_server" {
  ami           = var.server_ami_id
  instance_type = var.server_instance_type
  key_name      = var.server_key_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = concat([aws_security_group.hoss_server_sg.id],var.security_group_ids)

  # Optional variables
  iam_instance_profile = var.server_iam_instance_profile
  private_ip           = var.server_private_ip

  root_block_device {
    volume_size = var.server_volume_size_gb

    tags = (merge(var.tags,
      { "HossResource" = "True",
        "HossServer"   = "${var.server_domain_name}"
        "Name"         = "hoss-server",
      })
    )
  }

  tags = (merge(
    var.tags_instance,
    var.tags,
    { "HossResource" = "True",
      "HossServer"   = "${var.server_domain_name}"
      "Name"         = "hoss-server",
    })
  )
}
# ### EC2 instance to run the server
