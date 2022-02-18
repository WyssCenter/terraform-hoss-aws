output "api_notification_queue_name" {
  description = "Queue name for the API notification FIFO queue. Set in core.queues.settings.queue_name"
  value       = aws_sqs_queue.api_notification_queue.name
}

output "buckets" {
  description = "Name of buckets created. Set in core.namespace.bucket"
  value = [
    for b in aws_s3_bucket.buckets : b.bucket
  ]
}

output "bucket_event_queue_arns" {
  description = "Arn for bucket event queue. Set in core.object_stores.notification_arn"
  value = [
    for beq in aws_sqs_queue.bucket_event_queue : beq.arn
  ]
}

output "sts_role_arn" {
  description = "Arn for STS credential assume role. Set in core.object_stores.role_arn"
  value       = aws_iam_role.hoss_user_sts_role.arn
}

output "server_ip_public" {
  description = "Public IP address for deployed server"
  value       = aws_instance.hoss_server.public_ip
}

output "server_ip_private" {
  description = "Private IP address for deployed server"
  value       = aws_instance.hoss_server.private_ip
}

output "server_id" {
  description = "ID of the deployed server"
  value       = aws_instance.hoss_server.id
}

output "server_security_group_id" {
  description = "ID of the security group used with the deployed server"
  value       = aws_security_group.hoss_server_sg.id
}
