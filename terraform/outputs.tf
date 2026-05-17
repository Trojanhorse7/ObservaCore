output "grafana_url" {
  value = "http://localhost:3000"
  description = "Grafana dashboard URL"
}

output "prometheus_url" {
  value = "http://localhost:9090"
  description = "Prometheus URL"
}

output "alertmanager_url" {
  value = "http://localhost:9093"
  description = "Alertmanager URL"
}

output "demo_app_url" {
  value = "http://localhost:8080"
  description = "Demo app URL"
}
