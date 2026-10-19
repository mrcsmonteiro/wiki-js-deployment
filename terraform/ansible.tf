# The null_resource + local-exec that ran ansible-playbook from Terraform has been
# removed. Configuration no longer runs as a side effect of `terraform apply`;
# it moves to the Packer build (Task 8).
#
# `destroy = false` drops the resource from state without destroying it, so no
# provisioner runs and nothing on the host changes. This block can be deleted
# once the change has been applied.
removed {
  from = null_resource.ansible_provisioning

  lifecycle {
    destroy = false
  }
}
