terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "null_resource" "install_base" {
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/01_base.sh"
  }
}

resource "null_resource" "install_prometheus" {
  depends_on = [null_resource.install_base]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/02_prometheus.sh"
  }
}

resource "null_resource" "install_node_exporter" {
  depends_on = [null_resource.install_prometheus]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/03_node_exporter.sh"
  }
}

resource "null_resource" "install_blackbox" {
  depends_on = [null_resource.install_node_exporter]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/04_blackbox.sh"
  }
}

resource "null_resource" "install_alertmanager" {
  depends_on = [null_resource.install_blackbox]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/05_alertmanager.sh"
  }
}

resource "null_resource" "install_loki" {
  depends_on = [null_resource.install_alertmanager]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/06_loki.sh"
  }
}

resource "null_resource" "install_tempo" {
  depends_on = [null_resource.install_loki]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/07_tempo.sh"
  }
}

resource "null_resource" "install_grafana" {
  depends_on = [null_resource.install_tempo]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/08_grafana.sh"
  }
}

resource "null_resource" "install_otel" {
  depends_on = [null_resource.install_grafana]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/09_otel.sh"
  }
}

resource "null_resource" "install_demo_app" {
  depends_on = [null_resource.install_otel]
  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/10_demo_app.sh"
  }
}
