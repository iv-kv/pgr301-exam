# Topic the alarm publishes to.
resource "aws_sns_topic" "alarms" {
  name = "wishifai-${var.candidate_number}-alarms"
}

# AWS sends a confirmation email first. No notifications until it is confirmed.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Bedrock is ~80-85 % of response time, so slow Bedrock means a slow service.
resource "aws_cloudwatch_metric_alarm" "bedrock_slow" {
  alarm_name        = "wishifai-${var.candidate_number}-bedrock-slow"
  alarm_description = "Bedrock average latency above 30 s for 3 minutes in a row"

  namespace   = local.metrics_namespace
  metric_name = "wishifai.bedrock.duration.avg"
  dimensions = {
    outcome = "success"
  }

  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 30000 # ms; normal is ~15 s

  # Low traffic: minutes without calls are not a problem.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
