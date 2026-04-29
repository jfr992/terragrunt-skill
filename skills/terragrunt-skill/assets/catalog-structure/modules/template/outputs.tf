# Output values from the module

output "id" {
  description = "The ID of the resource"
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "The ARN of the resource"
  value       = aws_s3_bucket.this.arn
}

output "name" {
  description = "The name of the resource"
  value       = aws_s3_bucket.this.bucket
}
