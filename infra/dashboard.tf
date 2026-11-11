# Same namespace as app.metrics.namespace in the app.
locals {
  metrics_namespace = "wishifai-${var.candidate_number}"
}

# One dashboard, four rows: business, latency, infrastructure, application.
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "wishifai-${var.candidate_number}"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Business
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "Analyses (count)"
          region = var.region
          stat   = "Sum"
          period = 300
          view   = "timeSeries"
          metrics = [
            [local.metrics_namespace, "wishifai.gift.suggestions.count", { label = "Analyses" }]
          ]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "Gift suggestions per analysis"
          region = var.region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            [local.metrics_namespace, "wishifai.gift.suggestions.avg", { label = "Avg" }],
            [local.metrics_namespace, "wishifai.gift.suggestions.max", { label = "Max", stat = "Maximum" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "Bedrock tokens per call"
          region = var.region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            [local.metrics_namespace, "wishifai.bedrock.tokens.avg", "type", "input", { label = "Input" }],
            [local.metrics_namespace, "wishifai.bedrock.tokens.avg", "type", "output", { label = "Output" }]
          ]
        }
      },

      # Row 2: Latency (where does the time go?)
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Rekognition vs Bedrock latency (ms)"
          region = var.region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            [local.metrics_namespace, "wishifai.rekognition.duration.avg", "outcome", "success", { label = "Rekognition" }],
            [local.metrics_namespace, "wishifai.bedrock.duration.avg", "outcome", "success", { label = "Bedrock" }]
          ]
        }
      },
      {
        # SEARCH, since Spring adds many dimensions (method, status, uri...).
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "HTTP /api/analyze latency (ms)"
          region = var.region
          period = 300
          view   = "timeSeries"
          metrics = [
            [{ id = "e1", label = "Avg", expression = "SEARCH('Namespace=\"${local.metrics_namespace}\" MetricName=\"http.server.requests.avg\" uri=\"/api/analyze\"', 'Average', 300)" }],
            [{ id = "e2", label = "Max", expression = "SEARCH('Namespace=\"${local.metrics_namespace}\" MetricName=\"http.server.requests.max\" uri=\"/api/analyze\"', 'Maximum', 300)" }]
          ]
        }
      },

      # Row 3: Infrastructure (free AWS/ECS metrics)
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "ECS CPU and memory (%)"
          region = var.region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "default", "ServiceName", aws_ecs_express_gateway_service.app.service_name, { label = "CPU" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "default", "ServiceName", aws_ecs_express_gateway_service.app.service_name, { label = "Memory" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title  = "Running tasks"
          region = var.region
          stat   = "Maximum"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "LiveTaskCount", "ClusterName", "default", "ServiceName", aws_ecs_express_gateway_service.app.service_name, { label = "Tasks" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # Row 4: Application (Spring Boot Actuator / JVM)
      {
        # Heap is split in several pools (Eden, Survivor, Tenured), so we sum them.
        type = "metric", x = 0, y = 18, width = 12, height = 6
        properties = {
          title  = "JVM heap used (bytes)"
          region = var.region
          period = 300
          view   = "timeSeries"
          metrics = [
            [{ id = "e1", label = "Heap used", expression = "SUM(SEARCH('Namespace=\"${local.metrics_namespace}\" MetricName=\"jvm.memory.used.value\" area=\"heap\"', 'Average', 300))" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 18, width = 12, height = 6
        properties = {
          title  = "GC pause time (ms per 5 min)"
          region = var.region
          period = 300
          view   = "timeSeries"
          metrics = [
            [{ id = "e1", label = "GC pause", expression = "SUM(SEARCH('Namespace=\"${local.metrics_namespace}\" MetricName=\"jvm.gc.pause.sum\"', 'Sum', 300))" }]
          ]
        }
      }
    ]
  })
}
