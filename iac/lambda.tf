data "archive_file" "upload_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/upload-lambda"
  output_path = "${path.module}/upload-lambda.zip"
}

data "archive_file" "crop_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/crop-lambda"
  output_path = "${path.module}/crop-lambda.zip"
}

resource "aws_cloudwatch_log_group" "upload_log" {
  name              = "/aws/lambda/upload-lambda-${terraform.workspace}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "crop_log" {
  name              = "/aws/lambda/crop-lambda-${terraform.workspace}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "upload_role" {
  name               = "upload-lambda-role-${terraform.workspace}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "upload_vpc_access" {
  role       = aws_iam_role.upload_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "upload_s3_policy" {
  name = "s3-upload-policy"
  role = aws_iam_role.upload_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.images_bucket.arn}/uploads/*"
    }]
  })
}

resource "aws_iam_role" "crop_role" {
  name               = "crop-lambda-role-${terraform.workspace}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "crop_vpc_access" {
  role       = aws_iam_role.crop_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "crop_strict_policy" {
  name = "crop-strict-policy"
  role = aws_iam_role.crop_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.images_bucket.arn}/uploads/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.images_bucket.arn}/processed/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.main_queue.arn
      }
    ]
  })
}

resource "aws_lambda_function" "upload_lambda" {
  function_name    = "upload-lambda-${terraform.workspace}"
  filename         = data.archive_file.upload_zip.output_path
  source_code_hash = data.archive_file.upload_zip.output_base64sha256
  role             = aws_iam_role.upload_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 256
  timeout          = 30

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_upload_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET     = aws_s3_bucket.images_bucket.id
      UPLOAD_PREFIX = "uploads/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.upload_log]
}

resource "aws_lambda_function" "crop_lambda" {
  function_name    = "crop-lambda-${terraform.workspace}"
  filename         = data.archive_file.crop_zip.output_path
  source_code_hash = data.archive_file.crop_zip.output_base64sha256
  role             = aws_iam_role.crop_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  memory_size      = 512
  timeout          = 60

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.sg_crop_lambda.id]
  }

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.images_bucket.id
      PROCESSED_PREFIX = "processed/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.crop_log]
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = aws_sqs_queue.main_queue.arn
  function_name                      = aws_lambda_function.crop_lambda.arn
  batch_size                         = 5
  function_response_types            = ["ReportBatchItemFailures"]
}