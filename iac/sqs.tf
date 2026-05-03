# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue

resource "aws_sqs_queue" "dlq" {
  name                      = "image-processor-${terraform.workspace}-image-dlq"
  message_retention_seconds = 1209600 # 14 días (en segundos)
}

# 2. Main Queue
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