terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "null_resource" "install_observability_stack" {
  triggers = {
    script_hash = filemd5("/home/ubuntu/observability-platform/scripts/install.sh")
    always_run  = timestamp()
  }

  provisioner "local-exec" {
    command = "sudo bash /home/ubuntu/observability-platform/scripts/install.sh 2>&1 | tee /var/log/observability-install.log"
  }
}
