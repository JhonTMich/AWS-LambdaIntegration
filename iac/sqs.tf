resource "aws_sqs_queue" "dlq" {
  name                      = "image-processor-${terraform.workspace}-image-dlq"
  message_retention_seconds = 1209600 
}

resource "aws_sqs_queue" "main_queue" {
  name                       = "image-processor-${terraform.workspace}-image-queue"
  visibility_timeout_seconds = 360   
  message_retention_seconds  = 86400 
  receive_wait_time_seconds  = 20    

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
resource "aws_sqs_queue_policy" "s3_to_sqs_policy" {
  queue_url = aws_sqs_queue.main_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.images_bucket.arn
          }
        }
      }
    ]
  })
}